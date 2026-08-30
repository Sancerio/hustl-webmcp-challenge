import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get_it/get_it.dart';

import 'package:hustl_app/features/workout_logging/data/repositories/local_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
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

  group('LocalWorkoutRepository dirty flag persistence', () {
    setUp(() async {
      final gi = GetIt.instance;
      await gi.reset();
      gi.registerLazySingleton<ExerciseRepository>(() => _FakeExerciseRepo());
      SharedPreferences.setMockInitialValues({});
      gi.registerSingleton<PreferencesService>(PreferencesService());
      await gi<PreferencesService>().init();
    });

    test(
      'loadFromStorage preserves dirty flags and does not force dirty=true',
      () async {
        const storageKey = 'workout_sessions_v1';
        final sessionA = WorkoutSession(
          id: 'a',
          name: 'A',
          startTime: DateTime.parse('2024-01-01T10:00:00Z'),
          endTime: DateTime.parse('2024-01-01T11:00:00Z'),
          exercises: const [
            WorkoutExercise(
              id: 'we',
              exercise: Exercise(name: 'E', muscles: []),
              sets: [
                WorkoutSet(id: 's', weight: 10, reps: 5, isCompleted: true),
              ],
            ),
          ],
          dirty: false,
        );
        final sessionB = WorkoutSession(
          id: 'b',
          name: 'B',
          startTime: DateTime.parse('2024-01-02T10:00:00Z'),
          endTime: DateTime.parse('2024-01-02T11:00:00Z'),
          exercises: const [],
          dirty: true,
        );
        final stored = jsonEncode([sessionA.toMap(), sessionB.toMap()]);
        SharedPreferences.setMockInitialValues({storageKey: stored});

        final repo = LocalWorkoutRepository();
        final all = await repo.getWorkoutSessions();
        final a = all.firstWhere((s) => s.id == 'a');
        final b = all.firstWhere((s) => s.id == 'b');
        expect(a.dirty, isFalse);
        expect(b.dirty, isTrue);
      },
    );

    test('loadFromStorage clears stale watch capture pending flags', () async {
      const storageKey = 'workout_sessions_v1';
      final pendingAt = DateTime.now().subtract(const Duration(hours: 1));
      final session = WorkoutSession(
        id: 'p',
        name: 'Pending',
        startTime: DateTime.parse('2024-01-03T10:00:00Z'),
        endTime: DateTime.parse('2024-01-03T11:00:00Z'),
        exercises: const [],
        isCompleted: true,
        watchCapturePending: true,
        watchCapturePendingAt: pendingAt,
      );
      final stored = jsonEncode([session.toMap()]);
      SharedPreferences.setMockInitialValues({storageKey: stored});

      final repo = LocalWorkoutRepository();
      final all = await repo.getWorkoutSessions();
      final loaded = all.singleWhere((s) => s.id == 'p');
      expect(loaded.watchCapturePending, isFalse);
      expect(loaded.watchCapturePendingAt, isNull);
      expect(loaded.capturedOnWatch, isFalse);
      expect(loaded.watchWorkoutUuid, isNull);
    });

    test(
      'updateWorkoutSession preserves provided dirty flag (used by server import)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final repo = LocalWorkoutRepository();
        final base = DateTime.parse('2024-02-01T10:00:00Z');
        await repo.createWorkoutSession(
          WorkoutSession(
            id: 'x',
            name: 'X',
            startTime: base,
            endTime: base.add(const Duration(hours: 1)),
            exercises: const [],
            dirty: true,
          ),
        );
        // Simulate server import updating same id with dirty=false
        final imp = WorkoutSession(
          id: 'x',
          name: 'X-Server',
          startTime: base,
          endTime: base.add(const Duration(hours: 1)),
          exercises: const [],
          dirty: false,
        );
        await repo.updateWorkoutSession(imp, markDirty: false);
        final stored = await repo.getWorkoutSession('x');
        expect(stored!.dirty, isFalse);
        expect(stored.name, 'X-Server');
      },
    );

    test('mutating helpers set dirty=true', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = LocalWorkoutRepository();
      final base = DateTime.parse('2024-03-01T10:00:00Z');
      await repo.createWorkoutSession(
        WorkoutSession(
          id: 'm1',
          name: 'M1',
          startTime: base,
          endTime: base.add(const Duration(hours: 1)),
          exercises: const [],
          dirty: false,
        ),
      );
      await repo.addExerciseToSession(
        'm1',
        const WorkoutExercise(
          id: 'we1',
          exercise: Exercise(name: 'E', muscles: []),
          sets: [WorkoutSet(id: 's1', weight: 10, reps: 10, isCompleted: true)],
        ),
      );
      final afterAdd = await repo.getWorkoutSession('m1');
      expect(afterAdd!.dirty, isTrue);
    });
  });
}
