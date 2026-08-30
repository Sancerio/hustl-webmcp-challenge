import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../domain/repositories/workout_repository.dart';
import '../../domain/models/workout_session.dart';
import '../../domain/models/workout_exercise.dart';
import '../../domain/models/workout_set.dart';
import '../../domain/models/exercise_timeline_event.dart';
import '../datasources/hustl_backend_workout_exercise_stats_api.dart';
import '../../../exercise_library/domain/repositories/exercise_repository.dart';
import '../../../exercise_library/domain/models/exercise.dart';
import '../../../../core/services/preferences_service.dart';
import '../../../../core/services/token_storage.dart';
import '../../../health_sync/data/writeback/workout_writeback_coordinator.dart';

typedef WorkoutSessionsEncoder =
    Future<String> Function(List<WorkoutSession> sessions);

String _encodeWorkoutSessions(List<WorkoutSession> sessions) {
  return jsonEncode(sessions.map((session) => session.toMap()).toList());
}

Future<String> _encodeWorkoutSessionsOffMain(List<WorkoutSession> sessions) {
  return compute(
    _encodeWorkoutSessions,
    sessions,
    debugLabel: 'workout-session-store-encode',
  );
}

/// Internal record of the best set for an exercise.
class _PrRecord {
  final double weight;
  final int reps;
  const _PrRecord(this.weight, this.reps);
}

