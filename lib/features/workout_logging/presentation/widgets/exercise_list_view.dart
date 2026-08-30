import 'package:flutter/material.dart';

import '../../domain/models/workout_session.dart';
import '../../domain/models/workout_exercise.dart';
import '../widgets/exercise_card.dart';

typedef ExerciseUpdate = Future<void> Function(WorkoutExercise updated);
typedef ExerciseStartRest =
    void Function(int? durationSeconds, WorkoutExercise exercise);

class ExerciseListView extends StatelessWidget {
  final WorkoutSession session;
  final EdgeInsets padding;
  final ExerciseUpdate onExerciseUpdated;
  final ExerciseStartRest onStartRestTimer;
  final Function(String) onExerciseDeleted;
  final Function(String) onExerciseReplaced;

  const ExerciseListView({
    super.key,
    required this.session,
    required this.padding,
    required this.onExerciseUpdated,
    required this.onStartRestTimer,
    required this.onExerciseDeleted,
    required this.onExerciseReplaced,
  });

  @override
  Widget build(BuildContext context) {
    if (session.exercises.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      padding: padding,
      itemCount: session.exercises.length,
      itemBuilder: (context, index) {
        final exercise = session.exercises[index];
        return ExerciseCard(
          exercise: exercise,
          onExerciseUpdated: onExerciseUpdated,
          onStartRestTimer: (int? durationSeconds) =>
              onStartRestTimer(durationSeconds, exercise),
          onExerciseDeleted: onExerciseDeleted,
          onExerciseReplaced: onExerciseReplaced,
        );
      },
    );
  }
}
