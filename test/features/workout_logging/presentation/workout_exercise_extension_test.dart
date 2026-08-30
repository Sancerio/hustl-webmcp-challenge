import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/presentation/screens/workout_summary_screen.dart';

void main() {
  test('toTemplateExercise includes previous set types', () {
    const exercise = WorkoutExercise(
      id: '1',
      exercise: Exercise(name: 'squat', muscles: []),
      sets: [
        WorkoutSet(id: 'a', weight: 0, reps: 0, setType: SetType.warmup),
        WorkoutSet(id: 'b', weight: 0, reps: 0, setType: SetType.failure),
      ],
    );

    final result = exercise.toTemplateExercise();
    final prev = result['previousSets'] as List<dynamic>;
    expect(prev[0]['setType'], 'warmup');
    expect(prev[1]['setType'], 'failure');
  });
}
