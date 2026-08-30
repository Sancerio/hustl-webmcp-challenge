import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/history/history_session_metrics.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';

void main() {
  const run = WorkoutExercise(
    id: 'run',
    exercise: Exercise(
      name: 'Run',
      muscles: ['Cardio'],
      loggingMode: ExerciseLoggingMode.distanceDuration,
    ),
    sets: [
      WorkoutSet(
        id: 'r1',
        weight: 5,
        reps: 1500,
        isCompleted: true,
        isPr: true,
      ),
    ],
  );

  const plank = WorkoutExercise(
    id: 'plank',
    exercise: Exercise(
      name: 'Plank',
      muscles: ['Core'],
      loggingMode: ExerciseLoggingMode.durationOnly,
    ),
    sets: [WorkoutSet(id: 'p1', weight: 0, reps: 90, isCompleted: true)],
  );

  const bench = WorkoutExercise(
    id: 'bench',
    exercise: Exercise(name: 'Bench Press', muscles: ['Chest']),
    sets: [
      WorkoutSet(id: 'b1', weight: 100, reps: 5, isCompleted: true, isPr: true),
    ],
  );

  WorkoutSession session(List<WorkoutExercise> exercises) => WorkoutSession(
    id: 's',
    name: 'Session',
    startTime: DateTime(2026),
    exercises: exercises,
  );

  test('cardio-only session has no kg volume and ignores stale PR flags', () {
    final metrics = HistorySessionMetrics.from(session(const [run, plank]));

    expect(metrics.totalVolume, isNull);
    expect(metrics.prCount, 0);
  });

  test('mixed session counts only weight-based volume and PRs', () {
    final metrics = HistorySessionMetrics.from(session(const [bench, run]));

    expect(metrics.totalVolume, 500);
    expect(metrics.prCount, 1);
  });

  test('best-set labels follow logging mode, never kg for cardio', () {
    expect(bestSetLabel(run), '5 km × 25:00');
    expect(bestSetLabel(plank), '01:30');
    expect(bestSetLabel(bench), '100 kg × 5');
  });
}
