import 'dart:collection';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';

import '../../../workout_logging/domain/models/workout_session.dart';
import '../../../workout_logging/domain/models/workout_exercise.dart';
import '../../../workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/workout_progress_utils.dart';
import '../models/exercise.dart';

class ExerciseRecordService {
  const ExerciseRecordService();

  bool _isBetterSet(
    WorkoutSet candidate,
    WorkoutSet current,
    Exercise exercise, {
    required bool isAssisted,
  }) {
    final mode = exercise.loggingMode;
    if (mode == ExerciseLoggingMode.durationOnly) {
      return candidate.reps > current.reps;
    }
    if (mode == ExerciseLoggingMode.distanceDuration) {
      if (candidate.weight != current.weight) {
        return candidate.weight > current.weight;
      }
      // For the same distance, prefer faster time (lower seconds).
      return candidate.reps < current.reps;
    }

    // weightReps
    if (isAssisted) {
      // Assisted work uses negative weights; only compare valid entries.
      if (candidate.weight >= 0) return false;
      if (current.weight >= 0) return true;
    }
    return candidate.weight > current.weight ||
        (candidate.weight == current.weight && candidate.reps > current.reps);
  }

  double _primaryValue(
    RecordEntry e,
    Exercise exercise, {
    required bool useEstimated1Rm,
  }) {
    switch (exercise.loggingMode) {
      case ExerciseLoggingMode.durationOnly:
        return e.set.reps.toDouble();
      case ExerciseLoggingMode.distanceDuration:
        return e.set.weight;
      case ExerciseLoggingMode.weightReps:
        return useEstimated1Rm
            ? estimate1Rm(e.set.weight, e.set.reps)
            : e.set.weight;
    }
  }

  /// Build record entries (best completed set per completed session) for an exercise.
  List<RecordEntry> buildEntries(
    List<WorkoutSession> sessions,
    Exercise exercise,
  ) {
    final entries = <RecordEntry>[];
    final targetName = exercise.name;
    final targetSlug = exercise.slug;
    for (final s in sessions.where((s) => s.isCompleted)) {
      final WorkoutExercise? ex = s.exercises.firstWhereOrNull(
        (e) => e.exercise.matchesIdentity(name: targetName, slug: targetSlug),
      );
      if (ex == null) continue;

      final isAssisted = ex.exercise.kind == ExerciseKind.assisted;
      WorkoutSet? best;
      for (final set in ex.sets.where(
        // Warm-up sets and dropset drops are never record candidates — a light
        // warm-up or a lighter drop must not win a record via the Epley
        // estimate. Only the heavy top set of a dropset is eligible (it stays a
        // regular/failure set). Mirrors the repo PR guards.
        (set) =>
            set.isCompleted &&
            set.setType != SetType.warmup &&
            set.setType != SetType.dropset,
      )) {
        if (exercise.loggingMode == ExerciseLoggingMode.weightReps &&
            isAssisted &&
            set.weight >= 0) {
          continue;
        }
        if (best == null) {
          best = set;
          continue;
        }
        if (_isBetterSet(set, best, exercise, isAssisted: isAssisted)) {
          best = set;
        }
      }
      if (best != null) {
        entries.add(RecordEntry(date: s.startTime, set: best));
      }
    }
    entries.sort((a, b) => a.date.compareTo(b.date));
    return entries;
  }

  /// Find the personal record across entries, based on the exercise's logging mode.
  ///
  /// Ties preserve the earliest entry.
  RecordEntry? findPersonalRecord(
    List<RecordEntry> entries,
    Exercise exercise,
  ) {
    if (entries.isEmpty) return null;
    // Reduce while preserving earliest on ties.
    RecordEntry best = entries.first;
    for (final e in entries.skip(1)) {
      if (_isBetterSet(
        e.set,
        best.set,
        exercise,
        isAssisted: exercise.kind == ExerciseKind.assisted,
      )) {
        best = e;
      }
    }
    return best;
  }

