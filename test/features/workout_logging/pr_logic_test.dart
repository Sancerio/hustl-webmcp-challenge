import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/exercise_library/domain/repositories/exercise_repository.dart';
import 'package:hustl_app/features/workout_logging/data/repositories/local_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/data/repositories/mock_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';

class _FakeExerciseRepo extends ExerciseRepository {
  @override
  Future<List<Exercise>> getAllExercises() async => const [];

  @override
  Future<List<Exercise>> getExercisesByMuscle(String muscle) async => const [];

  @override
  Future<List<Exercise>> searchExercises(String query) async => const [];

  @override
  Future<List<Exercise>> getCustomExercises() async => const [];

  @override
  Future<Exercise> addCustomExercise(Exercise exercise) async => exercise;

  @override
  Future<void> removeCustomExercise(Exercise exercise) async {}
}

void main() {
  const bench = Exercise(name: 'Bench Press', muscles: []);
  const assisted = Exercise(
    name: 'Assisted Pull-Up',
    muscles: [],
    kind: ExerciseKind.assisted,
  );

  setUp(() async {
    // Clean DI and storage between tests
    GetIt.I.reset();
    SharedPreferences.setMockInitialValues({});
    GetIt.I.registerLazySingleton<ExerciseRepository>(
      () => _FakeExerciseRepo(),
    );
  });

  group('LocalWorkoutRepository PR logic', () {
    test('computes PR before persistence (greater-than policy)', () async {
      final repo = LocalWorkoutRepository();
      // Seed a session with a completed set 100x5
      final session = await repo.createWorkoutSession(
        WorkoutSession(
          id: 's1',
          name: 'Session 1',
          startTime: DateTime.now().subtract(const Duration(days: 1)),
          exercises: [
            const WorkoutExercise(
              id: 'e1',
              exercise: bench,
              sets: [
                WorkoutSet(id: 'set1', weight: 100, reps: 5, isCompleted: true),
              ],
            ),
          ],
        ),
      );
      await repo.updateWorkoutSession(session);

      // New set 105x5 should be a PR against history
      const candidate = WorkoutSet(
        id: 'candidate',
        weight: 105,
        reps: 5,
        isCompleted: true,
      );
      final isPr = await repo.checkIfSetIsPR(bench.name, candidate);
      expect(isPr, isTrue);

      // Persist the new set into a new session; a subsequent equal attempt is not PR
      final session2 = await repo.createWorkoutSession(
        WorkoutSession(
          id: 's2',
          name: 'Session 2',
          startTime: DateTime.now(),
          exercises: [
            const WorkoutExercise(id: 'e2', exercise: bench, sets: [candidate]),
          ],
        ),
      );
      await repo.updateWorkoutSession(session2);

      const equalAttempt = WorkoutSet(
        id: 'equal',
        weight: 105,
        reps: 5,
        isCompleted: true,
      );
      final isPrTie = await repo.checkIfSetIsPR(bench.name, equalAttempt);
      expect(isPrTie, isFalse, reason: 'strict greater-than policy for ties');
    });

    test('ignores unfinished sets when computing historic PRs', () async {
      final repo = LocalWorkoutRepository();
      // Seed history: one unfinished heavy set and one completed moderate set
      final session = await repo.createWorkoutSession(
        WorkoutSession(
          id: 's3',
          name: 'Session 3',
          startTime: DateTime.now().subtract(const Duration(days: 2)),
          exercises: [
            const WorkoutExercise(
              id: 'e3',
              exercise: bench,
              sets: [
                WorkoutSet(id: 'u1', weight: 200, reps: 1, isCompleted: false),
                WorkoutSet(id: 'c1', weight: 150, reps: 3, isCompleted: true),
              ],
            ),
          ],
        ),
      );
      await repo.updateWorkoutSession(session);

      // New completed set 160x2 should be PR even though 200x1 exists unfinished
      const candidate = WorkoutSet(
        id: 'c2',
        weight: 160,
        reps: 2,
        isCompleted: true,
      );
      final isPr = await repo.checkIfSetIsPR(bench.name, candidate);
      expect(isPr, isTrue);
    });

    test(
      'treats assisted exercises as PR by largest (least negative) weight',
      () async {
        final repo = LocalWorkoutRepository();
        final session = await repo.createWorkoutSession(
          WorkoutSession(
            id: 's4',
            name: 'Session Assisted',
            startTime: DateTime.now().subtract(const Duration(days: 1)),
            exercises: [
              const WorkoutExercise(
                id: 'e4',
                exercise: assisted,
                sets: [
                  WorkoutSet(id: 'a1', weight: -40, reps: 6, isCompleted: true),
                ],
              ),
            ],
          ),
        );
        await repo.updateWorkoutSession(session);

        const candidate = WorkoutSet(
          id: 'a2',
          weight: -30,
          reps: 6,
          isCompleted: true,
        );
        final isPr = await repo.checkIfSetIsPR(assisted.name, candidate);
        expect(isPr, isTrue);

        const heavierAssist = WorkoutSet(
          id: 'a3',
          weight: -50,
          reps: 6,
          isCompleted: true,
        );
        final isPrHeavier = await repo.checkIfSetIsPR(
          assisted.name,
          heavierAssist,
        );
        expect(
          isPrHeavier,
          isFalse,
          reason: 'more negative weight should not replace assisted PR',
        );

        final pr = await repo.getExercisePr(assisted.name);
        expect(pr, isNotNull);
        expect(pr!.weight, equals(-30));
        expect(pr.reps, equals(6));
      },
    );

    test('ignores positive assisted attempts when checking PR', () async {
      final repo = LocalWorkoutRepository();
      final session = await repo.createWorkoutSession(
        WorkoutSession(
          id: 's5',
          name: 'Assist Guard',
          startTime: DateTime.now().subtract(const Duration(days: 1)),
          exercises: [
            const WorkoutExercise(
              id: 'e5',
              exercise: assisted,
              sets: [
                WorkoutSet(id: 'a4', weight: -25, reps: 8, isCompleted: true),
              ],
            ),
          ],
        ),
      );
      await repo.updateWorkoutSession(session);

      const legacyPositive = WorkoutSet(
        id: 'legacy',
        weight: 15,
        reps: 8,
        isCompleted: true,
      );
      final isPr = await repo.checkIfSetIsPR(assisted.name, legacyPositive);
      expect(isPr, isFalse);
    });

    test('never treats warmup sets as PR candidates', () async {
      final repo = LocalWorkoutRepository();
      final session = await repo.createWorkoutSession(
        WorkoutSession(
          id: 's-warmup',
          name: 'Warmup PR Guard',
          startTime: DateTime.now().subtract(const Duration(days: 1)),
          exercises: const [
            WorkoutExercise(
              id: 'e-warmup',
              exercise: bench,
              sets: [
                WorkoutSet(id: 'base', weight: 100, reps: 5, isCompleted: true),
              ],
            ),
          ],
        ),
      );
      await repo.updateWorkoutSession(session);

      const warmupAttempt = WorkoutSet(
        id: 'warmup',
        weight: 120,
        reps: 5,
        isCompleted: true,
        setType: SetType.warmup,
      );
      final isPr = await repo.checkIfSetIsPR(bench.name, warmupAttempt);
      expect(isPr, isFalse);

      final pr = await repo.getExercisePr(bench.name);
      expect(pr, isNotNull);
      expect(pr!.weight, equals(100));
      expect(pr.reps, equals(5));
    });

    test('never treats dropset drops as PR candidates', () async {
      final repo = LocalWorkoutRepository();
      final session = await repo.createWorkoutSession(
        WorkoutSession(
          id: 's-drop',
          name: 'Dropset PR Guard',
          startTime: DateTime.now().subtract(const Duration(days: 1)),
          exercises: const [
            WorkoutExercise(
              id: 'e-drop',
              exercise: bench,
              sets: [
                WorkoutSet(id: 'top', weight: 100, reps: 5, isCompleted: true),
              ],
            ),
          ],
        ),
      );
      await repo.updateWorkoutSession(session);

      // A heavier *drop* must never win a PR — only the heavy top set is
      // eligible. parentSetId links the drop to its working set.
      const dropAttempt = WorkoutSet(
        id: 'drop',
        weight: 120,
        reps: 5,
        isCompleted: true,
        setType: SetType.dropset,
        parentSetId: 'top',
        dropIndex: 1,
      );
      final isPr = await repo.checkIfSetIsPR(bench.name, dropAttempt);
      expect(isPr, isFalse);

      final pr = await repo.getExercisePr(bench.name);
      expect(pr, isNotNull);
      expect(pr!.weight, equals(100));
      expect(pr.reps, equals(5));
    });

    test('migrates legacy positive assisted weights', () async {
      final storedSession = WorkoutSession(
        id: 'legacy-session',
        name: 'Legacy Assisted',
        startTime: DateTime(2024, 1, 1),
        endTime: DateTime(2024, 1, 1, 1),
        exercises: const [
          WorkoutExercise(
            id: 'legacy-ex',
            exercise: assisted,
            sets: [
              WorkoutSet(
                id: 'legacy-neg',
                weight: -8,
                reps: 6,
                isCompleted: true,
              ),
              WorkoutSet(
                id: 'legacy-pos',
                weight: 12,
                reps: 6,
                isCompleted: true,
                isPr: true,
              ),
            ],
          ),
        ],
        isCompleted: true,
      );

      SharedPreferences.setMockInitialValues({
        'workout_sessions_v1': jsonEncode([storedSession.toMap()]),
      });

      final repo = LocalWorkoutRepository();
      final sessions = await repo.getWorkoutSessions();
      expect(sessions, hasLength(1));
      final sets = sessions.first.exercises.first.sets;
      final best = sets.firstWhere((element) => element.id == 'legacy-neg');
      expect(best.weight, equals(-8));
      expect(best.isPr, isTrue);
      final flipped = sets.firstWhere((element) => element.id == 'legacy-pos');
      expect(flipped.weight, equals(-12));
      expect(flipped.isPr, isFalse);

      final pr = await repo.getExercisePr(assisted.name);
      expect(pr, isNotNull);
      expect(pr!.weight, equals(-8));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('workout_sessions_v1_assisted_sign_fixed'), isTrue);
    });

    // Note: zero-weight/reps guard is enforced by UI before calling checkIfSetIsPR.
  });

  group('MockWorkoutRepository PR logic', () {
    test('ignores unfinished sets in history', () async {
      final repo = MockWorkoutRepository();

      // Build session state directly via repo API to populate internal history
      final session = await repo.createWorkoutSession(
        WorkoutSession(
          id: 'm1',
          name: 'Mock 1',
          startTime: DateTime.now().subtract(const Duration(days: 3)),
          exercises: [
            const WorkoutExercise(
              id: 'me1',
              exercise: bench,
              sets: [
                WorkoutSet(id: 'mu1', weight: 210, reps: 1, isCompleted: false),
                WorkoutSet(id: 'mc1', weight: 140, reps: 5, isCompleted: true),
              ],
            ),
          ],
        ),
      );
      await repo.updateWorkoutSession(session);

      const candidate = WorkoutSet(
        id: 'mc2',
        weight: 145,
        reps: 5,
        isCompleted: true,
      );
      final isPr = await repo.checkIfSetIsPR(bench.name, candidate);
      expect(isPr, isTrue);
    });

    test('supports assisted PR detection with negative weights', () async {
      final repo = MockWorkoutRepository();

      final session = await repo.createWorkoutSession(
        WorkoutSession(
          id: 'm2',
          name: 'Mock Assisted',
          startTime: DateTime.now().subtract(const Duration(days: 2)),
          exercises: [
            const WorkoutExercise(
              id: 'me2',
              exercise: assisted,
              sets: [
                WorkoutSet(id: 'ma1', weight: -42, reps: 8, isCompleted: true),
              ],
            ),
          ],
        ),
      );
      await repo.updateWorkoutSession(session);

      const candidate = WorkoutSet(
        id: 'ma2',
        weight: -35,
        reps: 8,
        isCompleted: true,
      );
      final isPr = await repo.checkIfSetIsPR(assisted.name, candidate);
      expect(isPr, isTrue);

      const worseAttempt = WorkoutSet(
        id: 'ma3',
        weight: -47,
        reps: 8,
        isCompleted: true,
      );
      final isPrWorse = await repo.checkIfSetIsPR(assisted.name, worseAttempt);
      expect(isPrWorse, isFalse);
    });

    test('ignores positive assisted attempts when checking PR', () async {
      final repo = MockWorkoutRepository();

      final session = await repo.createWorkoutSession(
        WorkoutSession(
          id: 'm3',
          name: 'Mock Guard',
          startTime: DateTime.now().subtract(const Duration(days: 1)),
          exercises: [
            const WorkoutExercise(
              id: 'me3',
              exercise: assisted,
              sets: [
                WorkoutSet(id: 'ma4', weight: -30, reps: 8, isCompleted: true),
              ],
            ),
          ],
        ),
      );
      await repo.updateWorkoutSession(session);

      const legacyPositive = WorkoutSet(
        id: 'ma5',
        weight: 12,
        reps: 8,
        isCompleted: true,
      );
      final isPr = await repo.checkIfSetIsPR(assisted.name, legacyPositive);
      expect(isPr, isFalse);
    });

    test('never treats warmup sets as PR candidates', () async {
      final repo = MockWorkoutRepository();

      final session = await repo.createWorkoutSession(
        WorkoutSession(
          id: 'm-warmup',
          name: 'Warmup PR Guard',
          startTime: DateTime.now().subtract(const Duration(days: 1)),
          exercises: [
            const WorkoutExercise(
              id: 'me-warmup',
              exercise: bench,
              sets: [
                WorkoutSet(
                  id: 'mbase',
                  weight: 100,
                  reps: 5,
                  isCompleted: true,
                ),
              ],
            ),
          ],
        ),
      );
      await repo.updateWorkoutSession(session);

      const warmupAttempt = WorkoutSet(
        id: 'mwarmup',
        weight: 120,
        reps: 5,
        isCompleted: true,
        setType: SetType.warmup,
      );
      final isPr = await repo.checkIfSetIsPR(bench.name, warmupAttempt);
      expect(isPr, isFalse);

      final pr = await repo.getExercisePr(bench.name);
      expect(pr, isNotNull);
      expect(pr!.weight, equals(100));
      expect(pr.reps, equals(5));
    });

    test('never treats dropset drops as PR candidates', () async {
      final repo = MockWorkoutRepository();

      final session = await repo.createWorkoutSession(
        WorkoutSession(
          id: 'm-drop',
          name: 'Dropset PR Guard',
          startTime: DateTime.now().subtract(const Duration(days: 1)),
          exercises: [
            const WorkoutExercise(
              id: 'me-drop',
              exercise: bench,
              sets: [
                WorkoutSet(id: 'mtop', weight: 100, reps: 5, isCompleted: true),
              ],
            ),
          ],
        ),
      );
      await repo.updateWorkoutSession(session);

      const dropAttempt = WorkoutSet(
        id: 'mdrop',
        weight: 120,
        reps: 5,
        isCompleted: true,
        setType: SetType.dropset,
        parentSetId: 'mtop',
        dropIndex: 1,
      );
      final isPr = await repo.checkIfSetIsPR(bench.name, dropAttempt);
      expect(isPr, isFalse);

      final pr = await repo.getExercisePr(bench.name);
      expect(pr, isNotNull);
      expect(pr!.weight, equals(100));
      expect(pr.reps, equals(5));
    });
  });
}
