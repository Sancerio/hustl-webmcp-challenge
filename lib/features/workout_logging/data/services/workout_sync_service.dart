import 'dart:async'; // includes `unawaited` for intentional fire-and-forget
import 'package:flutter/widgets.dart';
import '../../../../core/services/preferences_service.dart';
import '../../../../core/services/token_storage.dart';
import '../../domain/models/workout_session.dart';
import '../../domain/models/workout_exercise.dart';
import '../../../exercise_library/domain/models/exercise.dart';
import '../../domain/models/workout_set.dart';
import '../../domain/repositories/workout_repository.dart';
import '../datasources/workout_sync_api.dart';
import '../mappers/workout_server_mapper.dart';
import '../repositories/local_workout_repository.dart';
import '../../../../core/services/notification_service.dart';

enum SyncStatus { idle, syncing, degraded }

class SyncProgress {
  final int completed;
  final int total;
  const SyncProgress(this.completed, this.total);

  @override
  bool operator ==(Object other) {
    return other is SyncProgress &&
        other.completed == completed &&
        other.total == total;
  }

  @override
  int get hashCode => Object.hash(completed, total);
}

/// Local-first workout history sync orchestrator.
///
/// - Pushes locally completed workouts to backend.
/// - Pulls server changes since last sync and merges them locally.
/// - Maintains a monotonic lastSyncVersion per user/session store.
class WorkoutSyncService with WidgetsBindingObserver {
  final PreferencesService _prefs;
  final TokenStorage _tokens;
  final WorkoutRepository _local;
  final WorkoutSyncApi _api;
  // Notifications intentionally unused for sync errors; retained for future in-app surfaces.
  // ignore: unused_field
  final NotificationService? _notifications;
  Timer? _timer;
  Future<void> _autoSyncOp = Future.value();
  bool _isSyncing = false;
  Duration _backoff = Duration.zero;
  static const Duration _minInterval = Duration(minutes: 5);
  static const Duration _maxBackoff = Duration(minutes: 30);
  static const int _uploadBatchSize = 25; // below backend limit of 100
  // Pull the server delta in SMALL pages. Flutter web has no isolates, so each
  // page's response is decoded (jsonDecode) and hydrated/persisted inline on the
  // single UI thread. Requesting the whole history (~450) in one page produced a
  // single ~1.6MB decode + a full-store re-encode per session — a multi-second
  // synchronous burst that froze the tab after login. A small page keeps every
  // decode/import step bounded; the page loop yields to the frame between pages.
  static const int _serverPageLimit = 75; // well below backend MAX_PAGE_LIMIT
  // With small pages we may need many more iterations to drain a large history,
  // so raise the per-run page cap accordingly (75 * 40 = 3000 sessions/run).
  static const int _maxServerPagesPerRun = 40; // safety: keep sync runs bounded
  final ValueNotifier<SyncProgress?> progress = ValueNotifier(null);
  // Collects human-readable sync errors for optional UI display
  final ValueNotifier<List<String>> errors = ValueNotifier(<String>[]);
  // High-level sync health for subtle UI surfaces (e.g., history banner).
  final ValueNotifier<SyncStatus> status = ValueNotifier<SyncStatus>(
    SyncStatus.idle,
  );

  bool _observerAttached = false;
  // Debounce rapid resume events to avoid redundant restarts/syncs
  Timer? _resumeDebouncer;
  // Cooldown to suppress subsequent resume-triggered syncs shortly after one ran
  static const Duration _resumeCooldown = Duration(seconds: 2);
  DateTime? _lastResumeHandledAt;

  WorkoutSyncService(
    this._prefs,
    this._tokens,
    this._local,
    this._api, [
    this._notifications,
  ]);

  Future<int> _getLastVersion() => _prefs.getWorkoutsSyncVersion();

  Future<void> _setLastVersion(int v) => _prefs.setWorkoutsSyncVersion(v);

