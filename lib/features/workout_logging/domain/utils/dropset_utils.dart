import '../models/workout_set.dart';

/// Pure helpers for the dropset structure (parent working set + linked drops).
///
/// All linkage is id-based (`parentSetId`), never index-based, so it survives
/// reordering and id-based deletion. A working set has `parentSetId == null`; a
/// drop has `setType == SetType.dropset` and `parentSetId == <parent.id>`.
class DropsetUtils {
  const DropsetUtils._();

  /// Default load reduction applied when seeding a new drop from its parent
  /// (~15% lighter — the canonical dropset step).
  static const double dropStepFraction = 0.15;

  /// Suggested weight for the next drop hanging off [parentWeight], rounded to a
  /// sensible plate-friendly value. Always returns a value strictly lighter than
  /// the parent (so a real drop is never seeded at the parent's load), floored at
  /// the smallest sensible step.
  ///
  /// Assisted machines carry NEGATIVE weight (more assistance = lighter
  /// effective load); a "drop" there means LESS assistance, i.e. moving toward
  /// zero, so we reduce the magnitude and keep the sign.
  static double suggestedDropWeight(double parentWeight) {
    final magnitude = parentWeight.abs();
    if (magnitude <= 0) return parentWeight;
    final raw = magnitude * (1 - dropStepFraction);
    // Round down to the nearest 2.5 for plate-friendly numbers; never round up
    // to or above the parent.
    final floored = (raw / 2.5).floor() * 2.5;
    var reduced = floored > 0
        ? floored.toDouble()
        : double.parse(raw.toStringAsFixed(2));
    // Guard: must stay strictly below the parent magnitude.
    if (reduced >= magnitude) {
      reduced = (magnitude - 2.5).clamp(0, magnitude).toDouble();
    }
    return parentWeight < 0 ? -reduced : reduced;
  }

  /// The drops linked to [parentId] within [sets], ordered by their position in
  /// the list (which mirrors `dropIndex` after any renumber).
  static List<WorkoutSet> dropsFor(List<WorkoutSet> sets, String parentId) {
    return sets
        .where((s) => s.setType == SetType.dropset && s.parentSetId == parentId)
        .toList();
  }

  /// Re-derive contiguous 1-based [WorkoutSet.dropIndex] values for every drop in
  /// [sets], grouped by parent and in list order. Returns a new list; working
  /// sets are passed through untouched. Use after inserting/removing a drop so
  /// the `3.1 / 3.2 …` labels never gap.
  static List<WorkoutSet> renumberDrops(List<WorkoutSet> sets) {
    final counters = <String, int>{};
    return sets.map((s) {
      if (s.setType != SetType.dropset || s.parentSetId == null) return s;
      final parent = s.parentSetId!;
      final next = (counters[parent] ?? 0) + 1;
      counters[parent] = next;
      return s.dropIndex == next ? s : s.copyWith(dropIndex: next);
    }).toList();
  }
}
