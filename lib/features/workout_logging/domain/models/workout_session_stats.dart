import '../../../exercise_library/domain/models/exercise.dart';
import 'workout_exercise.dart';
import 'workout_session.dart';
import 'workout_set.dart';

/// Session-level derived statistics. Lives in the domain layer (was previously
/// declared as presentation-layer extensions inside workout_summary_screen.dart)
/// so the logic can be unit-tested without a widget harness.
extension WorkoutSessionStats on WorkoutSession {
  /// Total volume (weight x reps) across logged sets, rounded to whole units.
  ///
  /// Warm-up sets are excluded so they never inflate session/home/weekly volume
  /// (matches `history_session_metrics` and cross-app consensus).
  ///
  /// [completedOnly] is accepted for source compatibility; only sets with reps
  /// are ever counted, so the flag does not change the result.
  int calculateTotalVolume({bool completedOnly = false}) {
    var totalVolume = 0;
    for (final exercise in exercises) {
      if (exercise.exercise.loggingMode != ExerciseLoggingMode.weightReps) {
        continue;
      }
      for (final set in exercise.sets) {
        if (set.reps > 0 && set.setType != SetType.warmup) {
          totalVolume += (set.weight * set.reps).round();
        }
      }
    }
    return totalVolume;
  }

  /// Number of personal-record sets logged this session.
  int countPrSets() {
    var count = 0;
    for (final exercise in exercises) {
      if (exercise.exercise.loggingMode != ExerciseLoggingMode.weightReps) {
        continue;
      }
      for (final set in exercise.sets) {
        if (set.reps > 0 && set.isPr) {
          count++;
        }
      }
    }
    return count;
  }
}

/// Conversion of a workout exercise into a template-exercise map. Domain logic,
/// kept out of the presentation layer.
extension WorkoutExerciseTemplateConversion on WorkoutExercise {
  Map<String, dynamic> toTemplateExercise() {
    return {
      // Using name as the identifier since Exercise doesn't carry an id.
      'exerciseId': exercise.name,
      'sets': sets.length,
      'restTimerSeconds': restTimerSeconds,
      'previousSets': sets.map((s) => s.toMap()).toList(),
    };
  }
}