  /// Export local completed workouts into transport maps expected by backend
  Future<List<Map<String, dynamic>>> _exportLocal() async {
    final sessions = await _local.getWorkoutSessions();
    // Only upload completed sessions that are dirty (or default dirty=true for legacy)
    final completed = sessions
        .where((s) => s.endTime != null && (s.dirty == true))
        .toList();
    // Sort deterministically so upload batching can resume based on offset
    completed.sort((a, b) {
      final t = a.startTime.compareTo(b.startTime);
      if (t != 0) return t;
      return a.id.compareTo(b.id);
    });
    return completed.map(_toServerMap).toList();
  }

  String _payloadSignature(List<Map<String, dynamic>> payload) {
    // Simple signature based on ordered IDs; sufficient for resume purposes
    final ids = <String>[];
    for (final m in payload) {
      final id = (m['id'] as String?) ?? '';
      ids.add(id);
    }
    return ids.join('|');
  }

  Map<String, dynamic> _toServerMap(WorkoutSession s) {
    return {
      'id': s.id,
      'name': s.name,
      // Always send UTC to avoid timezone ambiguities on the server
      'start_time': s.startTime.toUtc().toIso8601String(),
      'end_time': s.endTime?.toUtc().toIso8601String(),
      'duration': s.duration.inSeconds,
      'notes': s.notes,
      'status': s.isCompleted ? 'completed' : 'active',
      'exercises': [
        for (int i = 0; i < s.exercises.length; i++)
          _exerciseToServerMap(s.exercises[i], i),
      ],
    };
  }

