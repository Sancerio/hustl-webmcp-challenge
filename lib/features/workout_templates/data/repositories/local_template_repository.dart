import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get_it/get_it.dart';
import '../../../../core/services/preferences_service.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/workout_template.dart';
import '../../domain/repositories/template_repository.dart';

/// Local implementation backed by SharedPreferences.
/// Stores templates as a single JSON array under a stable key.
class LocalTemplateRepository implements TemplateRepository {
  static const String _storageKey = 'workout_templates_v1';
  final Map<String, WorkoutTemplate> _templates = {};
  final Uuid _uuid = const Uuid();

  Future<void>? _initFuture;
  Future<void> get _init async => _initFuture ??= _loadFromStorage();

  Future<void> _loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString == null || jsonString.isEmpty) return;
    final List<dynamic> data = jsonDecode(jsonString) as List<dynamic>;
    _templates
      ..clear()
      ..addEntries(
        data
            .whereType<Map<String, dynamic>>()
            .map((m) => WorkoutTemplate.fromJson(m))
            .map((t) => MapEntry(t.id, t)),
      );
    // Seed defaults on first run if nothing stored
    if (_templates.isEmpty) {
      await _seedDefaults();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _templates.values.map((t) => t.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(list));
  }

  @override
  Future<List<WorkoutTemplate>> getWorkoutTemplates() async {
    await _init;
    // Ensure seed if nothing available
    if (_templates.isEmpty) {
      await _seedDefaults();
    }
    final list = _templates.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<WorkoutTemplate?> getWorkoutTemplate(String id) async {
    await _init;
    return _templates[id];
  }

  @override
  Future<WorkoutTemplate> createWorkoutTemplate(
    WorkoutTemplate template,
  ) async {
    await _init;
    final id = template.id.isEmpty ? _uuid.v4() : template.id;
    final now = DateTime.now();
    final toSave = template.copyWith(
      id: id,
      createdAt: template.createdAt.isAfter(DateTime(1971))
          ? template.createdAt
          : now,
      updatedAt: now,
    );
    _templates[id] = toSave;
    await _persist();
    // Mark as dirty for sync
    try {
      await GetIt.instance<PreferencesService>().addTemplatesDirtyId(id);
    } catch (_) {}
    return toSave;
  }

  @override
  Future<WorkoutTemplate> updateWorkoutTemplate(
    WorkoutTemplate template,
  ) async {
    await _init;
    if (!_templates.containsKey(template.id)) {
      throw Exception('Template not found');
    }
    final updated = template.copyWith(updatedAt: DateTime.now());
    _templates[template.id] = updated;
    await _persist();
    try {
      await GetIt.instance<PreferencesService>().addTemplatesDirtyId(
        template.id,
      );
    } catch (_) {}
    return updated;
  }

  @override
  Future<void> deleteWorkoutTemplate(String id) async {
    await _init;
    _templates.remove(id);
    await _persist();
    try {
      await GetIt.instance<PreferencesService>().addTemplatesDeletedId(id);
      await GetIt.instance<PreferencesService>().removeTemplatesDirtyIds([id]);
    } catch (_) {}
  }

  /// Wipe ALL locally-stored templates (in-memory + persisted) so a DIFFERENT
  /// account can never see or re-upload them. Used by [AccountMigrationService]
  /// on account switch / sign-out. Best-effort and idempotent: settles any
  /// in-flight load first, then marks the store "loaded" so the next read does
  /// not reload the removed blob. (A later read may re-seed the generic starter
  /// templates — those are not account data and are never marked dirty, so they
  /// do not upload to the next account.)
  Future<void> clearAll() async {
    await _init;
    _templates.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    _initFuture = Future.value();
  }

  Future<void> _seedDefaults() async {
    final now = DateTime.now();
    final defaults = <WorkoutTemplate>[
      WorkoutTemplate(
        id: _uuid.v4(),
        name: 'Full Body Starter',
        description: 'Balanced routine for all major muscle groups',
        exercises: const [
          {'exerciseId': 'Squat (Barbell)', 'sets': 3, 'restTimerSeconds': 90},
          {
            'exerciseId': 'Bench Press (Barbell)',
            'sets': 3,
            'restTimerSeconds': 90,
          },
          {
            'exerciseId': 'Seated Row (Cable)',
            'sets': 3,
            'restTimerSeconds': 90,
          },
        ],
        createdAt: now,
        updatedAt: now,
      ),
      WorkoutTemplate(
        id: _uuid.v4(),
        name: 'Upper Body Basics',
        description: 'Push/pull focus for chest, back, shoulders',
        exercises: const [
          {
            'exerciseId': 'Overhead Press (Dumbbell)',
            'sets': 3,
            'restTimerSeconds': 90,
          },
          {'exerciseId': 'Pull Up', 'sets': 3, 'restTimerSeconds': 90},
          {'exerciseId': 'Bicep Curl', 'sets': 2, 'restTimerSeconds': 60},
        ],
        createdAt: now,
        updatedAt: now,
      ),
      WorkoutTemplate(
        id: _uuid.v4(),
        name: 'Lower Body Basics',
        description: 'Legs and glutes with compound lifts',
        exercises: const [
          {
            'exerciseId': 'Deadlift (Barbell)',
            'sets': 3,
            'restTimerSeconds': 120,
          },
          {'exerciseId': 'Lunge (Dumbbell)', 'sets': 3, 'restTimerSeconds': 60},
          {
            'exerciseId': 'Standing Calf Raise (Dumbbell)',
            'sets': 3,
            'restTimerSeconds': 45,
          },
        ],
        createdAt: now,
        updatedAt: now,
      ),
      WorkoutTemplate(
        id: _uuid.v4(),
        name: 'Full Body (Dumbbells)',
        description: 'Simple full-body workout with dumbbells',
        exercises: const [
          {'exerciseId': 'Goblet Squat', 'sets': 3, 'restTimerSeconds': 75},
          {'exerciseId': 'Dumbbell Row', 'sets': 3, 'restTimerSeconds': 75},
          {
            'exerciseId': 'Overhead Press (Dumbbell)',
            'sets': 3,
            'restTimerSeconds': 75,
          },
          {
            'exerciseId': 'Romanian Deadlift (Dumbbell)',
            'sets': 3,
            'restTimerSeconds': 75,
          },
        ],
        createdAt: now,
        updatedAt: now,
      ),
      WorkoutTemplate(
        id: _uuid.v4(),
        name: 'Bodyweight Full Body',
        description: 'No equipment needed (great for home)',
        exercises: const [
          {
            'exerciseId': 'Squat (Bodyweight)',
            'sets': 3,
            'restTimerSeconds': 60,
          },
          {'exerciseId': 'Push Up', 'sets': 3, 'restTimerSeconds': 60},
          {'exerciseId': 'Lunge', 'sets': 3, 'restTimerSeconds': 60},
          {'exerciseId': 'Plank', 'sets': 3, 'restTimerSeconds': 45},
        ],
        createdAt: now,
        updatedAt: now,
      ),
    ];
    for (final t in defaults) {
      _templates[t.id] = t;
    }
    await _persist();
  }
}

extension LocalTemplateRepositoryServerUpserts on LocalTemplateRepository {
  /// Upsert a template from the server without changing timestamps
  /// or adding dirty flags. Persists immediately.
  Future<void> upsertFromRemote(WorkoutTemplate template) async {
    await _init;
    _templates[template.id] = template;
    await _persist();
  }

  /// Delete a template due to a server tombstone/soft delete without
  /// adding local deleted markers that would re-upload.
  Future<void> deleteFromRemote(String id) async {
    await _init;
    _templates.remove(id);
    await _persist();
  }
}
