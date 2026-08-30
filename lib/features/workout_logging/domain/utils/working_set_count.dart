import '../models/workout_exercise.dart';

/// Working-set tallies for an exercise.
///
/// A dropset reads as **one** working set: its lighter "drops" are linked
/// sub-sets (`parentSetId != null`) that roll into the parent for any place the
/// app shows a set TALLY (the "X of Y sets" finish bar, weekly set counts, …).
/// Drops still count toward VOLUME (they are real sets with reps) — this helper
/// is only about set *counts*, never volume math.
///
/// A working set is any set with `parentSetId == null` (a real top-level set).
/// Legacy sets have `parentSetId == null`, so this is identical to the old
/// `sets.length` / `sets.where(...)` behavior until drops actually exist.
extension WorkoutExerciseWorkingSetCount on WorkoutExercise {
  /// Total number of working (top-level) sets, counting each dropset as one.
  int get workingSetCount => sets.where((s) => s.parentSetId == null).length;

  /// Number of completed working sets, counting each dropset as one.
  int get completedWorkingSetCount =>
      sets.where((s) => s.parentSetId == null && s.isCompleted).length;
}
