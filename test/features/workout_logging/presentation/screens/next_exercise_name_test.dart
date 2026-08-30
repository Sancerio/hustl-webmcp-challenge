import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/presentation/screens/active_workout_screen.dart';

WorkoutExercise makeExercise(
  String id,
  String name, {
  List<WorkoutSet> sets = const [],
}) {
  return WorkoutExercise(
    id: id,
    exercise: Exercise(name: name, muscles: const []),
    sets: sets,
  );
}

void main() {
  test('returns current exercise when more sets remain', () {
    final ex1 = makeExercise(
      '1',
      'Squat',
      sets: [
        const WorkoutSet(id: 's1', weight: 0, reps: 0, isCompleted: true),
        const WorkoutSet(id: 's2', weight: 0, reps: 0, isCompleted: false),
      ],
    );
    final ex2 = makeExercise('2', 'Bench');
    final exercises = [ex1, ex2];

    final next = nextExerciseSuggestion(exercises, ex1);
    expect(next.name, 'Squat');
    expect(next.isNextSet, isTrue);
  });

  test('returns next exercise when current is complete', () {
    final ex1 = makeExercise(
      '1',
      'Squat',
      sets: [const WorkoutSet(id: 's1', weight: 0, reps: 0, isCompleted: true)],
    );
    final ex2 = makeExercise('2', 'Bench');
    final exercises = [ex1, ex2];

    final next = nextExerciseSuggestion(exercises, ex1);
    expect(next.name, 'Bench');
    expect(next.isNextSet, isFalse);
  });

  test('returns null when no further exercises', () {
    final ex1 = makeExercise(
      '1',
      'Squat',
      sets: [const WorkoutSet(id: 's1', weight: 0, reps: 0, isCompleted: true)],
    );
    final exercises = [ex1];

    final next = nextExerciseSuggestion(exercises, ex1);
    expect(next.name, isNull);
    expect(next.isNextSet, isFalse);
  });

  test('skips an already-completed next exercise and names the next '
      'incomplete one', () {
    // Current done; the immediately-following exercise is also fully done
    // (logged out of order). The notification must skip it and name the next
    // exercise that still has work left.
    final ex1 = makeExercise(
      '1',
      'Squat',
      sets: [const WorkoutSet(id: 's1', weight: 0, reps: 0, isCompleted: true)],
    );
    final ex2 = makeExercise(
      '2',
      'Bench',
      sets: [const WorkoutSet(id: 's2', weight: 0, reps: 0, isCompleted: true)],
    );
    final ex3 = makeExercise(
      '3',
      'Deadlift',
      sets: [
        const WorkoutSet(id: 's3', weight: 0, reps: 0, isCompleted: false),
      ],
    );
    final exercises = [ex1, ex2, ex3];

    final next = nextExerciseSuggestion(exercises, ex1);
    expect(next.name, 'Deadlift');
    expect(next.isNextSet, isFalse);
  });

  test('returns null when current is done and all later exercises are '
      'complete', () {
    // Every remaining exercise is fully completed -> no stale name; fall back
    // to the generic "time to move" copy (null name).
    final ex1 = makeExercise(
      '1',
      'Squat',
      sets: [const WorkoutSet(id: 's1', weight: 0, reps: 0, isCompleted: true)],
    );
    final ex2 = makeExercise(
      '2',
      'Bench',
      sets: [const WorkoutSet(id: 's2', weight: 0, reps: 0, isCompleted: true)],
    );
    final exercises = [ex1, ex2];

    final next = nextExerciseSuggestion(exercises, ex1);
    expect(next.name, isNull);
    expect(next.isNextSet, isFalse);
  });

  test('treats a not-yet-started (no sets) exercise as valid next work', () {
    final ex1 = makeExercise(
      '1',
      'Squat',
      sets: [const WorkoutSet(id: 's1', weight: 0, reps: 0, isCompleted: true)],
    );
    final ex2 = makeExercise('2', 'Bench'); // planned, no sets logged yet
    final exercises = [ex1, ex2];

    final next = nextExerciseSuggestion(exercises, ex1);
    expect(next.name, 'Bench');
    expect(next.isNextSet, isFalse);
  });

  test('returns null for an empty exercise list', () {
    final orphan = makeExercise('1', 'Squat');
    final next = nextExerciseSuggestion(const [], orphan);
    expect(next.name, isNull);
    expect(next.isNextSet, isFalse);
  });

  test('returns null when current is not in the list', () {
    final ex1 = makeExercise('1', 'Squat');
    final missing = makeExercise('99', 'Curl');
    final next = nextExerciseSuggestion([ex1], missing);
    expect(next.name, isNull);
    expect(next.isNextSet, isFalse);
  });
}
