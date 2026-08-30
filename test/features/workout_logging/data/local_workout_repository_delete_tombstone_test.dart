import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/exercise_library/domain/repositories/exercise_repository.dart';
import 'package:hustl_app/features/workout_logging/data/repositories/local_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';

class _FakeExerciseRepo implements ExerciseRepository {
  @override
  Future<List<Exercise>> getAllExercises() async => const [];
  @override
  Future<List<Exercise>> getExercisesByMuscle(String muscle) async => const [];
  @override
  Future<List<Exercise>> searchExercises(String query) async => const [];
  @override
  Future<String?> regenerateThumbnail(Exercise exercise) async => null;
  @override
  Future<String?> regenerateThumbnailDebug(
    Exercise exercise, {
    String? steerImageUrl,
    String? steerImageDataUrl,
  }) async => null;
  @override
  Future<Exercise> generateOverviewDebug(Exercise exercise) async => exercise;
  @override
  Future<Exercise> generateHowToDebug(Exercise exercise) async => exercise;
  @override
  Future<List<Exercise>> getCustomExercises() async => const [];
  @override
  Future<List<Exercise>> getSharedExercises({String? search}) async => const [];
  @override
  Future<Exercise> addCustomExercise(Exercise exercise) async => exercise;
  @override
  Future<void> removeCustomExercise(Exercise exercise) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sessionsKey = 'workout_sessions_v1';
  const tombstonesKey = 'workout_sessions_v1_delete_tombstones';
  const syncDeletedIdsKey = 'sync_workouts_deleted_ids';
  const activeSessionIdKey = 'workout_sessions_v1_active_session_id';

  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    getIt.registerLazySingleton<ExerciseRepository>(() => _FakeExerciseRepo());
    SharedPreferences.setMockInitialValues({});
    getIt.registerSingleton<PreferencesService>(PreferencesService());
    await getIt<PreferencesService>().init();
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('tombstoned sessions are not restored as active workouts', () async {
    final dangling = WorkoutSession(
      id: 'dangling',
      name: 'Workout',
      startTime: DateTime.parse('2025-01-01T10:00:00Z'),
      exercises: const [],
    );
    SharedPreferences.setMockInitialValues({
      sessionsKey: jsonEncode([dangling.toMap()]),
      tombstonesKey: const ['dangling'],
    });
    await getIt<PreferencesService>().init();

    final repo = LocalWorkoutRepository();
    final active = await repo.getLatestActiveSession();
    expect(active, isNull);
    expect(await repo.getWorkoutSession('dangling'), isNull);

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(sessionsKey);
    expect(stored, isNotNull);
    expect(jsonDecode(stored!) as List<dynamic>, isEmpty);
  });

  test(
    'explicit empty active-session pointer prevents restoring a stale active session',
    () async {
      final dangling = WorkoutSession(
        id: 'dangling-pointer',
        name: 'Workout',
        startTime: DateTime.parse('2025-01-01T10:00:00Z'),
        exercises: const [],
      );
      SharedPreferences.setMockInitialValues({
        sessionsKey: jsonEncode([dangling.toMap()]),
        activeSessionIdKey: '',
      });
      await getIt<PreferencesService>().init();

      final repo = LocalWorkoutRepository();
      final active = await repo.getLatestActiveSession();
      expect(active, isNull);
    },
  );

  test(
    'legacy restore finds an active session and persists the pointer',
    () async {
      final dangling = WorkoutSession(
        id: 'dangling-legacy',
        name: 'Workout',
        startTime: DateTime.parse('2025-01-01T10:00:00Z'),
        exercises: const [],
      );
      SharedPreferences.setMockInitialValues({
        sessionsKey: jsonEncode([dangling.toMap()]),
      });
      await getIt<PreferencesService>().init();

      final repo = LocalWorkoutRepository();
      final active = await repo.getLatestActiveSession();
      expect(active?.id, dangling.id);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(activeSessionIdKey), dangling.id);
    },
  );

  test('deleteWorkoutSession records a local tombstone', () async {
    final repo = LocalWorkoutRepository();
    await repo.createWorkoutSession(
      WorkoutSession(
        id: 'to-delete',
        name: 'Workout',
        startTime: DateTime.parse('2025-01-01T10:00:00Z'),
        exercises: const [],
      ),
    );

    await repo.deleteWorkoutSession('to-delete');

    final prefs = await SharedPreferences.getInstance();
    final tombstones = prefs.getStringList(tombstonesKey) ?? const <String>[];
    expect(tombstones, contains('to-delete'));
    expect(await repo.getWorkoutSession('to-delete'), isNull);
  });

  test('sync deleted ids prevent restoring an active session', () async {
    final dangling = WorkoutSession(
      id: 'dangling-sync',
      name: 'Workout',
      startTime: DateTime.parse('2025-01-01T10:00:00Z'),
      exercises: const [],
    );
    SharedPreferences.setMockInitialValues({
      sessionsKey: jsonEncode([dangling.toMap()]),
      syncDeletedIdsKey: const ['dangling-sync'],
    });
    await getIt<PreferencesService>().init();

    final repo = LocalWorkoutRepository();
    final active = await repo.getLatestActiveSession();
    expect(active, isNull);
    expect(await repo.getWorkoutSession('dangling-sync'), isNull);

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(sessionsKey);
    expect(stored, isNotNull);
    expect(jsonDecode(stored!) as List<dynamic>, isEmpty);
  });

  test(
    'completed sessions with missing endTime are not treated as active',
    () async {
      final inconsistent = WorkoutSession(
        id: 'completed-missing-end',
        name: 'Workout',
        startTime: DateTime.parse('2025-01-01T10:00:00Z'),
        endTime: null,
        exercises: const [],
        isCompleted: true,
        dirty: false,
      );
      SharedPreferences.setMockInitialValues({
        sessionsKey: jsonEncode([inconsistent.toMap()]),
      });
      await getIt<PreferencesService>().init();

      final repo = LocalWorkoutRepository();
      final active = await repo.getLatestActiveSession();
      expect(active, isNull);
    },
  );
}
