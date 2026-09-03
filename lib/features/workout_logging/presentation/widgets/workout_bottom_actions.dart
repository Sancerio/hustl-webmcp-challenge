import 'package:flutter/material.dart';

import '../widgets/add_exercise_button.dart';

class WorkoutBottomActions extends StatelessWidget {
  final EdgeInsets padding;
  final bool hasExercises;
  final VoidCallback onAddExercise;

  const WorkoutBottomActions({
    super.key,
    required this.padding,
    required this.hasExercises,
    required this.onAddExercise,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasExercises)
            AddExerciseButton(onPressed: onAddExercise, isCompact: false)
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}
