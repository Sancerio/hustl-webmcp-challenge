import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/data/mappers/workout_server_mapper.dart';

void main() {
  group('WorkoutServerMapper cardio mapping', () {
    test('maps cardio distance/duration into weight/reps', () {
      final map = <String, dynamic>{
        'id': 'w1',
        'name': 'Run',
        'start_time': DateTime.now().toUtc().toIso8601String(),
        'end_time': DateTime.now().toUtc().toIso8601String(),
        'status': 'completed',
        'exercises': [
          {
            'id': 'we1',
            'exercise_name': 'Treadmill Run',
            'exercise_kind': 'cardio',
            'order_index': 0,
            'sets': [
              {
                'id': 's1',
                'set_number': 1,
                // distance column is metres (backend contract); app maps to km.
                'distance': 2500,
                'duration': 600,
                'rpe': null,
                'is_completed': true,
                'set_type': 'regular',
              },
            ],
          },
        ],
      };

      final session = WorkoutServerMapper.sessionFromServerMap(map);
      expect(session.exercises, hasLength(1));
      final exercise = session.exercises.single;
      expect(
        exercise.exercise.loggingMode,
        ExerciseLoggingMode.distanceDuration,
      );
      expect(exercise.sets, hasLength(1));
      final set = exercise.sets.single;
      expect(set.weight, 2.5); // 2500 m -> 2.5 km
      expect(set.reps, 600);
    });

    test('maps cardio duration-only into reps with zero weight', () {
      final map = <String, dynamic>{
        'id': 'w2',
        'name': 'Jump Rope',
        'start_time': DateTime.now().toUtc().toIso8601String(),
        'end_time': DateTime.now().toUtc().toIso8601String(),
        'status': 'completed',
        'exercises': [
          {
            'id': 'we2',
            'exercise_name': 'Jump Rope',
            'exercise_kind': 'cardio',
            'order_index': 0,
            'sets': [
              {
                'id': 's2',
                'set_number': 1,
                'distance': null,
                'duration': 90,
                'is_completed': true,
                'set_type': 'regular',
              },
            ],
          },
        ],
      };

      final session = WorkoutServerMapper.sessionFromServerMap(map);
      final exercise = session.exercises.single;
      expect(exercise.exercise.loggingMode, ExerciseLoggingMode.durationOnly);
      final set = exercise.sets.single;
      expect(set.weight, 0.0);
      expect(set.reps, 90);
    });

    test('keeps distance+duration when distance is present but zero', () {
      // A treadmill logged with time but no distance: the write path emits a
      // present distance column (0), which must not collapse the exercise to
      // duration-only on sync import.
      final map = <String, dynamic>{
        'id': 'w4',
        'name': 'Incline Walk',
        'start_time': DateTime.now().toUtc().toIso8601String(),
        'end_time': DateTime.now().toUtc().toIso8601String(),
        'status': 'completed',
        'exercises': [
          {
            'id': 'we4',
            'exercise_name': 'Treadmill',
            'exercise_kind': 'cardio',
            'order_index': 0,
            'sets': [
              {
                'id': 's4',
                'set_number': 1,
                'weight': 0,
                'reps': 1800,
                'distance': 0,
                'duration': 1800,
                'is_completed': true,
                'set_type': 'regular',
              },
            ],
          },
        ],
      };

      final session = WorkoutServerMapper.sessionFromServerMap(map);
      final exercise = session.exercises.single;
      expect(
        exercise.exercise.loggingMode,
        ExerciseLoggingMode.distanceDuration,
      );
      final set = exercise.sets.single;
      expect(set.weight, 0.0);
      expect(set.reps, 1800);
    });

    test('falls back to weight/reps when distance/duration are absent', () {
      final map = <String, dynamic>{
        'id': 'w3',
        'name': 'Legacy Cardio Sync',
        'start_time': DateTime.now().toUtc().toIso8601String(),
        'end_time': DateTime.now().toUtc().toIso8601String(),
        'status': 'completed',
        'exercises': [
          {
            'id': 'we3',
            'exercise_name': 'Bike Ride',
            'exercise_kind': 'cardio',
            'order_index': 0,
            'sets': [
              {
                'id': 's3',
                'set_number': 1,
                // Older synced cardio sets store distance in `weight` and
                // duration in `reps` because the sync payload omitted fields.
                'weight': 12.3,
                'reps': 1500,
                'distance': null,
                'duration': null,
                'is_completed': true,
                'set_type': 'regular',
              },
            ],
          },
        ],
      };

      final session = WorkoutServerMapper.sessionFromServerMap(map);
      final exercise = session.exercises.single;
      expect(
        exercise.exercise.loggingMode,
        ExerciseLoggingMode.distanceDuration,
      );
      final set = exercise.sets.single;
      expect(set.weight, 12.3);
      expect(set.reps, 1500);
    });
  });
}
