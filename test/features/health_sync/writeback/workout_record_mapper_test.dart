import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/health_sync/domain/writeback/workout_record.dart';
import 'package:hustl_app/features/health_sync/domain/writeback/workout_record_mapper.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';

void main() {
  group('WorkoutRecord', () {
    test('externalId is derived from session id', () {
      final record = WorkoutRecord(
        sessionId: 'session-123',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2024, 1, 1, 12),
        endedAt: DateTime.utc(2024, 1, 1, 13),
        duration: 3600,
      );

      expect(record.externalId, 'hustl:session-123');
    });

    test('payloadHash is stable and changes with payload updates', () {
      final recordA = WorkoutRecord(
        sessionId: 'session-123',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2024, 1, 1, 12),
        endedAt: DateTime.utc(2024, 1, 1, 13),
        duration: 3600,
        energyKilocalories: 120,
        metadata: {'planId': 'plan-1'},
      );

      final recordB = WorkoutRecord(
        sessionId: 'session-123',
        activityType: WorkoutActivityType.strength,
        startedAt: DateTime.utc(2024, 1, 1, 12),
        endedAt: DateTime.utc(2024, 1, 1, 13),
        duration: 3600,
        energyKilocalories: 120,
        metadata: {'planId': 'plan-1'},
      );

      final hashA = recordA.payloadHash();
      final hashB = recordB.payloadHash();

      expect(hashA, hashB);

      final hashAfterMetadataChange = recordA
          .copyWith(metadata: {'planId': 'plan-2'})
          .payloadHash();
      expect(hashAfterMetadataChange, hashA);

      final hashAfterChange = recordA
          .copyWith(energyKilocalories: 150)
          .payloadHash();
      expect(hashAfterChange, isNot(hashA));
    });
  });

  group('WorkoutRecordMapper', () {
    const mapper = WorkoutRecordMapper();

    WorkoutSession buildSession({
      String name = 'Strength Session',
      List<WorkoutExercise>? exercises,
      DateTime? start,
      DateTime? end,
    }) {
      final startTime = start ?? DateTime.utc(2024, 1, 1, 12);
      final endTime = end ?? startTime.add(const Duration(minutes: 45));
      return WorkoutSession(
        id: 'session-1',
        name: name,
        startTime: startTime,
        endTime: endTime,
        exercises: exercises ?? const [],
        isCompleted: true,
      );
    }

    WorkoutExercise buildExercise({
      required Exercise exercise,
      List<WorkoutSet>? sets,
    }) {
      return WorkoutExercise(
        id: 'exercise-${exercise.name}',
        exercise: exercise,
        sets: sets ?? const [],
      );
    }

    test('infers running activity from session title', () {
      final session = buildSession(name: 'Morning Run');

      final record = mapper.fromSession(session);

      expect(record.activityType, WorkoutActivityType.running);
    });

    test('infers cycling from cardio exercise kind', () {
      const exercise = Exercise(
        name: 'Stationary Bike',
        muscles: ['legs'],
        kind: ExerciseKind.cardio,
      );
      final session = buildSession(
        exercises: [buildExercise(exercise: exercise)],
      );

      final record = mapper.fromSession(session);

      expect(record.activityType, WorkoutActivityType.cycling);
    });

    test('estimates energy from completed sets', () {
      const exercise = Exercise(name: 'Bench Press', muscles: ['chest']);
      final sets = [
        const WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: true),
        const WorkoutSet(id: 'set-2', weight: 100, reps: 5, isCompleted: false),
      ];
      final session = buildSession(
        exercises: [buildExercise(exercise: exercise, sets: sets)],
      );

      final record = mapper.fromSession(session);

      expect(record.energyKilocalories, closeTo(2.5, 0.01));
      expect(record.distanceMeters, isNull);
    });
  });
}
