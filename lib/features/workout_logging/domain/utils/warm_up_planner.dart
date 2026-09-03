import 'dart:math' as math;

import '../models/workout_set.dart';
import '../../../exercise_library/domain/models/exercise.dart';

/// Where the warm-up ramp's target weight came from. Drives the "Ramping
/// from …" microcopy in the planner sheet so the lifter can see, and override,
/// what the %-ladder is anchored to.
enum WarmUpSeedSource {
  /// A working set already logged in the current session.
  currentSet,

  /// The exercise's all-time PR (heaviest for strength, lightest for assisted).
  pr,

  /// The top set from the previous session.
  previousSession,

  /// A target the lifter typed into the planner.
  typed,
}

/// The resolved anchor the warm-up ramp builds from: a target weight, the rep
/// count to carry, and where it came from. [targetWeight] is signed the same
/// way logged weights are (assisted loads are negative).
class WarmUpSeed {
  const WarmUpSeed({
    required this.targetWeight,
    required this.reps,
    required this.source,
  });

  final double targetWeight;
  final int reps;
  final WarmUpSeedSource source;

  /// Absolute (always positive) magnitude of the target, for display.
  double get displayWeight => targetWeight.abs();
}

/// A single proposed warm-up set: a fraction [percentage] of the working
/// target, the resulting [weight] (signed like the target), and [reps].
/// [selected] is mutable so the sheet can toggle it.
class WarmUpSuggestion {
  WarmUpSuggestion({
    required this.percentage,
    required this.weight,
    required this.reps,
    this.selected = true,
  });

  final double percentage;
  final double weight;
  final int reps;
  bool selected;

  WarmUpSuggestion copy() {
    return WarmUpSuggestion(
      percentage: percentage,
      weight: weight,
      reps: reps,
      selected: selected,
    );
  }
}

/// Round a warm-up weight, keeping up to two decimals so micro-plate warm-ups
/// (e.g. 3.75 kg) are not silently rounded — matches the precision logged
/// weights carry.
double roundWarmUpWeight(double value) {
  return double.parse(value.toStringAsFixed(2));
}

/// Pick the heaviest (strength) or lightest (assisted) eligible set from
/// [sets], ignoring warm-ups and zero/blank loads. Returns null when nothing
/// qualifies. Pure — used for both the current and previous session scans.
WorkoutSet? topWorkingSet(
  Iterable<WorkoutSet> sets, {
  required bool isAssisted,
}) {
  WorkoutSet? best;
  double? bestMagnitude;
  for (final set in sets) {
    if (set.setType == SetType.warmup) continue;
    final magnitude = isAssisted ? set.weight.abs() : set.weight;
    if (magnitude <= 0) continue;
    if (bestMagnitude == null ||
        (isAssisted ? magnitude < bestMagnitude : magnitude > bestMagnitude)) {
      bestMagnitude = magnitude;
      best = set;
    }
  }
  return best;
}

/// Resolve the warm-up seed by priority — without any "must log a working set
/// first" gate. Order:
///   1. current-session top working set
///   2. PR (assisted PR is the *lightest*, already captured by the caller)
///   3. previous-session top working set
///   4. nothing (caller falls back to a typed target)
///
/// [prWeight]/[prReps] come from the (possibly still-resolving) PR future; pass
/// null when the PR is unknown so resolution simply skips that rung. All inputs
/// are plain values, so this is trivially testable.
WarmUpSeed? resolveWarmUpSeed({
  required Iterable<WorkoutSet> currentSets,
  Iterable<WorkoutSet>? previousSessionSets,
  double? prWeight,
  int? prReps,
  required bool isAssisted,
}) {
  final current = topWorkingSet(currentSets, isAssisted: isAssisted);
  if (current != null) {
    return WarmUpSeed(
      targetWeight: current.weight,
      reps: current.reps > 0 ? current.reps : 5,
      source: WarmUpSeedSource.currentSet,
    );
  }

  if (prWeight != null && prWeight.abs() > 0) {
    return WarmUpSeed(
      targetWeight: prWeight,
      reps: (prReps != null && prReps > 0) ? prReps : 5,
      source: WarmUpSeedSource.pr,
    );
  }

  if (previousSessionSets != null) {
    final previous = topWorkingSet(previousSessionSets, isAssisted: isAssisted);
    if (previous != null) {
      return WarmUpSeed(
        targetWeight: previous.weight,
        reps: previous.reps > 0 ? previous.reps : 5,
        source: WarmUpSeedSource.previousSession,
      );
    }
  }

  return null;
}

