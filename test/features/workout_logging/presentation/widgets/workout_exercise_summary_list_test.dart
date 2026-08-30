import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/workout_exercise_summary_list.dart';

void main() {
  testWidgets('distance-duration summary rows render km and time without kg', (
    tester,
  ) async {
    const exercise = WorkoutExercise(
      id: 'run',
      exercise: Exercise(
        name: 'Custom Run',
        muscles: ['Cardio'],
        loggingMode: ExerciseLoggingMode.distanceDuration,
      ),
      sets: [WorkoutSet(id: 'set', weight: 2.5, reps: 780, isCompleted: true)],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WorkoutExerciseSummaryList(
            exercises: [exercise],
            showTitle: false,
          ),
        ),
      ),
    );

    expect(find.textContaining('2.5 km × 13:00'), findsOneWidget);
    expect(find.textContaining('kg'), findsNothing);
  });
}