  List<String> _normalizeMuscleList(Iterable<String> muscles) {
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

  List<String> _extractMuscles(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return _normalizeMuscleList(value.whereType<String>());
  }

  Map<String, dynamic> _exerciseToServerMap(
    WorkoutExercise ex,
    int orderIndex,
  ) {
    final map = {
      'id': ex.id,
      'exercise_name': ex.exercise.name,
      'order_index': orderIndex,
      'notes': ex.notes,
      'rest_time': ex.restTimerSeconds,
      // Additive, nullable superset grouping fields (null = ungrouped/legacy).
      'superset_group_id': ex.supersetGroupId,
      'superset_order': ex.supersetOrder,
      if (ex.metrics != null) 'metrics': ex.metrics,
      'sets': [
        for (int si = 0; si < ex.sets.length; si++)
          WorkoutSyncService.setToServerMap(
            ex.sets[si],
            si + 1,
            loggingMode: ex.exercise.loggingMode,
          ),
      ],
    };
    final muscles = _normalizeMuscleList(ex.exercise.muscles);
    if (muscles.isNotEmpty) {
      map['primary_muscles'] = muscles;
    }
    final slug = ex.exercise.slug?.trim();
    if (slug != null && slug.isNotEmpty) {
      map['exercise_slug'] = slug;
    }
    return map;
  }

  @visibleForTesting
  static Map<String, dynamic> setToServerMap(
    WorkoutSet s,
    int setNumber, {
    ExerciseLoggingMode loggingMode = ExerciseLoggingMode.weightReps,
  }) {
    // The app's lossy two-field model folds cardio/timed metrics into
    // weight/reps (distance -> weight in km, duration -> reps in seconds). Mirror
    // them into the dedicated `duration`/`distance` columns (a server-side
    // pass-through) so consumers that read those columns — get_exercise_history
    // stats, AI proposals, cross-client reads — get real values instead of null.
    // weight and reps are still written unchanged, so back-compat readers keep
    // working; this is additive.
    //
    // Two rules matter for correctness:
    // 1. Unit: `exercise_sets.distance` is METRES per the backend/MCP contract,
    //    while the app models distance as km, so convert km -> metres here (read
    //    paths convert back). Duration is seconds on both sides — no conversion.
    // 2. Skips: only emit a metric for a set that was actually performed. A
    //    skipped/untouched set (completed but all-zero, no logged value) must not
    //    write `duration: 0` / `distance: 0`, or those zeros would drag down
    //    get_exercise_history medians (typicalDurationSeconds/typicalDistance).
    //    Distance for distance+duration is still emitted at 0 for a *performed*
    //    set so its presence keeps the set classified as distance+duration.
    int? duration;
    double? distance;
    if (s.hasLoggedValue) {
      switch (loggingMode) {
        case ExerciseLoggingMode.durationOnly:
          if (s.reps > 0) duration = s.reps;
          break;
        case ExerciseLoggingMode.distanceDuration:
          if (s.reps > 0) duration = s.reps;
          distance = s.weight * 1000; // km -> metres
          break;
        case ExerciseLoggingMode.weightReps:
          break;
      }
    }
    return {
      'id': s.id,
      'set_number': setNumber,
      'weight': s.weight,
      'reps': s.reps,
      if (duration != null) 'duration': duration,
      if (distance != null) 'distance': distance,
      'rpe': s.rpe,
      'is_completed': s.isCompleted,
      'set_type': s.setType.name,
      // Dropset linkage (nullable; null = legacy/standalone set). Ride along in
      // the per-set JSON — no schema change required server-side.
      'parent_set_id': s.parentSetId,
      'drop_index': s.dropIndex,
    };
  }

  /// Merge server workouts into local store, replacing by id.
  ///
  /// Returns the list of human-readable error messages encountered while
  /// importing AND a [persistFailed] flag that is true only when the page's data
  /// was NOT saved (so the caller must NOT advance the sync cursor and should
  /// retry the same page next run).
  ///
  /// Parses each server map first (collecting per-workout parse errors without
  /// aborting the page), then upserts the parsed sessions in a SINGLE batch via
  /// [LocalWorkoutRepository.importServerSessions] (when available) — which
  /// persists once for the whole page instead of re-encoding the entire store
  /// per session. This avoids the O(n^2) inline persist storm that froze Flutter
  /// web on large histories. Other repositories fall back to a per-session
  /// upsert.
  ///
  /// Persist-vs-parse distinction:
  /// - A whole-page persist throw (e.g. a transient web IndexedDB error) sets
  ///   [persistFailed] = true: the WHOLE page is unsaved, so the cursor must not
  ///   advance or the page would never be re-pulled (permanent data loss).
  /// - "We had sessions to import but NONE parsed" (`server` non-empty, `parsed`
  ///   empty) is also treated as [persistFailed] = true — that almost always
  ///   means a schema/parse bug affecting the whole page, and silently advancing
  ///   past it would lose all of them.
  /// - A pure per-session parse failure (some parsed, some didn't, and the batch
  ///   persisted fine) keeps [persistFailed] = false: skip the corrupt row and
  ///   advance, so one bad row can't wedge all sync forever.
  /// - The per-session fallback path (non-LocalWorkoutRepository) uses skip
  ///   semantics, so [persistFailed] stays false there too.
  @visibleForTesting
  Future<({List<String> errors, bool persistFailed})> importServer(
    List<Map<String, dynamic>> server,
  ) async {
    final errs = <String>[];
    bool persistFailed = false;
    final parsed = <WorkoutSession>[];
    for (final w in server) {
      try {
        parsed.add(_fromServerMap(w));
      } catch (e) {
        errs.add('Failed to import workout: $e');
      }
    }
    // Had data to import but nothing survived parsing -> treat as a whole-page
    // failure so we don't silently advance the cursor past an unsaved page.
    if (server.isNotEmpty && parsed.isEmpty) {
      persistFailed = true;
    }
    if (parsed.isNotEmpty) {
      final local = _local;
      if (local is LocalWorkoutRepository) {
        // Fast path: one yielding, single-persist batch import (web-safe).
        try {
          await local.importServerSessions(parsed);
        } catch (e) {
          // The whole page failed to persist: do NOT advance the cursor.
          persistFailed = true;
          errs.add('Failed to import workouts: $e');
        }
      } else {
        // Fallback for other repositories: per-session upsert by id. These are
        // skip semantics (a single failed row is dropped, the rest persist), so
        // persistFailed stays false here.
        for (final session in parsed) {
          try {
            final existing = await _local.getWorkoutSession(session.id);
            if (existing == null) {
              await _local.createWorkoutSession(session);
            } else {
              await _local.updateWorkoutSession(session, markDirty: false);
            }
          } catch (e) {
            errs.add('Failed to import workout: $e');
          }
        }
      }
    }
    return (errors: errs, persistFailed: persistFailed);
  }

  WorkoutSession _fromServerMap(Map<String, dynamic> map) {
    final idVal = map['id'];
    if (idVal is! String || idVal.isEmpty) {
      throw const FormatException('workout.id missing or invalid');
    }

    final name = (map['name'] as String?) ?? 'Workout';

    final startRaw = map['start_time'];
    if (startRaw is! String || startRaw.isEmpty) {
      throw const FormatException('workout.start_time missing or invalid');
    }
    DateTime start;
    try {
      start = DateTime.parse(startRaw).toLocal();
    } catch (_) {
      throw const FormatException('workout.start_time could not be parsed');
    }

    DateTime? end;
    final endRaw = map['end_time'];
    if (endRaw is String && endRaw.isNotEmpty) {
      try {
        end = DateTime.parse(endRaw).toLocal();
      } catch (_) {
        end = null; // ignore malformed end times
      }
    }

    final exercises = (map['exercises'] is List)
        ? (map['exercises'] as List)
              .whereType<Map<String, dynamic>>()
              .map(_exerciseFromServer)
              .toList()
        : <WorkoutExercise>[];

    final statusStr =
        (map['status'] as String?) ?? (end != null ? 'completed' : 'active');
    final isCompleted = statusStr == 'completed';

    return WorkoutSession(
      id: idVal,
      name: name,
      startTime: start,
      endTime: end,
      exercises: exercises,
      notes: map['notes'] as String?,
      isCompleted: isCompleted,
      lastUpdatedAt: DateTime.now(),
      dirty: false,
    );
  }

  int? _parseRestTimerSeconds(Map<String, dynamic> map) {
    final candidates = <dynamic>[
      map['rest_time'],
      map['restTimerSeconds'],
      map['rest_seconds'],
    ];

    for (final raw in candidates) {
      int? seconds;
      if (raw is num) {
        seconds = raw.toInt();
      } else if (raw is String) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) continue;
        seconds = num.tryParse(trimmed)?.toInt();
      }
      if (seconds == null || seconds <= 0) continue;
      return seconds.clamp(1, 600);
    }

