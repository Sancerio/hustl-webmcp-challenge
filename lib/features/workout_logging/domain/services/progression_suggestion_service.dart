import '../../../exercise_library/domain/models/exercise.dart';
import '../models/workout_set.dart';
import '../utils/effort_scale.dart';

/// Display unit the suggestion rounds in. Weights are STORED in kg everywhere in
/// the app; this only changes the increment/rounding grid so a suggestion lands
/// on a real plate jump in the unit the user reads (2.5 kg / 5 lb).
enum ProgressionUnit { kg, lb }

/// A conservative next-set target derived from the previous session. Immutable
/// and a pure function of its inputs — no clock, no I/O. [weightKg] is always in
/// kilograms (the stored unit); the display unit only affected how it was
/// rounded.
class ProgressionSuggestion {
  const ProgressionSuggestion({required this.weightKg, required this.reps});

  final double weightKg;
  final int reps;

  @override
  bool operator ==(Object other) =>
      other is ProgressionSuggestion &&
      other.weightKg == weightKg &&
      other.reps == reps;

  @override
  int get hashCode => Object.hash(weightKg, reps);

  @override
  String toString() =>
      'ProgressionSuggestion(weightKg: $weightKg, reps: $reps)';
}

/// Suggests the next set (progressive overload) from the previous session's
/// performance. Deliberately dumb and conservative — a bad suggestion erodes
/// trust, so the rules never push hard and any ambiguity yields NO suggestion.
///
/// Double progression, deterministic. For a completed previous working set:
///
/// | # | Condition                                   | Suggestion                                   |
/// |---|---------------------------------------------|----------------------------------------------|
/// | 1 | no previous working set at the index        | none                                         |
/// | 2 | logging mode is not weight×reps             | none (timed/distance/bodyweight-only defer)  |
/// | 3 | previous set is not completed               | none                                         |
/// | 4 | reps >= 8 and jump <= +5%                    | weight + increment, same reps                |
/// | 4 | reps >= 8 and jump  > +5% (light isolation) | same weight, reps + 1                        |
/// | 5 | reps < 8                                     | same weight, reps + 1                        |
/// | 6 | effort at 0 RIR (RPE 10 — trained to failure)| same weight × same reps (consolidate)        |
/// | 7 | (always) round weight to 0.5 kg / 1.25 lb   | —                                            |
/// | 8 | weight <= 0 (bodyweight/assisted)           | none                                         |
///
/// `increment` is 2.5 kg (or 5 lb when the display unit is lb). Rule 6 is checked
/// BEFORE rules 4–5: a set taken to failure gets consolidated, not pushed. When
/// effort data is absent, rules 4–5 apply.
class ProgressionSuggestionService {
  const ProgressionSuggestionService();

  static const double _lbPerKg = 2.2046226218487757;
  static const double _kgPerLb = 0.45359237;

  /// Suggests the next set for the working set at [workingSetIndex] (0-based)
  /// among [previousSessionSets]. Working sets are the top-level, non-warm-up
  /// sets — the same set the row shows in its "Previous" column (drops and
  /// warm-ups are excluded, mirroring the seeding filter in `set_utils.dart`).
  /// Returns null when there is no working set at that index (rule 1).
  ProgressionSuggestion? suggestForWorkingSetIndex({
    required List<WorkoutSet> previousSessionSets,
    required int workingSetIndex,
    required ExerciseLoggingMode loggingMode,
    ProgressionUnit unit = ProgressionUnit.kg,
  }) {
    final working = previousSessionSets
        .where(
          (set) => set.parentSetId == null && set.setType != SetType.warmup,
        )
        .toList(growable: false);
    if (workingSetIndex < 0 || workingSetIndex >= working.length) {
      return null;
    }
    return suggestFromPreviousSet(
      previous: working[workingSetIndex],
      loggingMode: loggingMode,
      unit: unit,
    );
  }

  /// Applies rules 2–8 to a single [previous] working set. Callers that already
  /// hold the row-aligned previous set (the set row) use this directly; the
  /// index-based entry point filters then delegates here.
  ProgressionSuggestion? suggestFromPreviousSet({
    required WorkoutSet previous,
    required ExerciseLoggingMode loggingMode,
    ProgressionUnit unit = ProgressionUnit.kg,
  }) {
    // Rule 2: only weight×reps logging carries a weight+reps target. Timed,
    // distance, and bodyweight-only modes defer to a later iteration.
    if (loggingMode != ExerciseLoggingMode.weightReps) return null;

    // Rule 3: an incomplete previous set is not a result to progress from.
    if (!previous.isCompleted) return null;

    // Rule 8 (+ assisted guard): a suggestion needs a real load and reps.
    // weight == 0 is a bodyweight row; a negative weight is assisted work,
    // where the +5% cap math is meaningless — both defer.
    if (previous.weight <= 0 || previous.reps <= 0) return null;

    // Rule 6: trained to failure (0 reps in reserve, i.e. RPE 10). Consolidate
    // the same weight × reps rather than pushing. Checked before rules 4–5.
    if (EffortScale.rirFromRpe(previous.rpe) == 0) {
      return ProgressionSuggestion(
        weightKg: previous.weight,
        reps: previous.reps,
      );
    }

    final bool isLb = unit == ProgressionUnit.lb;
    final double increment = isLb ? 5.0 : 2.5;
    final double step = isLb ? 1.25 : 0.5;
    final double prevInUnit = isLb
        ? previous.weight * _lbPerKg
        : previous.weight;

    double suggestedInUnit;
    int suggestedReps;
    if (previous.reps >= 8) {
      // Rule 4. Cap: a weight jump over +5% is too big for a light isolation
      // lift (2.5 kg on a 20 kg curl is 12.5%), so add a rep instead.
      if (increment > 0.05 * prevInUnit) {
        suggestedInUnit = prevInUnit;
        suggestedReps = previous.reps + 1;
      } else {
        suggestedInUnit = prevInUnit + increment;
        suggestedReps = previous.reps;
      }
    } else {
      // Rule 5.
      suggestedInUnit = prevInUnit;
      suggestedReps = previous.reps + 1;
    }

    // Rule 7: round in the display unit so the target lands on a real plate.
    final double roundedInUnit = (suggestedInUnit / step).round() * step;
    final double weightKg = isLb ? roundedInUnit * _kgPerLb : roundedInUnit;
    return ProgressionSuggestion(weightKg: weightKg, reps: suggestedReps);
  }
}
