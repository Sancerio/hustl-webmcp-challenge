import 'package:hustl_app/core/utils/number_format_util.dart';
import 'package:hustl_app/core/utils/time_format_util.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';

/// Pure, memoizable derivations for a history session card. Extracted from the
/// history screen so cards can precompute once instead of recomputing inline on
/// every scroll frame.
class HistorySessionMetrics {
  HistorySessionMetrics({
    required this.durationText,
    required this.prCount,
    required this.totalVolume,
    required this.bestSetByExerciseId,
    required this.bestSetRpeByExerciseId,
  });

  final String durationText;
  final int? prCount;
  final int? totalVolume;
  final Map<String, String> bestSetByExerciseId;

  /// The RPE logged on each exercise's best set, keyed by exercise id.
  /// Missing/null where no set or no effort was logged.
  final Map<String, int?> bestSetRpeByExerciseId;

  factory HistorySessionMetrics.from(WorkoutSession session) {
    final hasDetails = session.exercises.isNotEmpty;
    // Volume is a weight-training metric: a cardio/duration-only session shows
    // "—" rather than a misleading "0 kg".
    final hasWeightWork = session.exercises.any(
      (ex) => ex.exercise.loggingMode == ExerciseLoggingMode.weightReps,
    );
    return HistorySessionMetrics(
      durationText: formatSessionDuration(session),
      prCount: hasDetails ? countPrSets(session) : null,
      totalVolume: hasDetails && hasWeightWork
          ? totalSessionVolume(session)
          : null,
      bestSetByExerciseId: {
        for (final ex in session.exercises) ex.id: bestSetLabel(ex),
      },
      bestSetRpeByExerciseId: {
        for (final ex in session.exercises) ex.id: bestSet(ex)?.rpe,
      },
    );
  }
}

String formatSessionDuration(WorkoutSession session) {
  final duration = (session.endTime ?? DateTime.now()).difference(
    session.startTime,
  );
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  if (hours > 0) {
    return '$hours hr${minutes > 0 ? ' $minutes min' : ''}';
  } else if (minutes > 0) {
    return '$minutes min';
  }
  return seconds > 0 ? '$seconds sec' : 'Just started';
}

int countPrSets(WorkoutSession session) {
  var count = 0;
  for (final ex in session.exercises) {
    // PRs are weight-based; legacy cardio sets may carry stale isPr flags.
    if (ex.exercise.loggingMode != ExerciseLoggingMode.weightReps) continue;
    for (final s in ex.sets) {
      if (s.isPr) count++;
    }
  }
  return count;
}

int totalSessionVolume(WorkoutSession session) {
  var total = 0;
  for (final ex in session.exercises) {
    // Distance/duration modes store km and seconds in weight/reps — they are
    // not kg volume (mirrors WorkoutSession.totalVolume).
    if (ex.exercise.loggingMode != ExerciseLoggingMode.weightReps) continue;
    for (final s in ex.sets) {
      if (!s.isCompleted) continue;
      if (s.setType == SetType.warmup) continue;
      final weight = ex.exercise.kind == ExerciseKind.assisted
          ? s.weight.abs()
          : s.weight;
      total += (weight * s.reps).round();
    }
  }
  return total;
}

/// The best set for an exercise: the highest completed set (weight, then
/// reps), falling back to the highest logged set if none were completed.
/// Warmup sets are never considered "best". Shared by [bestSetLabel] and the
/// history card's compact effort gauge so both read the same set.
WorkoutSet? bestSet(WorkoutExercise ex) {
  WorkoutSet? bestCompleted;
  WorkoutSet? bestAny;
  for (final set in ex.sets) {
    if (set.setType == SetType.warmup) continue;
    if (bestAny == null ||
        set.weight > bestAny.weight ||
        (set.weight == bestAny.weight && set.reps > bestAny.reps)) {
      bestAny = set;
    }
    if (!set.isCompleted) continue;
    if (bestCompleted == null ||
        set.weight > bestCompleted.weight ||
        (set.weight == bestCompleted.weight && set.reps > bestCompleted.reps)) {
      bestCompleted = set;
    }
  }
  return bestCompleted ?? bestAny;
}

String bestSetLabel(WorkoutExercise ex) {
  if (ex.sets.isEmpty) return '-';
  final best = bestSet(ex);
  if (best == null) return '-';
  return switch (ex.exercise.loggingMode) {
    ExerciseLoggingMode.distanceDuration =>
      '${NumberFormatUtil.formatWeight(best.weight)} km × '
          '${TimeFormatUtil.formatMmSs(best.reps)}',
    ExerciseLoggingMode.durationOnly => TimeFormatUtil.formatMmSs(best.reps),
    ExerciseLoggingMode.weightReps =>
      '${NumberFormatUtil.formatWeight(best.weight)} kg × ${best.reps}',
  };
}