/// Build the warm-up %-ladder from a single target. Pure: no logged working set
/// is required — just a number. Ramps 40 / 60 / 75 (/ 90 for low working reps)
/// percent of [targetWeight]. For assisted machines the ladder *inverts*: a
/// warm-up is heavier assistance (lighter effort), so each step adds assistance
/// above the target rather than removing load.
///
/// [targetWeight] may be signed (assisted = negative) or positive; only its
/// magnitude is used and [isAssisted] re-applies the sign. Returns suggestions
/// sorted easiest-first (lightest effort first).
List<WarmUpSuggestion> buildWarmUpSuggestions({
  required double targetWeight,
  required int reps,
  required bool isAssisted,
}) {
  final baseAbsWeight = targetWeight.abs();
  if (baseAbsWeight <= 0) return const [];

  final workingReps = reps > 0 ? reps : 5;
  final baseReps = math.max(workingReps, 3);
  final suggestions = <WarmUpSuggestion>[];

  void addSuggestion({required double percentage, required int reps}) {
    final suggestedAbs = isAssisted
        ? baseAbsWeight + (1 - percentage) * baseAbsWeight
        : baseAbsWeight * percentage;
    if (suggestedAbs < 1) return;
    final rounded = roundWarmUpWeight(suggestedAbs);
    if (rounded <= 0) return;
    final actualWeight = isAssisted ? -rounded : rounded;
    final alreadyExists = suggestions.any(
      (existing) => (existing.weight - actualWeight).abs() < 0.001,
    );
    if (alreadyExists) return;
    suggestions.add(
      WarmUpSuggestion(
        percentage: percentage,
        weight: actualWeight,
        reps: reps,
      ),
    );
  }

  addSuggestion(
    percentage: 0.4,
    reps: math.min(12, math.max(baseReps + 6, 8)),
  );
  addSuggestion(
    percentage: 0.6,
    reps: math.min(10, math.max(baseReps + 2, 6)),
  );
  addSuggestion(percentage: 0.75, reps: math.max(math.min(baseReps, 8), 4));
  if (baseReps <= 6) {
    addSuggestion(percentage: 0.9, reps: math.max(baseReps - 3, 2));
  }

  suggestions.sort((a, b) {
    final aAbs = a.weight.abs();
    final bAbs = b.weight.abs();
    // Easiest effort first: for assisted that's the MOST assistance (heaviest
    // magnitude); for strength that's the lightest bar.
    if (isAssisted) {
      return bAbs.compareTo(aAbs);
    }
    return aAbs.compareTo(bAbs);
  });

  return suggestions;
}

/// True when warm-up planning applies to this exercise. The %-ladder is
/// kg-based, so it only makes sense in the WEIGHT-BASED logging mode
/// ([ExerciseLoggingMode.weightReps]) — the only mode that surfaces a weight
/// field and treats `reps` as reps. Duration-only "strength" moves (Wall Sit,
/// Plank) still have `kind == strength` but hide weight and interpret `reps`
/// as seconds, so seeding kg warm-ups into them would persist hidden-weight
/// rows with nonsensical "8-12 second" durations. Distance/duration cardio is
/// likewise excluded. Gate on logging mode, never on [ExerciseKind] alone.
bool warmUpSupportsLogging(ExerciseLoggingMode loggingMode) =>
    loggingMode == ExerciseLoggingMode.weightReps;
