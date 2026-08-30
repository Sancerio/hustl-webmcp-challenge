import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/exercise_library/domain/repositories/exercise_repository.dart';
import 'package:hustl_app/features/workout_logging/data/repositories/local_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/core/services/preferences_service.dart';

class _FakeExerciseRepo implements ExerciseRepository {
  @override
  Future<List<Exercise>> getAllExercises() async => const [
    Exercise(name: 'Test', muscles: ['X']),
  ];

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

  setUp(() async {
    GetIt.instance.reset();
    GetIt.instance.registerLazySingleton<ExerciseRepository>(
      () => _FakeExerciseRepo(),
    );
    SharedPreferences.setMockInitialValues({});
    GetIt.instance.registerSingleton<PreferencesService>(PreferencesService());
    await GetIt.instance<PreferencesService>().init();
  });

  tearDown(() {
    GetIt.instance.reset();
  });

  test(
    'LRU capacity enforcement trims old sessions and keeps active session',
    () async {
      final repo = LocalWorkoutRepository(maxSessions: 3);

      // Seed 5 completed sessions with increasing startTime
      DateTime t = DateTime(2024, 1, 1, 10, 0, 0);
      for (int i = 0; i < 5; i++) {
        final s = WorkoutSession(
          id: 'tmp',
          name: 'S$i',
          startTime: t,
          endTime: t.add(const Duration(hours: 1)),
          exercises: const [],
          isCompleted: true,
          // Completed synced sessions are clean, so eviction applies to them;
          // dirty (unsynced) sessions are pinned by design.
          dirty: false,
        );
        await repo.createWorkoutSession(s);
        t = t.add(const Duration(days: 1));
      }

      // After writes, capacity should be enforced to 3
      final all = await repo.getWorkoutSessions();
      expect(all.length, 3);
      // Newest sessions should remain (by startTime)
      expect(all.first.name, 'S4');
      expect(all.last.name, 'S2');

      // Create an active (non-completed) session with very old start time; it must be kept
      final oldActive = WorkoutSession(
        id: 'tmp',
        name: 'Active',
        startTime: DateTime(2000, 1, 1),
        exercises: const [],
        isCompleted: false,
      );
      final createdActive = await repo.createWorkoutSession(oldActive);
      // Now capacity 3 should include this active one and trim others
      final afterActive = await repo.getWorkoutSessions();
      expect(afterActive.length, 3);
      expect(afterActive.any((s) => s.id == createdActive.id), true);
    },
  );
}
