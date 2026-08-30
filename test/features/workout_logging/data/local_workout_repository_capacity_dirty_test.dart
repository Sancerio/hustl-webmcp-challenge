import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/features/workout_logging/data/repositories/local_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/exercise_library/domain/repositories/exercise_repository.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/core/services/preferences_service.dart';

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

  setUp(() async {
    final gi = GetIt.instance;
    await gi.reset();
    gi.registerLazySingleton<ExerciseRepository>(() => _FakeExerciseRepo());
    SharedPreferences.setMockInitialValues({});
    gi.registerSingleton<PreferencesService>(PreferencesService());
    await gi<PreferencesService>().init();
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  group('LocalWorkoutRepository capacity never evicts unsynced data', () {
    test(
      'keeps oldest dirty sessions and evicts the oldest clean ones',
      () async {
        final repo = LocalWorkoutRepository(maxSessions: 3);
        DateTime t = DateTime(2024, 1, 1, 10, 0, 0);

        // 5 completed sessions oldest-first; the 2 oldest are dirty (unsynced).
        for (int i = 0; i < 5; i++) {
          await repo.createWorkoutSession(
            WorkoutSession(
              id: 'tmp',
              name: 'S$i',
              startTime: t,
              endTime: t.add(const Duration(hours: 1)),
              exercises: const [],
              isCompleted: true,
              dirty: i < 2, // S0, S1 dirty; S2..S4 clean
            ),
          );
          t = t.add(const Duration(days: 1));
        }

        final all = await repo.getWorkoutSessions();
        final names = all.map((s) => s.name).toSet();
        // Cap is 3. The 2 dirty oldest (S0, S1) must survive; the remaining
        // budget (1) goes to the newest clean session (S4). The oldest clean
        // sessions (S2, S3) are evicted.
        expect(all.length, 3);
        expect(names.contains('S0'), isTrue);
        expect(names.contains('S1'), isTrue);
        expect(names.contains('S4'), isTrue);
        expect(names.contains('S2'), isFalse);
        expect(names.contains('S3'), isFalse);
      },
    );

    test(
      'soft cap: nothing evicted when every session over cap is dirty',
      () async {
        final repo = LocalWorkoutRepository(maxSessions: 3);
        DateTime t = DateTime(2024, 2, 1, 10, 0, 0);

        for (int i = 0; i < 5; i++) {
          await repo.createWorkoutSession(
            WorkoutSession(
              id: 'tmp',
              name: 'D$i',
              startTime: t,
              endTime: t.add(const Duration(hours: 1)),
              exercises: const [],
              isCompleted: true,
              dirty: true,
            ),
          );
          t = t.add(const Duration(days: 1));
        }

        final all = await repo.getWorkoutSessions();
        // All 5 are unsynced — keep them all despite the cap of 3.
        expect(all.length, 5);
      },
    );

    test(
      'active session always survives eviction (regression guard)',
      () async {
        final repo = LocalWorkoutRepository(maxSessions: 3);
        DateTime t = DateTime(2024, 3, 1, 10, 0, 0);

        // 3 clean completed sessions to fill the cap.
        for (int i = 0; i < 3; i++) {
          await repo.createWorkoutSession(
            WorkoutSession(
              id: 'tmp',
              name: 'C$i',
              startTime: t,
              endTime: t.add(const Duration(hours: 1)),
              exercises: const [],
              isCompleted: true,
              dirty: false,
            ),
          );
          t = t.add(const Duration(days: 1));
        }

        // A very old active (non-completed) session must still be kept.
        final active = await repo.createWorkoutSession(
          WorkoutSession(
            id: 'tmp',
            name: 'Active',
            startTime: DateTime(2000, 1, 1),
            exercises: const [],
            isCompleted: false,
          ),
        );

        final all = await repo.getWorkoutSessions();
        expect(all.length, 3);
        expect(all.any((s) => s.id == active.id), isTrue);
      },
    );
  });
}
