import 'models/workout_exercise.dart';

/// Whether [exercise] is fully completed: it has logged sets and every one of
/// them is marked complete. An exercise with no sets logged yet is still
/// "planned" work, so it is deliberately NOT treated as completed.
bool isExerciseFullyCompleted(WorkoutExercise exercise) =>
    exercise.sets.isNotEmpty && exercise.sets.every((s) => s.isCompleted);

/// Index of the first exercise after [fromIndex] that still has work left,
/// skipping any fully-completed exercises, or `null` when none remain.
///
/// Shared by the active-workout screen and the watch bridge so the rest-timer
/// notification names the same "next exercise" on both surfaces and never a
/// stale/already-finished one.
int? nextIncompleteExerciseIndex(
  List<WorkoutExercise> exercises,
  int fromIndex,
) {
  for (var i = fromIndex + 1; i < exercises.length; i++) {
    if (!isExerciseFullyCompleted(exercises[i])) return i;
  }
  return null;
}