  /// Generate ordered chart data grouped by the provided [group].
  ///
  /// Policy per group:
  /// - day:   best (max) weight for the day
  /// - week:  best (max) weight for ISO week (YYYY-Www)
  /// - month: best (max) weight for month (YYYY-MM)
  Map<String, double> generateChartData(
    List<RecordEntry> entries, {
    TimeGroup group = TimeGroup.day,
    bool useEstimated1Rm = false,
    required Exercise exercise,
  }) {
    final effectiveUse1Rm =
        exercise.loggingMode == ExerciseLoggingMode.weightReps
        ? useEstimated1Rm
        : false;
    switch (group) {
      case TimeGroup.day:
        final map = <String, double>{};
        final df = DateFormat('yyyy-MM-dd');
        for (final e in entries) {
          final key = df.format(e.date.toLocal());
          final current = map[key];
          final value = _primaryValue(
            e,
            exercise,
            useEstimated1Rm: effectiveUse1Rm,
          );
          map[key] = (current == null || value > current) ? value : current;
        }
        return map;
      case TimeGroup.week:
        final temp = <String, double>{};
        for (final e in entries) {
          final d = e.date.toLocal();
          final week = isoWeekNumber(d);
          final weekKey = '${d.year}-W${week.toString().padLeft(2, '0')}';
          final current = temp[weekKey];
          final value = _primaryValue(
            e,
            exercise,
            useEstimated1Rm: effectiveUse1Rm,
          );
          temp[weekKey] = (current == null || value > current)
              ? value
              : current;
        }
        final ordered = temp.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        return LinkedHashMap.fromEntries(ordered);
      case TimeGroup.month:
        final temp = <String, double>{};
        for (final e in entries) {
          final d = e.date.toLocal();
          final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
          final current = temp[key];
          final value = _primaryValue(
            e,
            exercise,
            useEstimated1Rm: effectiveUse1Rm,
          );
          temp[key] = (current == null || value > current) ? value : current;
        }
        final ordered = temp.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        return LinkedHashMap.fromEntries(ordered);
    }
  }

  /// Epley 1RM estimate: weight * (1 + reps/30)
  double estimate1Rm(double weight, int reps) {
    if (reps <= 1) return weight;
    return weight * (1.0 + reps / 30.0);
  }

  /// Returns indices in the ordered chart series where a new PR milestone occurs
  /// (value strictly greater than any previous value in the series).
  Set<int> prMilestoneIndices(Map<String, double> orderedSeries) {
    final indices = <int>{};
    double best = -double.infinity;
    final values = orderedSeries.values.toList();
    for (int i = 0; i < values.length; i++) {
      if (values[i] > best) {
        best = values[i];
        indices.add(i);
      }
    }
    return indices;
  }

  /// Suggest the next target value given a series.
  /// - Uses simple plate increments: 1.25kg under 40kg, else 2.5kg
  /// - Suggests PR+step (for clarity) rounded to the same increment.
  double? suggestNextTarget(
    Map<String, double> orderedSeries,
    Exercise exercise,
  ) {
    if (exercise.loggingMode != ExerciseLoggingMode.weightReps) return null;
    if (orderedSeries.isEmpty) return null;
    final values = orderedSeries.values.toList();
    final currentPr = values.reduce((a, b) => a > b ? a : b);
    final step = currentPr < 40 ? 1.25 : 2.5;
    final target = currentPr + step;
    return _roundToIncrement(target, step);
  }

  double _roundToIncrement(double value, double inc) {
    return (value / inc).roundToDouble() * inc;
  }

  /// Count PR sets for this exercise across all sessions.
  int countPrSets(List<WorkoutSession> sessions, Exercise exercise) {
    final targetName = exercise.name;
    final targetSlug = exercise.slug;
    int count = 0;
    for (final s in sessions) {
      for (final ex in s.exercises) {
        if (!ex.exercise.matchesIdentity(name: targetName, slug: targetSlug)) {
          continue;
        }
        for (final set in ex.sets) {
          if (set.isCompleted && set.isPr) count++;
        }
      }
    }
    return count;
  }

  /// Find the most recent PR date for this exercise, if any.
  DateTime? lastPrDate(List<WorkoutSession> sessions, Exercise exercise) {
    final targetName = exercise.name;
    final targetSlug = exercise.slug;
    DateTime? last;
    for (final s in sessions) {
      for (final ex in s.exercises) {
        if (!ex.exercise.matchesIdentity(name: targetName, slug: targetSlug)) {
          continue;
        }
        if (ex.sets.any((set) => set.isCompleted && set.isPr)) {
          if (last == null || s.startTime.isAfter(last)) {
            last = s.startTime;
          }
        }
      }
    }
    return last;
  }
}

class RecordEntry {
  final DateTime date;
  final WorkoutSet set;
  const RecordEntry({required this.date, required this.set});
}
