import 'dart:async';

import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/exercise_library/domain/repositories/exercise_repository.dart';
import '../datasources/hustl_backend_exercise_api.dart';
import '../datasources/exercise_cache_local_datasource.dart';
import '../datasources/custom_exercise_local_datasource.dart';
import '../datasources/exercise_seed_datasource.dart';
import '../datasources/exercise_custom_api.dart';
import '../../../../core/services/token_storage.dart';

/// Implementation of [ExerciseRepository] that uses static data
/// Will be replaced with API implementation when backend is ready
class ExerciseRepositoryImpl
    implements ExerciseRepository, ExerciseRepositoryDebug {
  ExerciseRepositoryImpl({
    HustlBackendExerciseApi? backendApi,
    ExerciseCustomApi? customApi,
    ExerciseCacheDataSource? cache,
    ExerciseSeedDataSource? seed,
    TokenStorage? tokens,
    CustomExerciseDataSource? custom,
  }) : _backend = backendApi ?? HustlBackendExerciseApi(),
       _customApi = customApi ?? ExerciseCustomApi(),
       _cache = cache ?? ExerciseCacheLocalDataSource(),
       _seed = seed ?? const AssetExerciseSeedDataSource(),
       _tokens = tokens ?? TokenStorage(),
       _custom = custom ?? CustomExerciseLocalDataSource();

  final HustlBackendExerciseApi _backend;
  final ExerciseCustomApi _customApi;
  final ExerciseCacheDataSource _cache;
  final ExerciseSeedDataSource _seed;
  final TokenStorage _tokens;
  final CustomExerciseDataSource _custom;
  static const Duration _cacheTtl = Duration(hours: 24);

  DateTime? _lastCustomSyncAt;
  static const Duration _customSyncTtl = Duration(minutes: 5);

  bool _isUuid(String? v) {
    if (v == null) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(v);
  }

  String _loggingModeToApi(ExerciseLoggingMode m) {
    switch (m) {
      case ExerciseLoggingMode.weightReps:
        return 'weight_reps';
      case ExerciseLoggingMode.distanceDuration:
        return 'distance_duration';
      case ExerciseLoggingMode.durationOnly:
        return 'duration_only';
    }
  }

  Map<String, dynamic> _toCustomPayload(Exercise e) {
    return {
      'name': e.name,
      'muscles': e.muscles,
      'description': e.description,
      if (e.steps.isNotEmpty) 'steps': e.steps,
      if (e.cues.isNotEmpty) 'cues': e.cues,
      if (e.instructions != null && e.instructions!.trim().isNotEmpty)
        'instructions': e.instructions,
      if (e.equipment.isNotEmpty) 'equipment': e.equipment,
      if (e.imageUrl != null &&
          e.imageUrl!.trim().isNotEmpty &&
          !e.imageUrl!.startsWith('assets/'))
        'image_url': e.imageUrl,
      'kind': e.kind.name,
      'logging_mode': _loggingModeToApi(e.loggingMode),
      'visibility': e.visibility == ExerciseVisibility.public
          ? 'public'
          : 'private',
    };
  }

  Future<void> _syncCustomExercisesIfNeeded() async {
    String? accessToken;
    try {
      accessToken = await _tokens.getAccessToken();
    } catch (_) {
      accessToken = null;
    }
    if (accessToken == null || accessToken.isEmpty) return;
    final last = _lastCustomSyncAt;
    if (last != null && DateTime.now().difference(last) < _customSyncTtl) {
      return;
    }

    final catalogKeys = await _catalogCanonicalKeys();
    final localRaw = await _custom.getAll();
    final local = _dropCatalogCollisions(localRaw, catalogKeys);
    if (local.length != localRaw.length) {
      await _custom.setAll(local);
    }
    // Push local customs first (idempotent by name on the backend).
    for (final ex in local) {
      try {
        await _customApi.createOrUpdate(
          accessToken: accessToken,
          payload: _toCustomPayload(ex),
        );
      } catch (_) {
        // Ignore per-item failures; we'll still pull the server list.
      }
    }

    // Pull server customs and persist a de-duped set locally.
    final remoteRaw = await _customApi.listMine(accessToken: accessToken);
    final remote = _dropCatalogCollisions(remoteRaw, catalogKeys);
    if (remote.length != remoteRaw.length) {
      for (final ex in remoteRaw) {
        final key = ex.canonicalKey;
        final id = ex.id;
        if (key == null || key.isEmpty) continue;
        if (!catalogKeys.contains(key)) continue;
        if (id == null || id.isEmpty) continue;
        try {
          await _customApi.delete(accessToken: accessToken, id: id);
        } catch (_) {
          // Best-effort cleanup; ignore delete failures.
        }
      }
    }
    final Map<String, Exercise> byName = {};
    for (final ex in remote) {
      byName[ex.name.toLowerCase()] = ex;
    }
    for (final ex in local) {
      byName.putIfAbsent(ex.name.toLowerCase(), () => ex);
    }
    final merged = byName.values.toList(growable: false);
    await _custom.setAll(merged);
    _lastCustomSyncAt = DateTime.now();
  }

  Future<Set<String>> _catalogCanonicalKeys() async {
    try {
      final cached = await _cache.getAll();
      final base = (cached != null && cached.isNotEmpty)
          ? cached
          : await _seed.loadSeed();
      final keys = <String>{};
      for (final ex in base) {
        final key = ex.canonicalKey;
        if (key == null || key.isEmpty) continue;
        keys.add(key);
      }
      return keys;
    } catch (_) {
      return <String>{};
    }
  }

  List<Exercise> _dropCatalogCollisions(
    List<Exercise> items,
    Set<String> catalogKeys,
  ) {
    if (items.isEmpty || catalogKeys.isEmpty) return items;
    return items
        .where((ex) {
          final key = ex.canonicalKey;
          if (key == null || key.isEmpty) return true;
          return !catalogKeys.contains(key);
        })
        .toList(growable: false);
  }

  @override
  Future<List<Exercise>> getAllExercises() async {
    // Offline-first: return cached if available; otherwise built-in static data.
    final cached = await _cache.getAll();
    if (cached != null && cached.isNotEmpty) {
      // Refresh in background when stale, but do not block UI.
      unawaited(_refreshIfStale());
      await _syncCustomExercisesIfNeeded();
      final custom = await _custom.getAll();
      return _mergeCustom(_filterInvalid(cached), custom);
    }
    // No cache yet: load bundled seed from assets, persist it, then refresh in background.
    final seed = await _seed.loadSeed();
    if (seed.isNotEmpty) {
      await _cache.saveAll(seed);
    }
    unawaited(_refreshIfStale(force: true));
    await _syncCustomExercisesIfNeeded();
    final custom = await _custom.getAll();
    return _mergeCustom(_filterInvalid(seed), custom);
  }

  @override
  Future<List<Exercise>> getExercisesByMuscle(String muscle) async {
    // Filter locally for offline-first; refresh cache in background.
    final all = await getAllExercises();
    final muscleLower = muscle.toLowerCase();
    return all
        .where(
          (exercise) => exercise.muscles.any(
            (m) => m.toLowerCase().contains(muscleLower),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<Exercise>> searchExercises(String query) async {
    if (query.isEmpty) {
      return getAllExercises();
    }
    final all = await getAllExercises();
    final queryLower = query.toLowerCase();
    return all
        .where(
          (exercise) =>
              exercise.name.toLowerCase().contains(queryLower) ||
              exercise.muscles.any((m) => m.toLowerCase().contains(queryLower)),
        )
        .toList(growable: false);
  }

  @override
  Future<String?> regenerateThumbnail(Exercise exercise) async {
    return regenerateThumbnailDebug(exercise);
  }

  @override
  Future<String?> regenerateThumbnailDebug(
    Exercise exercise, {
    String? steerImageUrl,
    String? steerImageDataUrl,
  }) async {
    final accessToken = await _tokens.getAccessToken();
    if (accessToken == null) {
      throw Exception('Not authenticated');
    }
    // Prefer backend-provided id or slug; fallback to slugified name
    final id = exercise.id;
    final slug =
        exercise.slug ??
        exercise.name
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'-+'), '-');
    return _backend.regenerateThumbnail(
      id: (id != null && id.isNotEmpty) ? id : null,
      slug: slug,
      accessToken: accessToken,
      steerImageUrl: steerImageUrl,
      steerImageDataUrl: steerImageDataUrl,
    );
  }

  Future<Exercise> _generateText(Exercise exercise, String mode) async {
    final accessToken = await _tokens.getAccessToken();
    if (accessToken == null) {
      throw Exception('Not authenticated');
    }
    final id = exercise.id;
    final slug =
        exercise.slug ??
        exercise.name
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'-+'), '-');
    return _backend.generateExerciseText(
      id: (id != null && id.isNotEmpty) ? id : null,
      slug: slug,
      mode: mode,
      accessToken: accessToken,
    );
  }

  @override
  Future<Exercise> generateOverviewDebug(Exercise exercise) async {
    return _generateText(exercise, 'overview');
  }

  @override
  Future<Exercise> generateHowToDebug(Exercise exercise) async {
    return _generateText(exercise, 'how_to');
  }

  Future<void> _refreshIfStale({bool force = false}) async {
    try {
      if (!force) {
        final last = await _cache.getLastUpdated();
        if (last != null && DateTime.now().difference(last) < _cacheTtl) {
          return; // fresh enough
        }
      }
      final fresh = await _backend.listExercises(limit: 1000);
      if (fresh.isNotEmpty) {
        await _cache.saveAll(_filterInvalid(fresh));
      }
    } catch (_) {
      // Silently ignore network failures; offline-first behavior
    }
  }

  List<Exercise> _filterInvalid(List<Exercise> items) {
    return items
        .where(
          (e) =>
              e.name.trim().isNotEmpty &&
              e.muscles.any((m) => m.trim().isNotEmpty),
        )
        .toList(growable: false);
  }

  List<Exercise> _mergeCustom(List<Exercise> base, List<Exercise> custom) {
    if (custom.isEmpty) return base;
    // Deduplicate by name: prefer custom over base
    final Set<String> seen = {};
    final List<Exercise> merged = [];
    for (final e in custom) {
      merged.add(e);
      seen.add(e.name.toLowerCase());
    }
    for (final e in base) {
      if (seen.contains(e.name.toLowerCase())) continue;
      merged.add(e);
    }
    return merged;
  }

  @override
  Future<List<Exercise>> getCustomExercises() async {
    try {
      await _syncCustomExercisesIfNeeded();
    } catch (_) {}
    return _custom.getAll();
  }

  @override
  Future<List<Exercise>> getSharedExercises({String? search}) async {
    String? accessToken;
    try {
      accessToken = await _tokens.getAccessToken();
    } catch (_) {
      accessToken = null;
    }
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Not authenticated');
    }
    return _customApi.listShared(accessToken: accessToken, search: search);
  }

  @override
  Future<Exercise> addCustomExercise(Exercise exercise) async {
    await _custom.add(exercise);
    String? accessToken;
    try {
      accessToken = await _tokens.getAccessToken();
    } catch (_) {
      accessToken = null;
    }
    if (accessToken == null || accessToken.isEmpty) return exercise;

    Exercise saved;
    try {
      try {
        if (_isUuid(exercise.id)) {
          saved = await _customApi.update(
            accessToken: accessToken,
            id: exercise.id!,
            updates: _toCustomPayload(exercise),
          );
        } else {
          saved = await _customApi.createOrUpdate(
            accessToken: accessToken,
            payload: _toCustomPayload(exercise),
          );
        }
      } catch (_) {
        saved = await _customApi.createOrUpdate(
          accessToken: accessToken,
          payload: _toCustomPayload(exercise),
        );
      }
    } catch (_) {
      return exercise;
    }

    // Persist server-normalized copy (ids/visibility) locally. These writes
    // are intentionally outside the API fallback catch so persistence
    // failures reach the caller instead of being reported as a successful save.
    if (exercise.id != null &&
        exercise.id!.isNotEmpty &&
        saved.id != null &&
        saved.id != exercise.id) {
      await _custom.removeById(exercise.id!);
    }
    await _custom.add(saved);
    _lastCustomSyncAt = DateTime.now();
    return saved;
  }

  @override
  Future<void> removeCustomExercise(Exercise exercise) async {
    // Remove by id when present; otherwise fall back to name for legacy entries.
    final id = exercise.id;
    if (id != null && id.isNotEmpty) {
      await _custom.removeById(id);
      String? accessToken;
      try {
        accessToken = await _tokens.getAccessToken();
      } catch (_) {
        accessToken = null;
      }
      if (accessToken != null && accessToken.isNotEmpty && _isUuid(id)) {
        try {
          await _customApi.delete(accessToken: accessToken, id: id);
          _lastCustomSyncAt = DateTime.now();
        } catch (_) {}
      }
      return;
    }
    await _custom.removeByNameCaseInsensitive(exercise.name);
  }
}
