import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/features/workout_logging/data/repositories/local_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/exercise_timeline_event.dart';
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

  group('LocalWorkoutRepository importServerSessions dirty guard', () {
    test(
      'skips import when local copy is dirty (local-dirty wins)',
      () async {
        final repo = LocalWorkoutRepository();
        final base = DateTime.parse('2024-05-01T10:00:00Z');
        // Local session with unsynced edits (dirty=true).
        await repo.createWorkoutSession(
          WorkoutSession(
            id: 'x',
            name: 'Local Edits',
            startTime: base,
            endTime: base.add(const Duration(hours: 1)),
            exercises: const [],
            dirty: true,
          ),
        );

        // A pull carries a stale server copy of the same id.
        await repo.importServerSessions([
          WorkoutSession(
            id: 'x',
            name: 'Stale Server Copy',
            startTime: base,
            endTime: base.add(const Duration(hours: 1)),
            exercises: const [],
            dirty: false,
          ),
        ]);

        final stored = await repo.getWorkoutSession('x');
        expect(stored, isNotNull);
        // Local content untouched and still dirty so it uploads next push.
        expect(stored!.name, 'Local Edits');
        expect(stored.dirty, isTrue);
      },
    );

    test(
      'applies server copy when local is clean (regression: normal path)',
      () async {
        final repo = LocalWorkoutRepository();
        final base = DateTime.parse('2024-05-02T10:00:00Z');
        await repo.createWorkoutSession(
          WorkoutSession(
            id: 'y',
            name: 'Local Clean',
            startTime: base,
            endTime: base.add(const Duration(hours: 1)),
            exercises: const [],
            dirty: false,
          ),
        );

        await repo.importServerSessions([
          WorkoutSession(
            id: 'y',
            name: 'Server Update',
            startTime: base,
            endTime: base.add(const Duration(hours: 1)),
            exercises: const [],
            dirty: false,
          ),
        ]);

        final stored = await repo.getWorkoutSession('y');
        expect(stored, isNotNull);
        expect(stored!.name, 'Server Update');
        expect(stored.dirty, isFalse);
      },
    );

    test(
      'brand-new import seeds a workoutStart timeline event',
      () async {
        final repo = LocalWorkoutRepository();
        final base = DateTime.parse('2024-05-03T10:00:00Z');

        await repo.importServerSessions([
          WorkoutSession(
            id: 'z',
            name: 'New Import',
            startTime: base,
            endTime: base.add(const Duration(hours: 1)),
            exercises: const [],
            dirty: false,
          ),
        ]);

        final stored = await repo.getWorkoutSession('z');
        expect(stored, isNotNull);
        expect(
          stored!.timelineEvents.any(
            (e) => e.kind == ExerciseTimelineEventKind.workoutStart,
          ),
          isTrue,
        );
      },
    );

    test(
      'all-dirty batch is skipped and does not re-persist storage',
      () async {
        const storageKey = 'workout_sessions_v1';
        final repo = LocalWorkoutRepository();
        final base = DateTime.parse('2024-05-04T10:00:00Z');
        await repo.createWorkoutSession(
          WorkoutSession(
            id: 'd1',
            name: 'Dirty One',
            startTime: base,
            endTime: base.add(const Duration(hours: 1)),
            exercises: const [],
            dirty: true,
          ),
        );

        final prefs = await SharedPreferences.getInstance();
        final before = prefs.getString(storageKey);

        // Import a server copy of the same (dirty) id — should be skipped, so
        // the persisted blob must not change.
        await repo.importServerSessions([
          WorkoutSession(
            id: 'd1',
            name: 'Server Overwrite',
            startTime: base,
            endTime: base.add(const Duration(hours: 1)),
            exercises: const [],
            dirty: false,
          ),
        ]);

        final after = (await SharedPreferences.getInstance())
            .getString(storageKey);
        expect(after, before);

        final stored = await repo.getWorkoutSession('d1');
        expect(stored!.name, 'Dirty One');
        expect(stored.dirty, isTrue);
      },
    );
  });
}