    return null;
  }

  WorkoutExercise _exerciseFromServer(Map<String, dynamic> map) {
    // Build exercise from server-provided fields
    final exerciseName = (map['exercise_name'] as String?) ?? 'Unknown';
    final rawKind = map['exercise_kind'];
    ExerciseKind kind = ExerciseKind.strength;
    if (rawKind is String) {
      switch (rawKind.trim().toLowerCase()) {
        case 'cardio':
          kind = ExerciseKind.cardio;
          break;
        case 'assisted':
          kind = ExerciseKind.assisted;
          break;
        default:
          kind = ExerciseKind.strength;
      }
    } else if (rawKind is int) {
      // Defensive: support int enum index if sent
      if (rawKind >= 0 && rawKind < ExerciseKind.values.length) {
        kind = ExerciseKind.values[rawKind];
      }
    }
    // Resolve sets through the shared server mapper so distance/duration columns
    // (and the legacy weight/reps fold) are handled identically to the history
    // path. Inferring the logging mode from the actual set data also recovers
    // duration-only exercises (e.g. Plank) that the coarse cardio->distance
    // heuristic used to misclassify.
    final rawSets = (map['sets'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final loggingMode = WorkoutServerMapper.inferLoggingMode(kind, rawSets);
    final sets = rawSets
        .map((m) => WorkoutServerMapper.setFromServerMap(m, loggingMode: loggingMode))
        .toList();
    final primaryMuscles = _extractMuscles(map['primary_muscles']);
    final secondaryMuscles = _extractMuscles(map['secondary_muscles']);
    final combinedMuscles = _normalizeMuscleList([
      ...primaryMuscles,
      ...secondaryMuscles,
    ]);
    final slugRaw = map['exercise_slug'] ?? map['slug'];
    final slug = (slugRaw is String && slugRaw.trim().isNotEmpty)
        ? slugRaw.trim()
        : null;
    final ex = Exercise(
      name: exerciseName,
      muscles: combinedMuscles,
      slug: slug,
      kind: kind,
      loggingMode: loggingMode,
    );
    return WorkoutExercise(
      id: (map['id'] as String?) ?? UniqueKey().toString(),
      exercise: ex,
      sets: sets,
      notes: map['notes'] as String?,
      restTimerSeconds: _parseRestTimerSeconds(map),
      metrics: map['metrics'] is Map
          ? Map<String, dynamic>.from(map['metrics'])
          : null,
      // Missing on read -> null (legacy flat behavior).
      supersetGroupId: map['superset_group_id'] as String?,
      supersetOrder: (map['superset_order'] as num?)?.toInt(),
    );
  }

  /// Legacy per-set reader. Prefer [WorkoutServerMapper.setFromServerMap] with
  /// an explicit logging mode (as [_exerciseFromServer] now does) so cardio/
  /// timed columns resolve; this thin delegate remains for callers/tests that
  /// only need weight/reps semantics and keeps the two paths from diverging.
  @visibleForTesting
  static WorkoutSet setFromServer(Map<String, dynamic> map) =>
      WorkoutServerMapper.setFromServerMap(map);

  /// Perform a full sync cycle (push + pull) with client-side batching.
  /// No-ops if not authenticated.
  Future<void> syncNow() async {
    if (_isSyncing) return;
    final access = await _tokens.getAccessToken();
    if (access == null || access.isEmpty) return; // not authenticated

    _isSyncing = true;
    status.value = SyncStatus.syncing;
    errors.value = <String>[];
    final allErrors = <String>[];
    try {
      int currentVersion = await _getLastVersion();
      final payload = await _exportLocal();
      final deletedIds = await _prefs.getWorkoutsDeletedIds();
      int uploaded = 0;

      // Determine resume point based on prior persisted upload progress
      final sig = _payloadSignature(payload);
      final savedSig = await _prefs.getWorkoutsUploadSignature();
      final savedOffset = await _prefs.getWorkoutsUploadOffset();
      int startIndex = 0;
      if (savedSig == sig && savedOffset > 0 && savedOffset < payload.length) {
        startIndex = savedOffset;
        uploaded = savedOffset;
      } else {
        await _prefs.setWorkoutsUploadSignature(sig);
        await _prefs.setWorkoutsUploadOffset(0);
      }
      progress.value = SyncProgress(uploaded, payload.length);

      // If there are no local updates, still do a pull-only sync once.
      if (payload.isEmpty) {
        int pages = 0;
        while (pages < _maxServerPagesPerRun) {
          final result = await _api.sync(
            accessToken: access,
            lastSyncVersion: currentVersion,
            clientWorkouts: const [],
            deletedIds: pages == 0 ? deletedIds : const [],
            limit: _serverPageLimit,
          );
          final imp = await importServer(result.serverWorkouts);
          allErrors.addAll(imp.errors);
          for (final id in result.deletedWorkoutIds) {
            await _local.deleteWorkoutSession(id);
            await _prefs.removeWorkoutsDeletedIds([id]);
          }
          if (imp.persistFailed) {
            // The page's server changes were NOT saved. Leave the cursor at the
            // last successfully-persisted version so this page is re-pulled next
            // run instead of being silently skipped (permanent data loss).
            allErrors.add(
              'Sync paused: could not save server changes; will retry next sync.',
            );
            break;
          }

          final returnedCount =
              result.serverWorkouts.length + result.deletedWorkoutIds.length;
          final advanced = result.newSyncVersion != currentVersion;
          currentVersion = result.newSyncVersion;

          // Persist progress immediately so we can resume after interruptions
          await _setLastVersion(currentVersion);
          await _prefs.setWorkoutsLastSyncAt(DateTime.now());

          pages += 1;
          if (!advanced || returnedCount < _serverPageLimit) break;
          // Yield to the frame between pages so a long server delta is drained
          // incrementally and never blocks the web UI thread in one burst.
          await Future<void>.delayed(Duration.zero);
        }

        await _prefs.clearWorkoutsUploadProgress();
      } else {
        // Batch uploads to respect backend limits
        bool deletionsSent = false;
        for (int i = startIndex; i < payload.length; i += _uploadBatchSize) {
          final chunk = payload.sublist(
            i,
            i + _uploadBatchSize > payload.length
                ? payload.length
                : i + _uploadBatchSize,
          );
          final result = await _api.sync(
            accessToken: access,
            lastSyncVersion: currentVersion,
            clientWorkouts: chunk,
            deletedIds: deletionsSent ? const [] : deletedIds,
            limit: _serverPageLimit,
          );
          deletionsSent = true;
          final imp = await importServer(result.serverWorkouts);
          allErrors.addAll(imp.errors);
          for (final id in result.deletedWorkoutIds) {
            await _local.deleteWorkoutSession(id);
            await _prefs.removeWorkoutsDeletedIds([id]);
          }
          if (imp.persistFailed) {
            // The page's server changes were NOT saved. Stop draining and leave
            // the cursor at the last persisted version so the page is re-pulled
            // next run. The uploads in this chunk already succeeded server-side;
            // their dirty flags are cleared below only on the success path, so a
            // paused chunk simply re-uploads next run (idempotent upsert by id).
            allErrors.add(
              'Sync paused: could not save server changes; will retry next sync.',
            );
            break;
          }
          currentVersion = result.newSyncVersion;
          // Update visible progress
          uploaded += chunk.length;
          progress.value = SyncProgress(uploaded, payload.length);
          // Persist progress after each batch to allow resume-on-restart
          await _setLastVersion(currentVersion);
          await _prefs.setWorkoutsLastSyncAt(DateTime.now());
          await _prefs.setWorkoutsUploadSignature(sig);
          await _prefs.setWorkoutsUploadOffset(i + chunk.length);

          // Mark uploaded client workouts as synced (clear dirty)
          for (final m in chunk) {
            final id = m['id'] as String?;
            if (id == null) continue;
            final existing = await _local.getWorkoutSession(id);
            if (existing != null) {
              await _local.updateWorkoutSession(
                existing.copyWith(dirty: false, lastUpdatedAt: DateTime.now()),
                markDirty: false,
              );
            }
          }
        }

        // Drain remaining server deltas beyond the final upload response.
        int pages = 0;
        while (pages < _maxServerPagesPerRun) {
          final result = await _api.sync(
            accessToken: access,
            lastSyncVersion: currentVersion,
            clientWorkouts: const [],
            deletedIds: const [],
            limit: _serverPageLimit,
          );
          final imp = await importServer(result.serverWorkouts);
          allErrors.addAll(imp.errors);
          for (final id in result.deletedWorkoutIds) {
            await _local.deleteWorkoutSession(id);
            await _prefs.removeWorkoutsDeletedIds([id]);
          }
          if (imp.persistFailed) {
            // The page's server changes were NOT saved. Leave the cursor at the
            // last persisted version so this page is re-pulled next run.
            allErrors.add(
              'Sync paused: could not save server changes; will retry next sync.',
            );
            break;
          }

          final returnedCount =
              result.serverWorkouts.length + result.deletedWorkoutIds.length;
          final advanced = result.newSyncVersion != currentVersion;
          currentVersion = result.newSyncVersion;

          await _setLastVersion(currentVersion);
          await _prefs.setWorkoutsLastSyncAt(DateTime.now());

          pages += 1;
          if (!advanced || returnedCount < _serverPageLimit) break;
          // Yield to the frame between pages (see pull-only loop above).
          await Future<void>.delayed(Duration.zero);
        }
      }

      // Final confirmation of latest version and timestamp
      await _setLastVersion(currentVersion);
      await _prefs.setWorkoutsLastSyncAt(DateTime.now());
      await _prefs.clearWorkoutsUploadProgress();
      if (deletedIds.isNotEmpty) {
        await _prefs.removeWorkoutsDeletedIds(deletedIds);
      }
      _backoff = Duration.zero;
    } catch (e) {
      // backoff will be applied by scheduler
      _backoff = _backoff == Duration.zero
          ? const Duration(minutes: 2)
          : _backoff * 2;
      if (_backoff > _maxBackoff) _backoff = _maxBackoff;
      // Mark sync as degraded so UI can surface a subtle warning.
      status.value = SyncStatus.degraded;
    } finally {
      _isSyncing = false;
      progress.value = null;
      if (allErrors.isNotEmpty) {
        errors.value = allErrors;
        // If import produced errors but no exception was thrown,
        // consider sync degraded for UX purposes.
        if (status.value == SyncStatus.syncing) {
          status.value = SyncStatus.degraded;
        }
      } else if (status.value == SyncStatus.syncing) {
        // Successful run with no import errors.
        status.value = SyncStatus.idle;
      }
    }
  }

  void startAutoSync() {
    _autoSyncOp = _autoSyncOp.then((_) {
      _timer?.cancel();
      _timer = Timer.periodic(_minInterval, (_) async {
        // Apply backoff by skipping ticks until time passes; simplest approach:
        if (_backoff > Duration.zero) {
          _backoff -= _minInterval;
          if (_backoff.isNegative) _backoff = Duration.zero;
          return;
        }
        await syncNow();
      });
      if (!_observerAttached) {
        WidgetsBinding.instance.addObserver(this);
        _observerAttached = true;
      }
    });
  }

  /// Ensure auto-sync is started without restarting an active timer.
  void startAutoSyncIfNeeded() {
    if (_timer?.isActive == true) return;
    startAutoSync();
  }

  void stopAutoSync() {
    _autoSyncOp = _autoSyncOp.then((_) {
      _timer?.cancel();
      _timer = null;
      if (_observerAttached) {
        WidgetsBinding.instance.removeObserver(this);
        _observerAttached = false;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeDebouncer?.cancel();
      _resumeDebouncer = Timer(const Duration(milliseconds: 500), () {
        unawaited(_onResumed());
      });
    }
  }

  Future<void> _onResumed() async {
    try {
      final now = DateTime.now();
      if (_lastResumeHandledAt != null &&
          now.difference(_lastResumeHandledAt!) < _resumeCooldown) {
        return;
      }
      _lastResumeHandledAt = now;

      final bgEnabled = await _prefs.getBackgroundSyncEnabled();
      if (!bgEnabled) return;

      // Ensure periodic sync is active without redundant restarts
      startAutoSyncIfNeeded();

      // Avoid redundant one-off sync if one is already running
      if (!_isSyncing) {
        await syncNow();
      }
    } catch (e, st) {
      debugPrint(
        'WorkoutSyncService: resume handling failed (syncing=$_isSyncing): $e\n$st',
      );
    }
  }

  @visibleForTesting
  Timer? get timer => _timer;

  @visibleForTesting
  bool get observerAttached => _observerAttached;

  @visibleForTesting
  bool get isSyncing => _isSyncing;
}