class LocalWorkoutRepository
    implements WorkoutRepository, ReadOnlyWorkoutRepository {
  static const String _storageKey = 'workout_sessions_v1';
  // Tombstones recorded before mutating the main session payload so that deletes
  // still take effect even if the app is terminated before the larger JSON blob
  // is flushed to disk.
  static const String _localDeleteTombstonesKey =
      'workout_sessions_v1_delete_tombstones';
  // Explicit active-session pointer. Use an empty string to mean "no active
  // session", and null (key absent) to mean legacy behavior (derive from stored
  // sessions once, then persist the pointer).
  static const String _activeSessionIdKey =
      'workout_sessions_v1_active_session_id';
  static const String _hydrationPrefKey =
      'workout_sessions_v1_muscles_hydrated';
  static const String _assistedSignFixPrefKey =
      'workout_sessions_v1_assisted_sign_fixed';
  static const Duration _watchCapturePendingTimeout = Duration(minutes: 3);
  final Map<String, WorkoutSession> _sessions = {};
  final Map<String, Timer> _watchCapturePendingFallbackTimers = {};
  final Map<String, _PrRecord> _prCache = {};
  final Map<String, _PrRecord?> _remotePrCache = {};
  final Map<String, DateTime> _remotePrFetchedAt = {};
  static const Duration _remotePrTtl = Duration(minutes: 15);
  final Map<String, DateTime> _remotePrFailedAt = {};
  static const Duration _remotePrFailureBackoff = Duration(seconds: 30);
  HustlBackendWorkoutExerciseStatsApi? _remoteStatsApi;
  String? _remoteStatsToken;
  final Uuid _uuid = const Uuid();
  final HustlBackendWorkoutExerciseStatsApi Function(TokenStorage tokens)?
  _statsApiFactory;
  // Resolve lazily to ensure tests can register fakes before first use
  ExerciseRepository get _exerciseRepository =>
      GetIt.instance<ExerciseRepository>();
  WorkoutSession? _activeSessionCache;
  bool _activeSessionIdHydrated = false;
  String? _activeSessionIdPref;
  final int _maxSessions;
  final WorkoutSessionsEncoder _workoutSessionsEncoder;
  Future<void> _persistChain = Future<void>.value();
  int _persistGeneration = 0;
  Map<String, Exercise>? _exerciseLookupByName;
  Future<Map<String, Exercise>>? _exerciseLookupFuture;
  DateTime? _exerciseLookupFetchedAt;
  static const Duration _exerciseLookupTtl = Duration(hours: 12);
  // A forced catalog refresh is only useful when the cached lookup is actually
  // stale. Without this guard, hydrating a large history where many exercises
  // can't be resolved (custom/renamed/deleted entries with empty muscles) makes
  // EACH unresolvable exercise force a full `getAllExercises()` re-fetch, turning
  // a single cold-start read into an O(n) catalog-refetch storm that freezes the
  // web UI thread (no isolate for `compute`). Once the catalog has just been
  // (re)fetched, another force-refresh within this window is a no-op so the storm
  // collapses to a single fetch; genuinely stale catalogs (older than this) still
  // refresh exactly as before.
  static const Duration _exerciseLookupForceRefreshCooldown = Duration(
    minutes: 1,
  );

  LocalWorkoutRepository({
    int maxSessions = 500,
    HustlBackendWorkoutExerciseStatsApi Function(TokenStorage tokens)?
    statsApiFactory,
    WorkoutSessionsEncoder? workoutSessionsEncoder,
  }) : _maxSessions = maxSessions,
       _statsApiFactory = statsApiFactory,
       _workoutSessionsEncoder =
           workoutSessionsEncoder ?? _encodeWorkoutSessionsOffMain;

  static int _compareSessionsNewestFirst(WorkoutSession a, WorkoutSession b) {
    final byStart = b.startTime.compareTo(a.startTime);
    if (byStart != 0) return byStart;
    return b.id.compareTo(a.id);
  }

  Future<void>? _initFuture;
  Future<void> get _init async => _initFuture ??= _loadFromStorage();

  bool get _hasExerciseRepository =>
      GetIt.instance.isRegistered<ExerciseRepository>();

  Future<Map<String, Exercise>> _ensureExerciseLookup({
    bool forceRefresh = false,
  }) async {
    if (!_hasExerciseRepository) {
      _exerciseLookupByName = {};
      _exerciseLookupFetchedAt = DateTime.now();
      return _exerciseLookupByName!;
    }

    final now = DateTime.now();
    final isStale = _exerciseLookupFetchedAt == null
        ? true
        : now.difference(_exerciseLookupFetchedAt!) > _exerciseLookupTtl;

    // Collapse a force-refresh into a no-op when the catalog was (re)fetched very
    // recently: re-fetching the entire catalog once per unresolvable exercise is
    // what stalls large-history cold starts. A short cooldown keeps the
    // stale-recovery intent (a genuinely old catalog still refreshes) while
    // bounding the work to a single fetch per cold-start pass.
    final bool recentlyFetched =
        _exerciseLookupByName != null &&
        _exerciseLookupFetchedAt != null &&
        now.difference(_exerciseLookupFetchedAt!) <
            _exerciseLookupForceRefreshCooldown;
    final bool effectiveForceRefresh = forceRefresh && !recentlyFetched;

    if (!effectiveForceRefresh && _exerciseLookupByName != null && !isStale) {
      return _exerciseLookupByName!;
    }

    final previous = _exerciseLookupByName;
    final previousFetchedAt = _exerciseLookupFetchedAt;
    if (effectiveForceRefresh) {
      _exerciseLookupFuture = null;
      _exerciseLookupByName = null;
      _exerciseLookupFetchedAt = null;
    }

    if (_exerciseLookupFuture != null) {
      return _exerciseLookupFuture!;
    }

    _exerciseLookupFuture = () async {
      try {
        final all = await _exerciseRepository.getAllExercises();
        final map = <String, Exercise>{};
        for (final exercise in all) {
          final nameKey = exercise.name.toLowerCase();
          map.putIfAbsent(nameKey, () => exercise);
          final slug = exercise.slug;
          if (slug != null && slug.isNotEmpty) {
            map.putIfAbsent(slug.toLowerCase(), () => exercise);
          }
        }
        _exerciseLookupByName = map;
        _exerciseLookupFetchedAt = DateTime.now();
        return map;
      } catch (error) {
        if (previous != null) {
          _exerciseLookupByName = previous;
          _exerciseLookupFetchedAt = previousFetchedAt;
          return previous;
        }
        rethrow;
      } finally {
        _exerciseLookupFuture = null;
      }
    }();

    return _exerciseLookupFuture!;
  }

  Exercise? _findExerciseInLookup(
    Map<String, Exercise> lookup,
    String name, [
    String? slug,
  ]) {
    if (name.isNotEmpty) {
      final byName = lookup[name.toLowerCase()];
      if (byName != null) return byName;
    }
    if (slug != null && slug.isNotEmpty) {
      final bySlug = lookup[slug.toLowerCase()];
      if (bySlug != null) return bySlug;
    }
    return null;
  }

  List<String> _normalizeMuscles(Iterable<String> muscles) {
    final seen = <String>{};
    final result = <String>[];
    for (final muscle in muscles) {
      final trimmed = muscle.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (seen.add(key)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  ExerciseKind _parseKind(dynamic raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        return ExerciseKind.values.firstWhere(
          (e) => e.name.toLowerCase() == raw.toLowerCase(),
        );
      } catch (_) {
        return ExerciseKind.strength;
      }
    }
    if (raw is int) {
      return (raw >= 0 && raw < ExerciseKind.values.length)
          ? ExerciseKind.values[raw]
          : ExerciseKind.strength;
    }
    return ExerciseKind.strength;
  }

  ExerciseLoggingMode _parseLoggingMode(dynamic raw, ExerciseKind kind) {
    ExerciseLoggingMode fallback() => kind == ExerciseKind.cardio
        ? ExerciseLoggingMode.distanceDuration
        : ExerciseLoggingMode.weightReps;

    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return fallback();
      final compact = trimmed.toLowerCase().replaceAll(RegExp(r'[_\\s-]+'), '');
      switch (compact) {
        case 'weightreps':
          return ExerciseLoggingMode.weightReps;
        case 'distanceduration':
          return ExerciseLoggingMode.distanceDuration;
        case 'durationonly':
          return ExerciseLoggingMode.durationOnly;
      }
      try {
        return ExerciseLoggingMode.values.firstWhere(
          (e) => e.name.toLowerCase() == compact,
        );
      } catch (_) {
        return fallback();
      }
    }

    if (raw is int) {
      return (raw >= 0 && raw < ExerciseLoggingMode.values.length)
          ? ExerciseLoggingMode.values[raw]
          : fallback();
    }

    return fallback();
  }

  Exercise _mergeExerciseDetails(Exercise current, Exercise? resolved) {
    if (resolved == null) {
      return current;
    }
    final combinedMuscles = _normalizeMuscles([
      ...current.muscles,
      ...resolved.muscles,
    ]);
    final slug = (current.slug != null && current.slug!.isNotEmpty)
        ? current.slug
        : resolved.slug;
    final id = current.id ?? resolved.id;
    return current.copyWith(
      id: id,
      slug: slug,
      muscles: combinedMuscles.isNotEmpty ? combinedMuscles : current.muscles,
      kind: resolved.kind,
      loggingMode: resolved.loggingMode,
    );
  }

  String _keyForExercise(Exercise exercise) {
    final canonical = exercise.canonicalKey;
    if (canonical != null && canonical.isNotEmpty) {
      return canonical;
    }
    final name = exercise.name.trim().toLowerCase();
    if (name.isNotEmpty) {
      return name;
    }
    return exercise.name;
  }

  String _keyForName(String name, [String? slug]) {
    final canonical = Exercise.canonicalKeyFrom(name: name, slug: slug);
    if (canonical != null && canonical.isNotEmpty) {
      return canonical;
    }
    final normalized = name.trim().toLowerCase();
    return normalized.isNotEmpty ? normalized : name;
  }

  bool _matchesExercise(Exercise exercise, String name, [String? slug]) {
    return exercise.matchesIdentity(name: name, slug: slug);
  }

  bool _isAssistedExercise(String exerciseKey) {
    for (final session in _sessions.values) {
      for (final ex in session.exercises) {
        final key = _keyForExercise(ex.exercise);
        if (key == exerciseKey) {
          return ex.exercise.kind == ExerciseKind.assisted;
        }
      }
    }
    return false;
  }

  ExerciseLoggingMode? _loggingModeFromSessions(
    String exerciseKey,
    String exerciseName, [
    String? exerciseSlug,
  ]) {
    for (final session in _sessions.values) {
      for (final ex in session.exercises) {
        final key = _keyForExercise(ex.exercise);
        if (key == exerciseKey ||
            _matchesExercise(ex.exercise, exerciseName, exerciseSlug)) {
          return ex.exercise.loggingMode;
        }
      }
    }
    return null;
  }

  Future<bool> _usesWeightRepsLogging(
    String exerciseKey,
    String exerciseName, [
    String? exerciseSlug,
  ]) async {
    final sessionMode = _loggingModeFromSessions(
      exerciseKey,
      exerciseName,
      exerciseSlug,
    );
    if (sessionMode != null) {
      return sessionMode == ExerciseLoggingMode.weightReps;
    }

    if (_hasExerciseRepository) {
      try {
        final lookup = await _ensureExerciseLookup();
        final resolved = _findExerciseInLookup(
          lookup,
          exerciseName,
          exerciseSlug,
        );
        if (resolved != null) {
          return resolved.loggingMode == ExerciseLoggingMode.weightReps;
        }
      } catch (_) {
        // Keep legacy/no-catalog callers permissive; UI callers pass logging
        // mode directly and skip PR checks before reaching the repository.
      }
    }

    return true;
  }

  Future<Exercise> _hydrateExercise(Exercise exercise) async {
    final normalized = _normalizeMuscles(exercise.muscles);
    var updated = exercise;
    if (!listEquals(normalized, exercise.muscles)) {
      updated = updated.copyWith(muscles: normalized);
    }
    if (!_hasExerciseRepository) {
      return updated;
    }

    Map<String, Exercise> lookup;
    try {
      lookup = await _ensureExerciseLookup();
    } catch (_) {
      return updated;
    }
    Exercise? resolved = _findExerciseInLookup(
      lookup,
      updated.name,
      updated.slug,
    );

    if ((resolved == null || resolved.muscles.isEmpty) &&
        updated.muscles.isEmpty) {
      try {
        lookup = await _ensureExerciseLookup(forceRefresh: true);
        resolved = _findExerciseInLookup(lookup, updated.name, updated.slug);
      } catch (_) {
        return updated;
      }
    }

    return _mergeExerciseDetails(updated, resolved);
  }

  Future<WorkoutExercise> _hydrateWorkoutExercise(
    WorkoutExercise exercise,
  ) async {
    final hydrated = await _hydrateExercise(exercise.exercise);
    if (hydrated == exercise.exercise) {
      return exercise;
    }
    return exercise.copyWith(exercise: hydrated);
  }

  Future<WorkoutSession> _hydrateSession(WorkoutSession session) async {
    if (session.exercises.isEmpty) {
      return session;
    }
    final hydratedExercises = <WorkoutExercise>[];
    bool changed = false;
    for (final ex in session.exercises) {
      final hydrated = await _hydrateWorkoutExercise(ex);
      hydratedExercises.add(hydrated);
      if (hydrated != ex) {
        changed = true;
      }
    }
    if (!changed) {
      return session;
    }
    return session.copyWith(exercises: hydratedExercises);
  }

  Future<void> _loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final tombstones =
        prefs.getStringList(_localDeleteTombstonesKey) ?? const <String>[];
    final Set<String> tombstoneSet = tombstones.toSet();
    try {
      if (GetIt.instance.isRegistered<PreferencesService>()) {
        final deleted = await GetIt.instance<PreferencesService>()
            .getWorkoutsDeletedIds();
        tombstoneSet.addAll(deleted);
      }
    } catch (_) {
      // Ignore: local-only store should still load even if sync prefs fail.
    }
    final Set<String> storedIds = <String>{};
    bool foundTombstonedInStorage = false;

    final jsonString = prefs.getString(_storageKey);
    if (jsonString == null || jsonString.isEmpty) {
      if (tombstones.isNotEmpty) {
        await prefs.remove(_localDeleteTombstonesKey);
      }
      return;
    }
    final List<dynamic> data = jsonDecode(jsonString) as List<dynamic>;
    final bool hasExerciseRepo = _hasExerciseRepository;
    Map<String, Exercise> lookup = <String, Exercise>{};
    if (hasExerciseRepo) {
      try {
        lookup = await _ensureExerciseLookup();
      } catch (_) {
        lookup = <String, Exercise>{};
      }
    }
    bool didHydrate = false;

    for (final raw in data) {
      final map = raw as Map<String, dynamic>;
      final rawId = map['id'];
      final sessionId = rawId is String ? rawId : '';
      if (sessionId.isNotEmpty) {
        storedIds.add(sessionId);
      }
      if (sessionId.isNotEmpty && tombstoneSet.contains(sessionId)) {
        foundTombstonedInStorage = true;
        continue;
      }
      // Resolve exercises inside the session
      final List<dynamic> rawExercises =
          (map['exercises'] as List<dynamic>? ?? []);
      final List<WorkoutExercise> resolved = [];
      for (final re in rawExercises) {
        final exMap = re as Map<String, dynamic>;
        final exName = exMap['exerciseName'] as String? ?? '';
        final storedMusclesRaw = exMap['exerciseMuscles'];
        final storedMuscles = (storedMusclesRaw is List)
            ? storedMusclesRaw.whereType<String>().toList()
            : const <String>[];
        final normalizedMuscles = _normalizeMuscles(storedMuscles);
        if (!listEquals(normalizedMuscles, storedMuscles)) {
          didHydrate = true;
        }
        final slugRaw = exMap['exerciseSlug'];
        final normalizedSlug = (slugRaw is String && slugRaw.trim().isNotEmpty)
            ? slugRaw.trim()
            : null;
        if (slugRaw is String) {
          final trimmed = slugRaw.trim();
          if ((trimmed.isEmpty && slugRaw.isNotEmpty) || (trimmed != slugRaw)) {
            didHydrate = true;
          }
        }
        final exerciseId = exMap['exerciseId'] as String?;
        final kindRaw = exMap['exerciseKind'];
        final kind = _parseKind(kindRaw);
        final loggingModeRaw =
            exMap['exerciseLoggingMode'] ??
            exMap['loggingMode'] ??
            exMap['logging_mode'];
        var exercise = Exercise(
          id: exerciseId,
          name: exName,
          slug: normalizedSlug,
          muscles: normalizedMuscles,
          kind: kind,
          loggingMode: _parseLoggingMode(loggingModeRaw, kind),
        );
        if (hasExerciseRepo) {
          final resolvedExercise = _findExerciseInLookup(
            lookup,
            exName,
            normalizedSlug,
          );
          final merged = _mergeExerciseDetails(exercise, resolvedExercise);
          if (merged != exercise) {
            exercise = merged;
            didHydrate = true;
          }
        }
        resolved.add(WorkoutExercise.fromMap(exMap, exercise));
      }
      final session = WorkoutSession.fromMap(map, resolved);
      // Preserve stored dirty state; do not force dirty=true on load.
      _sessions[session.id] = session;
      if (session.endTime == null && !session.isCompleted) {
        _activeSessionCache ??= session;
      }
    }

    final now = DateTime.now();
    final Map<String, WorkoutSession> pendingUpdates = {};
    for (final entry in _sessions.entries) {
      final session = entry.value;
      // Only clean up pending capture flags for completed sessions.
      // During an active workout, HealthKit may not provide a UUID yet, and we don't want
      // to clear pending state based on an arbitrary time threshold.
      if (!session.isCompleted) continue;
      if (!session.watchCapturePending) continue;

      final hasWatchUuid =
          session.watchWorkoutUuid != null &&
          session.watchWorkoutUuid!.isNotEmpty;
      final pendingAt = session.watchCapturePendingAt;
      final isStale =
          pendingAt == null ||
          now.difference(pendingAt) > _watchCapturePendingTimeout;

      if (hasWatchUuid) {
        pendingUpdates[entry.key] = session.copyWith(
          capturedOnWatch: true,
          watchCapturePending: false,
          watchCapturePendingAt: null,
        );
        continue;
      }

      if (isStale) {
        pendingUpdates[entry.key] = session.copyWith(
          watchCapturePending: false,
          watchCapturePendingAt: null,
        );
      }
    }
    if (pendingUpdates.isNotEmpty) {
      pendingUpdates.forEach((id, session) {
        _sessions[id] = session;
        if (!session.capturedOnWatch &&
            !session.watchCapturePending &&
            session.isCompleted &&
            (session.watchWorkoutUuid == null ||
                session.watchWorkoutUuid!.isEmpty)) {
          _notifyWorkoutUpdated(session);
        }
      });
      await _persist();
    }
    for (final session in _sessions.values) {
      _scheduleWatchCapturePendingFallback(session);
    }
    // Trim to capacity and persist if we removed older entries
    final bool trimmed = _enforceCapacity();
    final bool shouldPersistTombstonePurge = foundTombstonedInStorage;
    if (trimmed || shouldPersistTombstonePurge) {
      await _persist();
    }
    final prunedTombstones = tombstones
        .where((id) => storedIds.contains(id))
        .toList();
    if (prunedTombstones.length != tombstones.length) {
      if (prunedTombstones.isEmpty) {
        await prefs.remove(_localDeleteTombstonesKey);
      } else {
        await prefs.setStringList(_localDeleteTombstonesKey, prunedTombstones);
      }
    }
    final alreadyHydrated = prefs.getBool(_hydrationPrefKey) ?? false;
    if (didHydrate && !alreadyHydrated) {
      await prefs.setBool(_hydrationPrefKey, true);
      await _persist();
    }

    final assistedSignFixed = prefs.getBool(_assistedSignFixPrefKey) ?? false;
    if (!assistedSignFixed) {
      final Map<String, WorkoutSession> updatedSessions = {};
      bool flippedAny = false;
      final DateTime now = DateTime.now();
      _sessions.forEach((id, session) {
        bool sessionChanged = false;
        final List<WorkoutExercise> updatedExercises = [];
        for (final ex in session.exercises) {
          if (ex.exercise.kind != ExerciseKind.assisted) {
            updatedExercises.add(ex);
            continue;
          }
          bool exerciseChanged = false;
          final List<WorkoutSet> updatedSets = [];
          for (final set in ex.sets) {
            if (set.weight > 0) {
              updatedSets.add(set.copyWith(weight: -set.weight));
              exerciseChanged = true;
              flippedAny = true;
            } else {
              updatedSets.add(set);
            }
          }
          if (exerciseChanged) {
            sessionChanged = true;
            updatedExercises.add(ex.copyWith(sets: updatedSets));
          } else {
            updatedExercises.add(ex);
          }
        }
        if (sessionChanged) {
          updatedSessions[id] = session.copyWith(
            exercises: updatedExercises,
            dirty: true,
            lastUpdatedAt: now,
          );
        } else {
          updatedSessions[id] = session;
        }
      });
      if (flippedAny) {
        _sessions
          ..clear()
          ..addEntries(updatedSessions.entries);
        await _recomputePrFlagsNoInit();
      }

      await prefs.setBool(_assistedSignFixPrefKey, true);
    }
  }

  Future<void> _recordLocalDeleteTombstone(String id) async {
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_localDeleteTombstonesKey) ?? <String>[];
    if (list.contains(id)) return;
    await prefs.setStringList(_localDeleteTombstonesKey, [...list, id]);
  }

  Future<void> _persist() {
    // Snapshot immutable session objects cheaply on the caller isolate, then do
    // the recursive toMap + full-history JSON encode in a worker isolate on
    // mobile. A watch-originated set update otherwise serializes the entire local
    // history synchronously on Flutter's UI isolate and can drop visible frames.
    final snapshot = List<WorkoutSession>.of(_sessions.values, growable: false);
    final generation = _persistGeneration;

    // Encoding off-isolate makes completion order non-deterministic unless writes
    // are serialized. Keep a single chain so an older, slower snapshot can never
    // overwrite a newer workout edit in SharedPreferences.
    final operation = _persistChain.catchError((_) {}).then((_) async {
      final encoded = await _workoutSessionsEncoder(snapshot);
      // Account cleanup advances the generation before it clears storage. An
      // older encode that finishes afterward must never resurrect the previous
      // account's workout blob.
      if (generation != _persistGeneration) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, encoded);
    });
    _persistChain = operation.catchError((_) {});
    return operation;
  }

  void _invalidatePrCache({String? name, String? slug, Exercise? exercise}) {
    if (exercise != null) {
      final key = _keyForExercise(exercise);
      _prCache.remove(key);
      return;
    }
    if (name != null) {
      final key = _keyForName(name, slug);
      _prCache.remove(key);
      return;
    }
    _prCache.clear();
  }

  bool get _hasTokenStorage => GetIt.instance.isRegistered<TokenStorage>();

  TokenStorage get _tokenStorage => GetIt.instance<TokenStorage>();

  void _clearRemotePrCache() {
    final hadAuth = _remoteStatsToken != null;
    _remoteStatsApi = null;
    _remoteStatsToken = null;
    _remotePrCache.clear();
    _remotePrFetchedAt.clear();
    _remotePrFailedAt.clear();
    // `_prCache` may contain merged remote PRs (best-of local + remote). Only
    // clear it when we previously had an authenticated context to avoid
    // breaking in-session PR caching in unauthenticated/test contexts.
    if (hadAuth) {
      _invalidatePrCache();
    }
  }

  Future<HustlBackendWorkoutExerciseStatsApi?> _ensureRemoteStatsApi() async {
    if (!_hasTokenStorage) {
      // If we were previously authenticated, treat losing TokenStorage as a
      // sign-out/account change and clear caches.
      if (_remoteStatsToken != null) {
        _clearRemotePrCache();
      }
      return null;
    }
    final String? token;
    try {
      token = await _tokenStorage.getAccessToken();
    } catch (_) {
      // Keychain/secure-storage access can fail transiently in simulator or
      // entitlement edge cases. Remote stats are optional for workout logging,
      // so fail closed to local-only data instead of blocking exercise actions.
      if (_remoteStatsToken != null) {
        _clearRemotePrCache();
      }
      return null;
    }
    if (token == null || token.isEmpty) {
      // Only clear if we previously had an authenticated token.
      if (_remoteStatsToken != null) {
        _clearRemotePrCache();
      }
      return null;
    }
    if (_remoteStatsToken != token) {
      final previousToken = _remoteStatsToken;
      _remoteStatsToken = token;
      _remotePrCache.clear();
      _remotePrFetchedAt.clear();
      _remotePrFailedAt.clear();
      // Token change implies user context may have changed; ensure we don't keep
      // remote PRs merged into `_prCache`.
      if (previousToken != null) {
        _invalidatePrCache();
      }
    }
    return _remoteStatsApi ??=
        _statsApiFactory?.call(_tokenStorage) ??
        HustlBackendWorkoutExerciseStatsApi(tokens: _tokenStorage);
  }

  _PrRecord _betterPr(_PrRecord current, _PrRecord candidate) {
    if (candidate.weight > current.weight) return candidate;
    if (candidate.weight == current.weight && candidate.reps > current.reps) {
      return candidate;
    }
    return current;
  }

  Future<_PrRecord?> _getRemotePr(
    String exerciseKey, {
    required String exerciseName,
    required String? exerciseSlug,
    HustlBackendWorkoutExerciseStatsApi? apiOverride,
  }) async {
    final api = apiOverride ?? await _ensureRemoteStatsApi();
    if (api == null) return null;

    final fetchedAt = _remotePrFetchedAt[exerciseKey];
    if (fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _remotePrTtl) {
      return _remotePrCache[exerciseKey];
    }

    final failedAt = _remotePrFailedAt[exerciseKey];
    if (failedAt != null &&
        DateTime.now().difference(failedAt) < _remotePrFailureBackoff) {
      return _remotePrCache[exerciseKey];
    }

    try {
      final pr = await api.fetchExercisePr(
        exerciseName,
        exerciseSlug: exerciseSlug,
      );
      _remotePrFetchedAt[exerciseKey] = DateTime.now();
      _remotePrFailedAt.remove(exerciseKey);
      _remotePrCache[exerciseKey] = pr == null
          ? null
          : _PrRecord(pr.weight, pr.reps);
    } catch (_) {
      _remotePrFailedAt[exerciseKey] = DateTime.now();
      // Keep existing cached value on failure.
    }
    return _remotePrCache[exerciseKey];
  }

  void _notifyWorkoutUpdated(WorkoutSession session) {
    if (!session.isCompleted) return;
    if (!GetIt.instance.isRegistered<WorkoutWritebackCoordinator>()) return;
    _dispatchWriteback(
      () => GetIt.instance<WorkoutWritebackCoordinator>().handleWorkoutUpdated(
        session,
      ),
    );
  }

  void _scheduleWatchCapturePendingFallback(WorkoutSession session) {
    _watchCapturePendingFallbackTimers.remove(session.id)?.cancel();

    // Only schedule fallback for completed sessions, since writeback isn't attempted until then.
    if (!session.isCompleted || !session.watchCapturePending) return;

    final hasUuid =
        session.watchWorkoutUuid != null &&
        session.watchWorkoutUuid!.isNotEmpty;
    if (hasUuid || session.capturedOnWatch) return;

    final now = DateTime.now();
    final pendingAt = session.watchCapturePendingAt;
    if (pendingAt == null) {
      // No timestamp to compute remaining time; treat as immediately stale.
      // ignore: discarded_futures
      _handleWatchCapturePendingTimeout(session.id);
      return;
    }

    final elapsed = now.difference(pendingAt);
    if (elapsed >= _watchCapturePendingTimeout) {
      // ignore: discarded_futures
      _handleWatchCapturePendingTimeout(session.id);
      return;
    }

    _watchCapturePendingFallbackTimers[session.id] = Timer(
      _watchCapturePendingTimeout - elapsed,
      () {
        _watchCapturePendingFallbackTimers.remove(session.id);
        // ignore: discarded_futures
        _handleWatchCapturePendingTimeout(session.id);
      },
    );
  }

  void _cancelWatchCapturePendingFallback(String sessionId) {
    _watchCapturePendingFallbackTimers.remove(sessionId)?.cancel();
  }

  Future<void> _handleWatchCapturePendingTimeout(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return;
    if (!session.isCompleted || !session.watchCapturePending) return;

    final hasUuid =
        session.watchWorkoutUuid != null &&
        session.watchWorkoutUuid!.isNotEmpty;
    if (hasUuid || session.capturedOnWatch) return;

    final updated = session.copyWith(
      watchCapturePending: false,
      watchCapturePendingAt: null,
      lastUpdatedAt: DateTime.now(),
    );
    _sessions[sessionId] = updated;
    await _persist();
    _notifyWorkoutUpdated(updated);
  }

  void _notifyWorkoutDeleted(String sessionId) {
    if (!GetIt.instance.isRegistered<WorkoutWritebackCoordinator>()) return;
    _dispatchWriteback(
      () => GetIt.instance<WorkoutWritebackCoordinator>().handleWorkoutDeleted(
        sessionId,
      ),
    );
  }

  /// Runs a fire-and-forget health writeback dispatch with its own guard so a
  /// stray async failure in this best-effort side effect is logged and swallowed
  /// here — instead of escaping to the root zone (where a blanket
  /// PlatformDispatcher.onError handler would have to swallow ALL errors and
  /// mask real release crashes). Writeback is non-user-facing, so dropping it on
  /// error is safe.
  void _dispatchWriteback(Future<void> Function() run) {
    unawaited(
      run().catchError((Object error, StackTrace stack) {
        debugPrint('Workout writeback dispatch failed (ignored): $error');
      }),
    );
  }

  // Keep only the most recent sessions up to the configured cap. Always retain an active session if present.
  bool _enforceCapacity() {
    if (_sessions.length <= _maxSessions) return false;
    final List<WorkoutSession> sorted = _sessions.values.toList()
      ..sort(_compareSessionsNewestFirst);
    final Set<String> toKeep = <String>{};
    // Never evict data the server hasn't acknowledged: dirty sessions (unsynced
    // edits) and the single active session are pinned unconditionally before any
    // clean session competes for the remaining budget. Losing unsynced work to a
    // cache cap is never acceptable, so this is a soft cap — if the pinned set
    // alone exceeds _maxSessions we keep it all anyway.
    for (final s in sorted) {
      final bool isActive = s.endTime == null && !s.isCompleted;
      if (s.dirty == true || isActive) {
        toKeep.add(s.id);
      }
    }
    if (toKeep.length > _maxSessions) {
      debugPrint(
        'Workout capacity soft cap: keeping ${toKeep.length} unsynced/active '
        'sessions over cap of $_maxSessions to avoid unsynced data loss',
      );
    }
    // Fill any remaining budget with the newest clean sessions.
    for (int i = 0; i < sorted.length && toKeep.length < _maxSessions; i++) {
      toKeep.add(sorted[i].id);
    }
    final List<String> toRemove = _sessions.keys
        .where((id) => !toKeep.contains(id))
        .toList();
    for (final id in toRemove) {
      _cancelWatchCapturePendingFallback(id);
      final removed = _sessions.remove(id);
      if (_activeSessionCache?.id == removed?.id) {
        _activeSessionCache = null;
      }
    }
    return toRemove.isNotEmpty;
  }

  /// Wipe ALL locally-stored workout history (in-memory + persisted) and reset
  /// every cache/pointer so a DIFFERENT account can never see or re-upload these
  /// rows. Used by [AccountMigrationService] on account switch / sign-out.
  ///
  /// Best-effort and idempotent: settles any in-flight load first so it can't
  /// repopulate after the clear, then marks the store "loaded" so the next read
  /// returns empty without reloading the (now-removed) storage blob.
  Future<void> clearAll() async {
    await _init;
    for (final timer in _watchCapturePendingFallbackTimers.values) {
      timer.cancel();
    }
    _watchCapturePendingFallbackTimers.clear();
    _sessions.clear();
    _activeSessionCache = null;
    _activeSessionIdPref = '';
    _activeSessionIdHydrated = true;
    _invalidatePrCache();
    _clearRemotePrCache();

    // Fence every snapshot captured before this wipe, then put the removal on
    // the same serial chain as persists. This covers both sides of the race:
    // stale encodes skip their write, and any write already inside preferences
    // completes before the removal runs.
    _persistGeneration++;
    final clearOperation = _persistChain.catchError((_) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
      await prefs.remove(_localDeleteTombstonesKey);
      await prefs.setString(_activeSessionIdKey, '');
    });
    _persistChain = clearOperation.catchError((_) {});
    await clearOperation;
    _initFuture = Future.value();
  }

  /// Dispose any in-memory caches to avoid leaks
  void dispose() {
    for (final timer in _watchCapturePendingFallbackTimers.values) {
      timer.cancel();
    }
    _watchCapturePendingFallbackTimers.clear();
    _activeSessionCache = null;
    _sessions.clear();
  }

  Future<String?> _getActiveSessionIdPref() async {
    if (_activeSessionIdHydrated) return _activeSessionIdPref;
    final prefs = await SharedPreferences.getInstance();
    _activeSessionIdPref = prefs.getString(_activeSessionIdKey);
    _activeSessionIdHydrated = true;
    return _activeSessionIdPref;
  }

  Future<void> _setActiveSessionIdPref(String value) async {
    if (_activeSessionIdHydrated && _activeSessionIdPref == value) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeSessionIdKey, value);
    _activeSessionIdPref = value;
    _activeSessionIdHydrated = true;
  }

  @override
  Future<WorkoutSession?> getLatestActiveSession() async {
    await _init;
    final readGeneration = _persistGeneration;

    final pref = await _getActiveSessionIdPref();
    if (readGeneration != _persistGeneration) return null;
    // If the pointer exists (even as empty string), treat it as authoritative.
    if (pref != null) {
      if (pref.isEmpty) {
        _activeSessionCache = null;
        return null;
      }
      final session = _sessions[pref];
      if (session == null || session.endTime != null || session.isCompleted) {
        _activeSessionCache = null;
        await _setActiveSessionIdPref('');
        return null;
      }
      final hydrated = await _hydrateSession(session);
      if (readGeneration != _persistGeneration) return null;
      final currentSession = _sessions[pref];
      if (!identical(currentSession, session)) {
        if (currentSession == null ||
            currentSession.endTime != null ||
            currentSession.isCompleted) {
          return null;
        }
        _activeSessionCache = currentSession;
        return currentSession;
      }
      if (hydrated != session) {
        _sessions[hydrated.id] = hydrated;
        _invalidatePrCache();
        await _persist();
      }
      _activeSessionCache = hydrated;
      return hydrated;
    }

    // Legacy behavior: derive from stored sessions, then persist the pointer so
    // "no active session" is durable across restarts.
    if (_activeSessionCache != null &&
        _activeSessionCache!.endTime == null &&
        !_activeSessionCache!.isCompleted) {
      final cachedSession = _activeSessionCache!;
      final hydrated = await _hydrateSession(cachedSession);
      if (readGeneration != _persistGeneration) return null;
      final currentSession = _sessions[cachedSession.id];
      if (!identical(_activeSessionCache, cachedSession) ||
          !identical(currentSession, cachedSession)) {
        if (currentSession == null ||
            currentSession.endTime != null ||
            currentSession.isCompleted) {
          return null;
        }
        _activeSessionCache = currentSession;
        return currentSession;
      }
      if (hydrated != cachedSession) {
        _sessions[hydrated.id] = hydrated;
        _activeSessionCache = hydrated;
        _invalidatePrCache();
        await _persist();
      }
      await _setActiveSessionIdPref(_activeSessionCache!.id);
      return _activeSessionCache;
    }

    final ongoing =
        _sessions.values
            .where((s) => s.endTime == null && !s.isCompleted)
            .toList()
          ..sort(_compareSessionsNewestFirst);
    if (ongoing.isEmpty) {
      _activeSessionCache = null;
      await _setActiveSessionIdPref('');
      return null;
    }

    final selectedSession = ongoing.first;
    final hydrated = await _hydrateSession(selectedSession);
    if (readGeneration != _persistGeneration) return null;
    final currentSession = _sessions[selectedSession.id];
    if (!identical(currentSession, selectedSession)) {
      if (currentSession == null ||
          currentSession.endTime != null ||
          currentSession.isCompleted) {
        return null;
      }
      _activeSessionCache = currentSession;
      return currentSession;
    }
    if (hydrated != selectedSession) {
      _sessions[hydrated.id] = hydrated;
      _invalidatePrCache();
      await _persist();
    }
    _activeSessionCache = hydrated;
    await _setActiveSessionIdPref(_activeSessionCache!.id);
    return _activeSessionCache;
  }

  @override
  Future<ReadOnlyWorkoutSnapshot> getWorkoutSnapshotReadOnly({
    int? limit,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final tombstoneSet = <String>{
      ...?prefs.getStringList(_localDeleteTombstonesKey),
    };
    try {
      if (GetIt.instance.isRegistered<PreferencesService>()) {
        tombstoneSet.addAll(
          await GetIt.instance<PreferencesService>().getWorkoutsDeletedIds(),
        );
      }
    } catch (_) {
      // A failed auxiliary tombstone read must not mutate or repair storage.
    }

    final encoded = prefs.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) {
      return const ReadOnlyWorkoutSnapshot(activeSession: null, sessions: []);
    }

    final sessions = <WorkoutSession>[];
    final data = jsonDecode(encoded) as List<dynamic>;
    for (final raw in data) {
      final map = Map<String, dynamic>.from(raw as Map);
      final id = map['id'];
      if (id is String && tombstoneSet.contains(id)) continue;
      final exercises = <WorkoutExercise>[];
      for (final rawExercise
          in map['exercises'] as List<dynamic>? ?? const []) {
        final exerciseMap = Map<String, dynamic>.from(rawExercise as Map);
        final kind = _parseKind(exerciseMap['exerciseKind']);
        final rawMuscles = exerciseMap['exerciseMuscles'];
        final exercise = Exercise(
          id: exerciseMap['exerciseId'] as String?,
          name: exerciseMap['exerciseName'] as String? ?? '',
          slug: exerciseMap['exerciseSlug'] as String?,
          muscles: rawMuscles is List
              ? rawMuscles.whereType<String>().toList(growable: false)
              : const [],
          kind: kind,
          loggingMode: _parseLoggingMode(
            exerciseMap['exerciseLoggingMode'] ??
                exerciseMap['loggingMode'] ??
                exerciseMap['logging_mode'],
            kind,
          ),
        );
        exercises.add(WorkoutExercise.fromMap(exerciseMap, exercise));
      }
      sessions.add(WorkoutSession.fromMap(map, exercises));
    }
    sessions.sort(_compareSessionsNewestFirst);

    final activeId = prefs.getString(_activeSessionIdKey);
    WorkoutSession? active;
    if (activeId == null) {
      for (final session in sessions) {
        if (session.endTime == null && !session.isCompleted) {
          active = session;
          break;
        }
      }
    } else if (activeId.isNotEmpty) {
      for (final session in sessions) {
        if (session.id == activeId &&
            session.endTime == null &&
            !session.isCompleted) {
          active = session;
          break;
        }
      }
    }

    final visible = limit != null && limit > 0 && sessions.length > limit
        ? sessions.sublist(0, limit)
        : sessions;
    return ReadOnlyWorkoutSnapshot(
      activeSession: active,
      sessions: List.unmodifiable(visible),
    );
  }

  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession session) async {
    await _init;
    final writeGeneration = _persistGeneration;
    // Prefer provided id when importing, but ensure uniqueness in local store.
    final String id =
        (session.id.isNotEmpty && !_sessions.containsKey(session.id))
        ? session.id
        : _uuid.v4();
    // If caller already marked session completed, do not treat as active
    var newSession = session.copyWith(
      id: id,
      lastUpdatedAt: session.lastUpdatedAt ?? DateTime.now(),
    );

    if (!newSession.timelineEvents.any(
      (e) => e.kind == ExerciseTimelineEventKind.workoutStart,
    )) {
      newSession = newSession.copyWith(
        timelineEvents: [
          ...newSession.timelineEvents,
          ExerciseTimelineEvent(
            tsMs: newSession.startTime.millisecondsSinceEpoch,
            kind: ExerciseTimelineEventKind.workoutStart,
          ),
        ],
      );
    }

    newSession = await _hydrateSession(newSession);
    if (writeGeneration != _persistGeneration) {
      throw StateError('Workout account context changed');
    }
    _sessions[id] = newSession;
    if (!newSession.isCompleted && newSession.endTime == null) {
      _activeSessionCache = newSession;
      await _setActiveSessionIdPref(newSession.id);
    }
    _invalidatePrCache();
    _enforceCapacity();
    await _persist();
    return newSession;
  }

  // How many imported sessions to hydrate per synchronous chunk before yielding
  // the event loop. Flutter web has no isolates, so the sync import runs inline
  // on the single UI thread; hydrating a large server delta in one burst (plus
  // the historical per-session full-blob persist) is what froze the tab after
  // login. Bounding each synchronous run to a small chunk and awaiting a
  // zero-delay future lets the frame loop paint between chunks.
  static const int _importHydrateChunkSize = 25;

  /// Import a batch of server-synced sessions efficiently: hydrate + upsert by
  /// id in bounded, yielding chunks, then persist ONCE for the whole batch.
  ///
  /// This replaces the previous path where each imported session went through
  /// `createWorkoutSession`/`updateWorkoutSession`, each of which re-encodes the
  /// ENTIRE store (~1.6MB jsonEncode) — an O(n^2) synchronous storm over a large
  /// history that blocked the web main thread. Here the heavy `_persist` runs a
  /// single time after the batch is merged in memory.
  ///
  /// This is a concrete (non-interface) method so other [WorkoutRepository]
  /// implementations (demo/mock/test fakes) don't need to implement it; the
  /// sync service calls it only when the repository is a
  /// [LocalWorkoutRepository] and otherwise falls back to the per-session path.
  Future<void> importServerSessions(List<WorkoutSession> sessions) async {
    if (sessions.isEmpty) return;
    await _init;
    final importGeneration = _persistGeneration;

    bool changed = false;
    for (int i = 0; i < sessions.length; i++) {
      if (importGeneration != _persistGeneration) return;
      final incoming = sessions[i];
      if (incoming.id.isEmpty) continue;

      final existing = _sessions[incoming.id];
      // Local-dirty wins: never let a pull overwrite unsynced local edits or
      // downgrade them to clean. The dirty copy uploads on the next push and the
      // server echo imports cleanly afterwards. Leaving `changed` untouched here
      // keeps the persist short-circuit correct for skipped-only batches.
      if (existing != null && existing.dirty == true) continue;
      // Imported sessions originate from the server: keep them clean.
      var session = incoming.copyWith(
        dirty: false,
        lastUpdatedAt: incoming.lastUpdatedAt ?? DateTime.now(),
      );

      if (existing == null) {
        // Mirror createWorkoutSession: seed a workoutStart timeline event when
        // one is missing so imported history matches locally-created history.
        if (!session.timelineEvents.any(
          (e) => e.kind == ExerciseTimelineEventKind.workoutStart,
        )) {
          session = session.copyWith(
            timelineEvents: [
              ...session.timelineEvents,
              ExerciseTimelineEvent(
                tsMs: session.startTime.millisecondsSinceEpoch,
                kind: ExerciseTimelineEventKind.workoutStart,
              ),
            ],
          );
        }
      }

      session = await _hydrateSession(session);
      if (importGeneration != _persistGeneration) return;
      final current = _sessions[incoming.id];
      if (current != null && current.dirty == true) continue;
      _sessions[session.id] = session;
      if (_activeSessionCache?.id == session.id) {
        _activeSessionCache = session;
      }
      changed = true;

      // Yield to the event loop at chunk boundaries so the import never blocks a
      // frame, regardless of how large the server delta is. Skip the yield after
      // the final session — the merge/persist below already awaits.
      if ((i + 1) % _importHydrateChunkSize == 0 && i + 1 < sessions.length) {
        await Future<void>.delayed(Duration.zero);
        if (importGeneration != _persistGeneration) return;
      }
    }

    if (!changed) return;
    if (importGeneration != _persistGeneration) return;
    _invalidatePrCache();
    _enforceCapacity();
    // Single full-blob encode for the whole batch (not once per session).
    await _persist();
  }

  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async {
    await _init;
    final readGeneration = _persistGeneration;
    final session = _sessions[id];
    if (session == null) {
      return null;
    }
    final hydrated = await _hydrateSession(session);
    if (readGeneration != _persistGeneration) return null;
    final currentSession = _sessions[id];
    if (!identical(currentSession, session)) return currentSession;
    if (hydrated != session) {
      _sessions[id] = hydrated;
      if (_activeSessionCache?.id == session.id) {
        _activeSessionCache = hydrated;
      }
      _invalidatePrCache();
      await _persist();
    }
    return hydrated;
  }

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    await _init;
    final readGeneration = _persistGeneration;
    var sessions = _sessions.values.toList();
    if (startDate != null) {
      sessions = sessions.where((s) => s.startTime.isAfter(startDate)).toList();
    }
    if (endDate != null) {
      sessions = sessions.where((s) => s.startTime.isBefore(endDate)).toList();
    }
    sessions.sort(_compareSessionsNewestFirst);
    if (limit != null && limit > 0 && limit < sessions.length) {
      sessions = sessions.sublist(0, limit);
    }

    Map<String, Exercise>? lookup;
    if (_hasExerciseRepository) {
      try {
        lookup = await _ensureExerciseLookup();
      } catch (_) {
        lookup = _exerciseLookupByName;
      }
      if (readGeneration != _persistGeneration) return const [];
    }

    bool updatedAny = false;
    final List<WorkoutSession> hydrated = [];

    for (final session in sessions) {
      if (readGeneration != _persistGeneration) return const [];
      final needsHydration = session.exercises.any((exercise) {
        final ex = exercise.exercise;
        if (ex.muscles.isEmpty) {
          return true;
        }
        final normalized = _normalizeMuscles(ex.muscles);
        if (!listEquals(normalized, ex.muscles)) {
          return true;
        }
        if (lookup != null) {
          final resolved = _findExerciseInLookup(lookup, ex.name, ex.slug);
          if (resolved != null) {
            final merged = _mergeExerciseDetails(ex, resolved);
            if (merged != ex) {
              return true;
            }
          }
        }
        return false;
      });

      if (!needsHydration) {
        hydrated.add(session);
        continue;
      }

      final updatedSession = await _hydrateSession(session);
      if (readGeneration != _persistGeneration) return const [];
      final currentSession = _sessions[session.id];
      if (!identical(currentSession, session)) {
        if (currentSession != null) hydrated.add(currentSession);
        continue;
      }
      hydrated.add(updatedSession);
      if (updatedSession != session) {
        _sessions[session.id] = updatedSession;
        if (_activeSessionCache?.id == session.id) {
          _activeSessionCache = updatedSession;
        }
        updatedAny = true;
        if (_hasExerciseRepository && _exerciseLookupByName != null) {
          lookup = _exerciseLookupByName;
        }
      }
    }

    if (updatedAny) {
      if (readGeneration != _persistGeneration) return const [];
      _invalidatePrCache();
      await _persist();
    }

    return hydrated;
  }

  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession session, {
    bool markDirty = true,
  }) async {
    await _init;
    final writeGeneration = _persistGeneration;
    if (!_sessions.containsKey(session.id)) {
      throw Exception('Session not found');
    }
    final shouldMarkDirty = markDirty ? true : session.dirty;
    var updated = session.copyWith(
      lastUpdatedAt: DateTime.now(),
      dirty: shouldMarkDirty,
    );
    updated = await _hydrateSession(updated);
    if (writeGeneration != _persistGeneration) {
      throw StateError('Workout account context changed');
    }
    _sessions[session.id] = updated;
    if (updated.endTime == null && !updated.isCompleted) {
      _activeSessionCache = updated;
      await _setActiveSessionIdPref(updated.id);
    } else {
      final activeId = await _getActiveSessionIdPref();
      if (_activeSessionCache?.id == updated.id) {
        _activeSessionCache = null;
      }
      if (activeId == updated.id) {
        await _setActiveSessionIdPref('');
      }
    }
    _invalidatePrCache();
    _enforceCapacity();
    await _persist();
    _notifyWorkoutUpdated(updated);
    _scheduleWatchCapturePendingFallback(updated);
    return updated;
  }

  @override
  Future<void> deleteWorkoutSession(String id) async {
    final activeId = await _getActiveSessionIdPref();
    if (activeId == id) {
      _activeSessionCache = null;
      await _setActiveSessionIdPref('');
    }
    await _recordLocalDeleteTombstone(id);
    await _init;
    final wasActive =
        _sessions[id]?.endTime == null && !(_sessions[id]?.isCompleted ?? true);
    if (activeId == null && wasActive) {
      _activeSessionCache = null;
      await _setActiveSessionIdPref('');
    }
    _cancelWatchCapturePendingFallback(id);
    _sessions.remove(id);
    if (_activeSessionCache?.id == id) {
      _activeSessionCache = null;
    }
    _invalidatePrCache();
    // Track deletions for sync
    await GetIt.instance<PreferencesService>().addWorkoutsDeletedId(id);
    _enforceCapacity();
    await _persist();
    _notifyWorkoutDeleted(id);
  }

  @override
  Future<WorkoutSession> addExerciseToSession(
    String sessionId,
    WorkoutExercise exercise,
  ) async {
    await _init;
    final writeGeneration = _persistGeneration;
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found');
    }
    final hydratedExercise = await _hydrateWorkoutExercise(exercise);
    var updatedSession = session
        .addExercise(hydratedExercise)
        .copyWith(lastUpdatedAt: DateTime.now(), dirty: true);
    updatedSession = await _hydrateSession(updatedSession);
    if (writeGeneration != _persistGeneration) {
      throw StateError('Workout account context changed');
    }
    _sessions[sessionId] = updatedSession;
    if (updatedSession.endTime == null && !updatedSession.isCompleted) {
      _activeSessionCache = updatedSession;
    }
    _invalidatePrCache(exercise: hydratedExercise.exercise);
    _enforceCapacity();
    await _persist();
    _notifyWorkoutUpdated(updatedSession);
    return updatedSession;
  }

  @override
  Future<WorkoutSession> updateExerciseInSession(
    String sessionId,
    String exerciseId,
    WorkoutExercise exercise,
  ) async {
    await _init;
    final writeGeneration = _persistGeneration;
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found');
    }
    final index = session.exercises.indexWhere((e) => e.id == exerciseId);
    if (index == -1) {
      throw Exception('Exercise not found in session');
    }
    final hydratedExercise = await _hydrateWorkoutExercise(exercise);
    var updatedSession = session
        .updateExercise(index, hydratedExercise)
        .copyWith(lastUpdatedAt: DateTime.now(), dirty: true);
    updatedSession = await _hydrateSession(updatedSession);
    if (writeGeneration != _persistGeneration) {
      throw StateError('Workout account context changed');
    }
    _sessions[sessionId] = updatedSession;
    if (updatedSession.endTime == null && !updatedSession.isCompleted) {
      _activeSessionCache = updatedSession;
    }
    _invalidatePrCache(exercise: hydratedExercise.exercise);
    _enforceCapacity();
    await _persist();
    _notifyWorkoutUpdated(updatedSession);
    return updatedSession;
  }

  @override
  Future<WorkoutSession> removeExerciseFromSession(
    String sessionId,
    String exerciseId,
  ) async {
    await _init;
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found');
    }
    final index = session.exercises.indexWhere((e) => e.id == exerciseId);
    if (index == -1) {
      throw Exception('Exercise not found in session');
    }
    final exerciseToRemove = session.exercises[index].exercise;
    final updatedSession = session
        .removeExercise(index)
        .copyWith(lastUpdatedAt: DateTime.now(), dirty: true);
    _sessions[sessionId] = updatedSession;
    if (updatedSession.endTime == null && !updatedSession.isCompleted) {
      _activeSessionCache = updatedSession;
    }
    _invalidatePrCache(exercise: exerciseToRemove);
    _enforceCapacity();
    await _persist();
    _notifyWorkoutUpdated(updatedSession);
    return updatedSession;
  }

  @override
  Future<WorkoutExercise> addSetToExercise(
    String sessionId,
    String exerciseId,
    WorkoutSet set,
  ) async {
    await _init;
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found');
    }
    final index = session.exercises.indexWhere((e) => e.id == exerciseId);
    if (index == -1) {
      throw Exception('Exercise not found in session');
    }
    final exercise = session.exercises[index];
    final updatedExercise = exercise.addSet(set);
    final updatedSession = session
        .updateExercise(index, updatedExercise)
        .copyWith(lastUpdatedAt: DateTime.now(), dirty: true);
    _sessions[sessionId] = updatedSession;
    if (updatedSession.endTime == null && !updatedSession.isCompleted) {
      _activeSessionCache = updatedSession;
    }
    _invalidatePrCache(exercise: exercise.exercise);
    _enforceCapacity();
    await _persist();
    final sessionAfter = _sessions[sessionId];
    if (sessionAfter != null) {
      _notifyWorkoutUpdated(sessionAfter);
    }
    return updatedExercise;
  }

  @override
  Future<WorkoutExercise> updateSetInExercise(
    String sessionId,
    String exerciseId,
    int setIndex,
    WorkoutSet set,
  ) async {
    return updateSetsInExercise(sessionId, exerciseId, {setIndex: set});
  }

  /// Applies multiple set replacements to one exercise and persists once.
  ///
  /// Watch `log_set` can complete several sets from one command; without this batch
  /// path each set serializes the full local workout store separately.
  ///
  /// This is a read-modify-write against the CURRENTLY-STORED session: it mutates
  /// only the named set indices (and appends [appendTimelineEvents]), leaving every
  /// OTHER set/exercise/field untouched. That is what makes it safe against a
  /// concurrent writer — e.g. the phone screen persisting a set the lifter just
  /// completed cannot clobber a different set the watch completed a moment earlier,
  /// the way a whole-session `updateWorkoutSession` overwrite would.
  ///
  /// [appendTimelineEvents] lets the caller fold in the timeline entries it would
  /// otherwise have persisted via a whole-session write (select / setComplete),
  /// merging them into the stored session instead of overwriting it.
  ///
  /// [markDirty] false keeps the stored session's sync bit unchanged — for
  /// timeline-only churn (rest start/stop) that shouldn't trigger an upload.
  Future<WorkoutExercise> updateSetsInExercise(
    String sessionId,
    String exerciseId,
    Map<int, WorkoutSet> updatesByIndex, {
    List<ExerciseTimelineEvent> appendTimelineEvents = const [],
    bool markDirty = true,
  }) async {
    await _init;
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found');
    }
    final exerciseIndex = session.exercises.indexWhere(
      (e) => e.id == exerciseId,
    );
    if (exerciseIndex == -1) {
      throw Exception('Exercise not found in session');
    }
    final exercise = session.exercises[exerciseIndex];
    if (updatesByIndex.isEmpty && appendTimelineEvents.isEmpty) {
      return exercise;
    }

    final updates = updatesByIndex.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    var updatedExercise = exercise;
    for (final update in updates) {
      final setIndex = update.key;
      if (setIndex < 0 || setIndex >= updatedExercise.sets.length) {
        throw Exception('Set index out of bounds');
      }
      updatedExercise = updatedExercise.updateSet(setIndex, update.value);
    }
    var updatedSession = session.updateExercise(exerciseIndex, updatedExercise);
    if (appendTimelineEvents.isNotEmpty) {
      updatedSession = updatedSession.copyWith(
        timelineEvents: [
          ...updatedSession.timelineEvents,
          ...appendTimelineEvents,
        ],
      );
    }
    updatedSession = updatedSession.copyWith(
      lastUpdatedAt: DateTime.now(),
      dirty: markDirty ? true : updatedSession.dirty,
    );
    _sessions[sessionId] = updatedSession;
    if (updatedSession.endTime == null && !updatedSession.isCompleted) {
      _activeSessionCache = updatedSession;
    }
    _invalidatePrCache(exercise: exercise.exercise);
    _enforceCapacity();
    await _persist();
    final sessionAfter = _sessions[sessionId];
    if (sessionAfter != null) {
      _notifyWorkoutUpdated(sessionAfter);
    }
    return updatedExercise;
  }

  @override
  Future<WorkoutSession> completeWorkoutSession(String sessionId) async {
    await _init;
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found');
    }
    final wasActive = session.endTime == null && !session.isCompleted;
    final hasResolvedWatchCapture =
        session.capturedOnWatch ||
        ((session.watchWorkoutUuid?.isNotEmpty ?? false));
    final shouldAwaitWatchCapture =
        !hasResolvedWatchCapture &&
        (session.watchCapturePending ||
            session.watchRecordingActive ||
            session.watchRecordingStartMs != null);
    final completedSession = session.complete().copyWith(
      lastUpdatedAt: DateTime.now(),
      dirty: true,
      watchRecordingRequested: false,
      watchCapturePending: shouldAwaitWatchCapture,
      watchCapturePendingAt: shouldAwaitWatchCapture ? DateTime.now() : null,
    );
    _sessions[sessionId] = completedSession;
    if (_activeSessionCache?.id == sessionId) {
      _activeSessionCache = null;
    }
    final activeId = await _getActiveSessionIdPref();
    if (activeId == sessionId || (activeId == null && wasActive)) {
      await _setActiveSessionIdPref('');
    }
    _invalidatePrCache();
    _enforceCapacity();
    await _persist();
    if (GetIt.instance.isRegistered<WorkoutWritebackCoordinator>()) {
      _dispatchWriteback(
        () => GetIt.instance<WorkoutWritebackCoordinator>()
            .handleWorkoutCompleted(completedSession),
      );
    }
    _scheduleWatchCapturePendingFallback(completedSession);
    return completedSession;
  }

  @override
  Future<List<WorkoutSet>?> getPreviousExerciseSets(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    await _init;
    DateTime? latest;
    List<WorkoutSet>? latestSets;
    for (final session in _sessions.values) {
      // Skip active or incomplete sessions entirely; "previous" should reflect the last
      // finished workout that actually logged this exercise.
      if (!session.isCompleted || session.endTime == null) {
        continue;
      }
      for (final ex in session.exercises) {
        if (!_matchesExercise(ex.exercise, exerciseName, exerciseSlug)) {
          continue;
        }
        final completed = ex.sets.where((s) => s.isCompleted).toList();
        // Skip a session where this exercise was present but skipped/untouched:
        // its completed sets carry no logged value. "Previous" must reflect the
        // last session the exercise was actually performed, not a zero-filled
        // skip that would otherwise surface as "00:00" (timed/cardio) or
        // "0 kg × 0". (An empty `completed` list also skips: `any` is false.)
        if (!completed.any((s) => s.hasLoggedValue)) continue;
        final DateTime start = session.startTime;
        if (latest == null || start.isAfter(latest)) {
          latest = start;
          latestSets = completed;
        }
        break;
      }
    }
    if (latestSets != null) return latestSets;

    final api = await _ensureRemoteStatsApi();
    if (api == null) return null;
    try {
      final remote = await api.fetchPreviousExerciseSets(
        exerciseName,
        exerciseSlug: exerciseSlug,
      );
      return remote.isEmpty ? null : remote;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DateTime?> getLastPerformedDate(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    await _init;
    final sessions = _sessions.values.toList()
      ..sort(_compareSessionsNewestFirst);
    for (final session in sessions) {
      for (final ex in session.exercises) {
        if (_matchesExercise(ex.exercise, exerciseName, exerciseSlug)) {
          return session.startTime;
        }
      }
    }
    return null;
  }

  @override
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  }) async {
    await _init;
    final key = _keyForName(exerciseName, exerciseSlug);
    if (!await _usesWeightRepsLogging(key, exerciseName, exerciseSlug)) {
      return false;
    }
    // Warm-ups and dropset drops are never PRs — only the heavy top set wins.
    if (set.setType == SetType.warmup || set.setType == SetType.dropset) {
      return false;
    }
    if (_isAssistedExercise(key) && set.weight >= 0) {
      return false;
    }
    final currentPr = await getExercisePr(
      exerciseName,
      exerciseSlug: exerciseSlug,
    );
    final bestWeight = currentPr?.weight ?? double.negativeInfinity;
    final bestReps = currentPr?.reps ?? -1;
    final bool isPr =
        set.weight > bestWeight ||
        (set.weight == bestWeight && set.reps > bestReps);
    if (isPr) {
      _prCache[key] = _PrRecord(set.weight, set.reps);
    }
    return isPr;
  }

  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    await _init;
    final key = _keyForName(exerciseName, exerciseSlug);
    if (!await _usesWeightRepsLogging(key, exerciseName, exerciseSlug)) {
      return null;
    }
    // Ensure auth/token changes are processed before reading `_prCache`, since
    // `_prCache` may contain merged remote PRs.
    final api = await _ensureRemoteStatsApi();
    var best = _prCache[key] ??= _computeBestPr(key);
    final remote = api == null
        ? null
        : await _getRemotePr(
            key,
            exerciseName: exerciseName,
            exerciseSlug: exerciseSlug,
            apiOverride: api,
          );
    if (remote != null) {
      best = _betterPr(best, remote);
      _prCache[key] = best;
    }
    if (best.weight == double.negativeInfinity || best.reps < 0) {
      return null;
    }
    return ExercisePr(weight: best.weight, reps: best.reps);
  }

  _PrRecord _computeBestPr(String exerciseKey) {
    double bestWeight = double.negativeInfinity;
    int bestReps = -1;
    for (final session in _sessions.values) {
      for (final ex in session.exercises) {
        final key = _keyForExercise(ex.exercise);
        if (ex.exercise.loggingMode != ExerciseLoggingMode.weightReps) {
          continue;
        }
        if (key != exerciseKey) continue;
        final bool isAssisted = ex.exercise.kind == ExerciseKind.assisted;
        for (final s in ex.sets) {
          // P2: Only consider completed sets when building historic PRs
          if (!s.isCompleted) continue;
          // Warm-ups and dropset drops never set a PR.
          if (s.setType == SetType.warmup || s.setType == SetType.dropset) {
            continue;
          }
          if (isAssisted && s.weight >= 0) continue;
          if (s.weight > bestWeight ||
              (s.weight == bestWeight && s.reps > bestReps)) {
            bestWeight = s.weight;
            bestReps = s.reps;
          }
        }
      }
    }
    return _PrRecord(bestWeight, bestReps);
  }

  @override
  Future<void> recomputeAllPrFlags() async {
    await _init;
    await _recomputePrFlagsNoInit();
  }

  // How many sessions to rebuild per synchronous chunk before yielding the event
  // loop. Flutter web has no isolates, so `compute()` runs inline and this legacy
  // PR-flag migration would otherwise rebuild every session (~455 for large
  // histories) in one synchronous burst, freezing the single UI thread for
  // seconds. Processing a bounded batch and then awaiting a zero-delay future
  // lets the frame loop paint/animate between chunks, so the migration never
  // blocks a frame regardless of history size. PR flags are computed identically
  // either way: the running best-per-exercise accumulators carry across chunks
  // and sessions are processed in the same oldest-first order.
  static const int _prFlagRecomputeChunkSize = 50;

  Future<void> _recomputePrFlagsNoInit() async {
    // Snapshot the history (oldest-first) so the running best-per-exercise
    // accumulators see a stable ordering across the yielding chunks below.
    final List<WorkoutSession> sessions = _sessions.values.toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final Map<String, double> bestWeightByExercise = {};
    final Map<String, int> bestRepsAtWeightByExercise = {};

    // Compute the corrected PR flag for every set, keyed by set id. We do NOT
    // rebuild/replace sessions from this snapshot: the chunked loop yields to the
    // event loop between batches (the web-freeze fix), and a normal repository
    // mutation (create/delete/edit a workout — e.g. the user logging right after
    // login) can persist during a yield window. Replacing `_sessions` from the
    // stale snapshot afterwards would drop that new workout, resurrect a delete,
    // or overwrite an edit (data loss). Instead we record the recomputed flags
    // and MERGE them back onto the CURRENT `_sessions` after the loop, so
    // concurrent mutations are preserved. Set ids are uuids (unique per set), so
    // a flat id->flag map matches sets back to whichever session currently holds
    // them; sets that no longer exist (deleted during the run) are simply absent
    // from the current store and never written.
    final Map<String, bool> recomputedPrBySetId = {};

    for (int si = 0; si < sessions.length; si++) {
      final session = sessions[si];
      for (final ex in session.exercises) {
        final key = _keyForExercise(ex.exercise);
        if (ex.exercise.loggingMode != ExerciseLoggingMode.weightReps) {
          for (final s in ex.sets) {
            recomputedPrBySetId[s.id] = false;
          }
          continue;
        }
        double bestWeight =
            bestWeightByExercise[key] ?? double.negativeInfinity;
        int bestRepsAtWeight = bestRepsAtWeightByExercise[key] ?? -1;
        final bool isAssisted = ex.exercise.kind == ExerciseKind.assisted;

        for (final s in ex.sets) {
          bool isPr = false;
          // Warm-ups and dropset drops never set a PR.
          if (s.isCompleted &&
              s.setType != SetType.warmup &&
              s.setType != SetType.dropset) {
            if (isAssisted && s.weight >= 0) {
              isPr = false;
            } else if (s.weight > bestWeight ||
                (s.weight == bestWeight && s.reps > bestRepsAtWeight)) {
              isPr = true;
              bestWeight = s.weight;
              bestRepsAtWeight = s.reps;
            }
          }
          recomputedPrBySetId[s.id] = isPr;
        }
        bestWeightByExercise[key] = bestWeight;
        bestRepsAtWeightByExercise[key] = bestRepsAtWeight;
      }

      // Yield to the event loop at chunk boundaries (but not after the final
      // session — the merge/persist below already awaits). This bounds the
      // longest synchronous run to one chunk's worth of work.
      if ((si + 1) % _prFlagRecomputeChunkSize == 0 &&
          si + 1 < sessions.length) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    // Merge the recomputed flags onto the CURRENT store. Re-reading `_sessions`
    // here (not the stale snapshot) is what preserves any concurrent mutation
    // that landed during a yield: newly created sessions/sets keep their own
    // flags (no entry in the map), deleted sessions are gone, and edits stay —
    // we only overwrite `isPr` on sets whose ids we recomputed, and only when
    // the value actually changes (so untouched sessions aren't rewritten).
    bool changed = false;
    for (final entry in _sessions.entries.toList()) {
      final session = entry.value;
      bool sessionChanged = false;
      final List<WorkoutExercise> updatedExercises = [];
      for (final ex in session.exercises) {
        bool exerciseChanged = false;
        final List<WorkoutSet> updatedSets = [];
        for (final s in ex.sets) {
          final bool? recomputed = recomputedPrBySetId[s.id];
          if (recomputed != null && recomputed != s.isPr) {
            updatedSets.add(s.copyWith(isPr: recomputed));
            exerciseChanged = true;
          } else {
            updatedSets.add(s);
          }
        }
        if (exerciseChanged) {
          updatedExercises.add(ex.copyWith(sets: updatedSets));
          sessionChanged = true;
        } else {
          updatedExercises.add(ex);
        }
      }
      if (sessionChanged) {
        final updatedSession = session.copyWith(exercises: updatedExercises);
        _sessions[entry.key] = updatedSession;
        if (_activeSessionCache?.id == updatedSession.id) {
          _activeSessionCache = updatedSession;
        }
        changed = true;
      }
    }

    _invalidatePrCache();
    // One write at the end (not per chunk) keeps the ~1.6MB jsonEncode off the
    // per-frame path. Persist only when the merge actually changed a flag,
    // skipping a redundant ~1.6MB encode for a no-op. We persist the MERGED
    // current state, never the stale snapshot.
    if (changed) {
      await _persist();
    }
  }
}
