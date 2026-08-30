import 'package:flutter/material.dart';

/// Utility class for determining appropriate exercise icons
class ExerciseIconUtil {
  /// Returns an appropriate icon based on the exercise name and muscle group
  static IconData getExerciseIcon(String exerciseName, String muscleGroup) {
    final nameLower = exerciseName.toLowerCase();
    final muscleLower = muscleGroup.toLowerCase();

    // Check for specific exercise types in name
    if (nameLower.contains('bench press') ||
        nameLower.contains('chest press')) {
      return Icons.fitness_center;
    }

    if (nameLower.contains('curl')) {
      return Icons.sports_gymnastics;
    }

    if (nameLower.contains('squat') || nameLower.contains('leg')) {
      return Icons.accessibility_new;
    }

    if (nameLower.contains('deadlift')) {
      return Icons.fitness_center;
    }

    if (nameLower.contains('pull') || nameLower.contains('row')) {
      return Icons.swap_vert;
    }

    if (nameLower.contains('press') || nameLower.contains('push')) {
      return Icons.arrow_upward;
    }

    // If no specific exercise match, use muscle groups
    if (muscleLower.contains('chest')) {
      return Icons.fitness_center;
    }

    if (muscleLower.contains('back')) {
      return Icons.accessibility_new;
    }

    if (muscleLower.contains('bicep')) {
      return Icons.sports_gymnastics;
    }

    if (muscleLower.contains('tricep')) {
      return Icons.sports_gymnastics;
    }

    if (muscleLower.contains('shoulder')) {
      return Icons.arrow_upward;
    }

    if (muscleLower.contains('leg') ||
        muscleLower.contains('quad') ||
        muscleLower.contains('glute') ||
        muscleLower.contains('hamstring')) {
      return Icons.accessibility_new;
    }

    // Default icon for any other exercise
    return Icons.fitness_center;
  }

  /// Returns an appropriate background color based on muscle group
  static Color getExerciseColor(String muscleGroup, ColorScheme colorScheme) {
    final muscleLower = muscleGroup.toLowerCase();

    if (muscleLower.contains('chest')) {
      return colorScheme.primaryContainer;
    }

    if (muscleLower.contains('back')) {
      return colorScheme.secondaryContainer;
    }

    if (muscleLower.contains('bicep') || muscleLower.contains('tricep')) {
      return colorScheme.tertiaryContainer;
    }

    if (muscleLower.contains('shoulder')) {
      return colorScheme.errorContainer;
    }

    if (muscleLower.contains('leg') ||
        muscleLower.contains('quad') ||
        muscleLower.contains('glute') ||
        muscleLower.contains('hamstring')) {
      return colorScheme.surfaceContainerHighest;
    }

    // Default color
    return colorScheme.secondaryContainer;
  }
}
