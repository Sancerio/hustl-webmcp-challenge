import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/exercise_timeline_event.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session_stats.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';

void main() {
  group('volume excludes warm-up sets', () {
    // Two warm-ups (40/60 kg) + three working sets (100x5, 100x5, 105x3).
    // Working volume = 100*5 + 100*5 + 105*3 = 1315. Warm-ups must not count.
    final session = WorkoutSession(
      id: 's',
      name: 'Test',
      startTime: DateTime(2024),
      exercises: const [
        WorkoutExercise(
          id: 'bench',
          exercise: Exercise(name: 'Bench', muscles: []),
          sets: [
            WorkoutSet(
              id: 'w1',
              weight: 40,
              reps: 10,
              setType: SetType.warmup,
              isCompleted: true,
            ),
            WorkoutSet(
              id: 'w2',
              weight: 60,
              reps: 6,
              setType: SetType.warmup,
              isCompleted: true,
            ),
            WorkoutSet(id: 's1', weight: 100, reps: 5, isCompleted: true),
            WorkoutSet(id: 's2', weight: 100, reps: 5, isCompleted: true),
            WorkoutSet(id: 's3', weight: 105, reps: 3, isCompleted: true),
          ],
        ),
      ],
    );

    test('totalVolume getter skips completed warm-up sets', () {
      expect(session.totalVolume, 1315);
    });

    test('calculateTotalVolume skips warm-up sets', () {
      expect(session.calculateTotalVolume(), 1315);
    });

    test('a card with only warm-up sets contributes zero volume', () {
      final warmOnly = WorkoutSession(
        id: 's2',
        name: 'Warm only',
        startTime: DateTime(2024),
        exercises: const [
          WorkoutExercise(
            id: 'sq',
            exercise: Exercise(name: 'Squat', muscles: []),
            sets: [
              WorkoutSet(
                id: 'w',
                weight: 50,
                reps: 10,
                setType: SetType.warmup,
                isCompleted: true,
              ),
            ],
          ),
        ],
      );
      expect(warmOnly.totalVolume, 0);
      expect(warmOnly.calculateTotalVolume(), 0);
    });

    test('distance and duration logging does not contribute kg volume', () {
      final cardioOnly = WorkoutSession(
        id: 'run',
        name: 'Run',
        startTime: DateTime(2024),
        exercises: const [
          WorkoutExercise(
            id: 'run',
            exercise: Exercise(
              name: 'Run',
              muscles: [],
              loggingMode: ExerciseLoggingMode.distanceDuration,
            ),
            sets: [
              WorkoutSet(
                id: 'run-set',
                weight: 5,
                reps: 1500,
                isCompleted: true,
              ),
            ],
          ),
        ],
      );

      expect(cardioOnly.totalVolume, 0);
      expect(cardioOnly.calculateTotalVolume(), 0);
    });
  });

  test('complete removes unfinished sets but keeps empty exercises', () {
    const bench = WorkoutExercise(
      id: 'bench',
      exercise: Exercise(name: 'Bench', muscles: []),
      sets: [
        WorkoutSet(
          id: 'c1',
          weight: 100,
          reps: 5,
          isCompleted: true,
          isPr: false,
        ),
        WorkoutSet(
          id: 'i1',
          weight: 105,
          reps: 3,
          isCompleted: false,
          isPr: false,
        ),
      ],
      notes: 'bench notes',
    );
    const curls = WorkoutExercise(
      id: 'curls',
      exercise: Exercise(name: 'Curls', muscles: []),
      sets: [
        WorkoutSet(
          id: 'i2',
          weight: 20,
          reps: 10,
          isCompleted: false,
          isPr: false,
        ),
      ],
      notes: 'curl notes',
    );

    final session = WorkoutSession(
      id: 's',
      name: 'Test',
      startTime: DateTime(2024),
      exercises: const [bench, curls],
    );

    final completed = session.complete();

    expect(completed.isCompleted, true);
    expect(completed.endTime, isNotNull);
    expect(completed.exercises.length, 2);

    final completedBench = completed.exercises.firstWhere(
      (e) => e.id == 'bench',
    );
    final completedCurls = completed.exercises.firstWhere(
      (e) => e.id == 'curls',
    );

    expect(completedBench.sets.length, 1);
    expect(completedBench.sets.single.isCompleted, true);

    expect(completedCurls.sets, isEmpty);
    expect(completedCurls.notes, 'curl notes');
  });

  test('exercise metrics equality/hashCode uses deep equality', () {
    const baseExercise = Exercise(name: 'Bench', muscles: []);
    final raw = {
      'id': 'we1',
      'sets': const [],
      'metrics': const {
        'hr': {
          'avgBpm': 150,
          'zonesSec': {'z1': 0, 'z2': 10},
        },
      },
    };
    final a = WorkoutExercise.fromMap(raw, baseExercise);
    final b = WorkoutExercise.fromMap(raw, baseExercise);

    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('timeline events compare by value (session equality stable)', () {
    final map = {
      'id': 's1',
      'name': 'Workout',
      'startTime': DateTime(2024).millisecondsSinceEpoch,
      'endTime': null,
      'notes': null,
      'isCompleted': false,
      'dirty': true,
      'timelineEvents': [
        {
          'tsMs': 1000,
          'kind': ExerciseTimelineEventKind.workoutStart.name,
          'workoutExerciseId': null,
        },
        {
          'tsMs': 2000,
          'kind': ExerciseTimelineEventKind.select.name,
          'workoutExerciseId': 'we1',
        },
      ],
    };

    final sessionA = WorkoutSession.fromMap(map, const []);
    final sessionB = WorkoutSession.fromMap(map, const []);
    expect(sessionA, sessionB);
    expect(sessionA.hashCode, sessionB.hashCode);
  });
}
