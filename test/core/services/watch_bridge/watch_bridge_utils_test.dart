import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/services/watch_bridge/watch_bridge_utils.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';

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

void main() {
  group('resolveWatchImageUrl', () {
    test('returns null for empty and assets', () {
      expect(
        resolveWatchImageUrl(null, baseUrl: 'http://localhost:3001'),
        isNull,
      );
      expect(
        resolveWatchImageUrl('', baseUrl: 'http://localhost:3001'),
        isNull,
      );
      expect(
        resolveWatchImageUrl(
          'assets/images/squat.png',
          baseUrl: 'http://localhost:3001',
        ),
        isNull,
      );
    });

    test('passes through absolute urls', () {
      expect(
        resolveWatchImageUrl(
          'https://example.com/a.png',
          baseUrl: 'http://localhost:3001',
        ),
        'https://example.com/a.png',
      );
      expect(
        resolveWatchImageUrl(
          'http://example.com/a.png',
          baseUrl: 'http://localhost:3001',
        ),
        'http://example.com/a.png',
      );
    });

    test('resolves relative urls against baseUrl', () {
      expect(
        resolveWatchImageUrl('/images/a.png', baseUrl: 'http://localhost:3001'),
        'http://localhost:3001/images/a.png',
      );
      expect(
        resolveWatchImageUrl('images/a.png', baseUrl: 'http://localhost:3001'),
        'http://localhost:3001/images/a.png',
      );
    });
  });

  group('nextExerciseSuggestion', () {
    test('returns current exercise as next set when sets remain', () {
      final ex1 = _ex(
        '1',
        'Squat',
        sets: const [
          WorkoutSet(id: 's1', weight: 0, reps: 0, isCompleted: true),
          WorkoutSet(id: 's2', weight: 0, reps: 0, isCompleted: false),
        ],
      );
      final next = nextExerciseSuggestion([ex1, _ex('2', 'Bench')], ex1);
      expect(next.name, 'Squat');
      expect(next.isNextSet, isTrue);
    });

    test('skips an already-completed next exercise and names the next '
        'incomplete one', () {
      final ex1 = _ex(
        '1',
        'Squat',
        sets: const [
          WorkoutSet(id: 's1', weight: 0, reps: 0, isCompleted: true),
        ],
      );
      final ex2 = _ex(
        '2',
        'Bench',
        sets: const [
          WorkoutSet(id: 's2', weight: 0, reps: 0, isCompleted: true),
        ],
      );
      final ex3 = _ex(
        '3',
        'Deadlift',
        sets: const [
          WorkoutSet(id: 's3', weight: 0, reps: 0, isCompleted: false),
        ],
      );
      final next = nextExerciseSuggestion([ex1, ex2, ex3], ex1);
      expect(next.name, 'Deadlift');
      expect(next.isNextSet, isFalse);
    });

    test('returns null when current is done and all later exercises are '
        'complete', () {
      final ex1 = _ex(
        '1',
        'Squat',
        sets: const [
          WorkoutSet(id: 's1', weight: 0, reps: 0, isCompleted: true),
        ],
      );
      final ex2 = _ex(
        '2',
        'Bench',
        sets: const [
          WorkoutSet(id: 's2', weight: 0, reps: 0, isCompleted: true),
        ],
      );
      final next = nextExerciseSuggestion([ex1, ex2], ex1);
      expect(next.name, isNull);
      expect(next.isNextSet, isFalse);
    });

    test('treats a not-yet-started (no sets) exercise as valid next work', () {
      final ex1 = _ex(
        '1',
        'Squat',
        sets: const [
          WorkoutSet(id: 's1', weight: 0, reps: 0, isCompleted: true),
        ],
      );
      final ex2 = _ex('2', 'Bench'); // planned, no sets logged yet
      final next = nextExerciseSuggestion([ex1, ex2], ex1);
      expect(next.name, 'Bench');
      expect(next.isNextSet, isFalse);
    });

    test('returns null when the only (last) exercise is complete', () {
      final ex1 = _ex(
        '1',
        'Squat',
        sets: const [
          WorkoutSet(id: 's1', weight: 0, reps: 0, isCompleted: true),
        ],
      );
      final next = nextExerciseSuggestion([ex1], ex1);
      expect(next.name, isNull);
      expect(next.isNextSet, isFalse);
    });

    test('returns null for an empty exercise list', () {
      final next = nextExerciseSuggestion(const [], _ex('1', 'Squat'));
      expect(next.name, isNull);
      expect(next.isNextSet, isFalse);
    });

    test('returns null when current is not in the list', () {
      final next = nextExerciseSuggestion([
        _ex('1', 'Squat'),
      ], _ex('99', 'Curl'));
      expect(next.name, isNull);
      expect(next.isNextSet, isFalse);
    });
  });
}
