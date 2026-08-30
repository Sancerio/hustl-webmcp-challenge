import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/next_incomplete_exercise.dart';

WorkoutExercise _ex(
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

WorkoutSet _set(String id, {required bool done}) =>
    WorkoutSet(id: id, weight: 0, reps: 0, isCompleted: done);

void main() {
  group('isExerciseFullyCompleted', () {
    test('false when no sets logged yet (planned work)', () {
      expect(isExerciseFullyCompleted(_ex('1', 'Squat')), isFalse);
    });

    test('false when any set is incomplete', () {
      final ex = _ex(
        '1',
        'Squat',
        sets: [_set('a', done: true), _set('b', done: false)],
      );
      expect(isExerciseFullyCompleted(ex), isFalse);
    });

    test('true when all logged sets are complete', () {
      final ex = _ex(
        '1',
        'Squat',
        sets: [_set('a', done: true), _set('b', done: true)],
      );
      expect(isExerciseFullyCompleted(ex), isTrue);
    });
  });

  group('nextIncompleteExerciseIndex', () {
    test('skips fully-completed exercises and returns the next with work', () {
      final exercises = [
        _ex('1', 'Squat', sets: [_set('a', done: true)]),
        _ex('2', 'Bench', sets: [_set('b', done: true)]),
        _ex('3', 'Deadlift', sets: [_set('c', done: false)]),
      ];
      expect(nextIncompleteExerciseIndex(exercises, 0), 2);
    });

    test('treats a not-yet-started exercise as valid next work', () {
      final exercises = [
        _ex('1', 'Squat', sets: [_set('a', done: true)]),
        _ex('2', 'Bench'),
      ];
      expect(nextIncompleteExerciseIndex(exercises, 0), 1);
    });

    test('returns null when all later exercises are complete', () {
      final exercises = [
        _ex('1', 'Squat', sets: [_set('a', done: true)]),
        _ex('2', 'Bench', sets: [_set('b', done: true)]),
      ];
      expect(nextIncompleteExerciseIndex(exercises, 0), isNull);
    });

    test('returns null when fromIndex is the last element', () {
      final exercises = [
        _ex('1', 'Squat', sets: [_set('a', done: true)]),
      ];
      expect(nextIncompleteExerciseIndex(exercises, 0), isNull);
    });
  });
}
