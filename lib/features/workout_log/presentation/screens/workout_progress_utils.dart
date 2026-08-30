import 'package:flutter/material.dart';
import 'package:collection/collection.dart';

import '../../../workout_logging/domain/models/workout_session.dart';
import '../../../workout_logging/domain/models/workout_set.dart';

enum QuickDateRange {
  last2Weeks,
  last1Month,
  last3Months,
  last6Months,
  last1Year,
}

enum TimeGroup { day, week, month }

/// Attempts to infer the TimeGroup from a collection of keys.
///
/// Expected formats:
/// - day:   YYYY-MM-DD
/// - week:  YYYY-Www (ISO week, 2 digits)
/// - month: YYYY-MM
TimeGroup? inferTimeGroupFromKeys(Iterable<String> keys) {
  final iterator = keys.iterator;
  if (!iterator.moveNext()) return null;
  final sample = iterator.current;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(sample)) return TimeGroup.day;
  if (RegExp(r'^\d{4}-W\d{2}$').hasMatch(sample)) return TimeGroup.week;
  if (RegExp(r'^\d{4}-\d{2}$').hasMatch(sample)) return TimeGroup.month;
  return null;
}

DateTimeRange quickDateRange(QuickDateRange range, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final end = DateTime(current.year, current.month, current.day);
  DateTime start;
  switch (range) {
    case QuickDateRange.last2Weeks:
      start = end.subtract(const Duration(days: 13));
      break;
    case QuickDateRange.last1Month:
      start = DateTime(end.year, end.month - 1, end.day);
      break;
    case QuickDateRange.last3Months:
      start = DateTime(end.year, end.month - 3, end.day);
      break;
    case QuickDateRange.last6Months:
      start = DateTime(end.year, end.month - 6, end.day);
      break;
    case QuickDateRange.last1Year:
      start = DateTime(end.year - 1, end.month, end.day);
      break;
  }
  return DateTimeRange(start: start, end: end);
}

List<WorkoutSession> filterSessionsByDate(
  List<WorkoutSession> sessions,
  DateTimeRange? range,
) {
  if (range == null) return sessions;
  final endExclusive = range.end.add(const Duration(days: 1));
  return sessions
      .where(
        (s) =>
            !s.startTime.isBefore(range.start) &&
            s.startTime.isBefore(endExclusive),
      )
      .toList();
}

Map<String, double> volumeByWorkout(List<WorkoutSession> sessions) {
  final Map<String, double> totals = {};
  for (final s in sessions) {
    totals.update(
      s.name,
      (v) => v + s.totalVolume,
      ifAbsent: () => s.totalVolume,
    );
  }
  final entries = totals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return Map.fromEntries(entries);
}

Map<String, double> sessionsByWorkout(List<WorkoutSession> sessions) {
  final Map<String, int> counts = {};
  for (final s in sessions) {
    counts.update(s.name, (v) => v + 1, ifAbsent: () => 1);
  }
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return Map.fromEntries(
    entries.map((e) => MapEntry(e.key, e.value.toDouble())),
  );
}

Map<String, double> aggregateWeeklyVolume(List<WorkoutSession> sessions) {
  final Map<String, double> byWeek = {};
  for (final s in sessions) {
    final thursday = s.startTime.add(
      Duration(days: 3 - ((s.startTime.weekday + 6) % 7)),
    );
    final weekYear = thursday.year;
    final week = isoWeekNumber(s.startTime);
    final weekKey = '$weekYear-W${week.toString().padLeft(2, '0')}';
    byWeek.update(
      weekKey,
      (v) => v + s.totalVolume,
      ifAbsent: () => s.totalVolume,
    );
  }
  return Map.fromEntries(
    byWeek.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

Map<String, double> aggregateVolumeByPeriod(
  List<WorkoutSession> sessions,
  TimeGroup group,
) {
  switch (group) {
    case TimeGroup.day:
      final Map<String, double> byDay = {};
      for (final s in sessions) {
        final key =
            '${s.startTime.year}-${s.startTime.month.toString().padLeft(2, '0')}-${s.startTime.day.toString().padLeft(2, '0')}';
        byDay.update(
          key,
          (v) => v + s.totalVolume,
          ifAbsent: () => s.totalVolume,
        );
      }
      return Map.fromEntries(
        byDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
    case TimeGroup.week:
      return aggregateWeeklyVolume(sessions);
    case TimeGroup.month:
      final Map<String, double> byMonth = {};
      for (final s in sessions) {
        final key =
            '${s.startTime.year}-${s.startTime.month.toString().padLeft(2, '0')}';
        byMonth.update(
          key,
          (v) => v + s.totalVolume,
          ifAbsent: () => s.totalVolume,
        );
      }
      return Map.fromEntries(
        byMonth.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
  }
}

Map<String, double> topPrsByWeight(
  List<WorkoutSession> sessions, {
  int limit = 8,
}) {
  final Map<String, double> best = {};
  for (final s in sessions) {
    for (final ex in s.exercises) {
      for (final WorkoutSet set in ex.sets) {
        if (!set.isCompleted) continue;
        final key = ex.exercise.name;
        if (!best.containsKey(key) || set.weight > best[key]!) {
          best[key] = set.weight;
        }
      }
    }
  }

  final pq = HeapPriorityQueue<MapEntry<String, double>>(
    (a, b) => a.value.compareTo(b.value),
  );
  for (final entry in best.entries) {
    pq.add(entry);
    if (pq.length > limit) pq.removeFirst();
  }
  final result = pq.toList()..sort((a, b) => b.value.compareTo(a.value));
  return Map.fromEntries(result);
}

/// Best estimated 1RM per exercise (Epley: weight·(1 + reps/30)), ranked desc
/// and capped to [limit]. Reps are capped at [repCap] (default 12) so a
/// high-rep set can't inflate the estimate into a fantasy number — this is the
/// honest strength signal that replaces the misleading raw-max-weight PR list
/// (where bench 100×1 and squat 100×10 read identically).
Map<String, double> topE1rmByExercise(
  List<WorkoutSession> sessions, {
  int limit = 8,
  int repCap = 12,
}) {
  final Map<String, double> best = {};
  for (final s in sessions) {
    for (final ex in s.exercises) {
      for (final WorkoutSet set in ex.sets) {
        if (!set.isCompleted || set.weight <= 0 || set.reps <= 0) continue;
        final reps = set.reps > repCap ? repCap : set.reps;
        final e1rm = reps <= 1 ? set.weight : set.weight * (1.0 + reps / 30.0);
        final key = ex.exercise.name;
        if (!best.containsKey(key) || e1rm > best[key]!) best[key] = e1rm;
      }
    }
  }

  final pq = HeapPriorityQueue<MapEntry<String, double>>(
    (a, b) => a.value.compareTo(b.value),
  );
  for (final entry in best.entries) {
    pq.add(entry);
    if (pq.length > limit) pq.removeFirst();
  }
  final result = pq.toList()..sort((a, b) => b.value.compareTo(a.value));
  return Map.fromEntries(result);
}

double bestSessionVolume(List<WorkoutSession> sessions) {
  double best = 0;
  for (final s in sessions) {
    if (s.totalVolume > best) best = s.totalVolume;
  }
  return best;
}

double lastNWeeksVolume(Map<String, double> weeklyVolume, int n) {
  final values = weeklyVolume.values.toList();
  if (values.isEmpty) return 0;
  final start = values.length - n;
  final slice = values.sublist(start < 0 ? 0 : start);
  return slice.fold<double>(0, (sum, v) => sum + v);
}

double prevNWeeksVolume(Map<String, double> weeklyVolume, int n) {
  final values = weeklyVolume.values.toList();
  if (values.length <= n) return 0;
  final endPrev = values.length - n;
  final startPrev = endPrev - n;
  if (startPrev < 0) return 0;
  final slice = values.sublist(startPrev, endPrev);
  return slice.fold<double>(0, (sum, v) => sum + v);
}

/// Counts how many of the most recent [windowWeeks] (anchored on [now]) had at
/// least [weeklyGoal] workouts. [countsByWeek] is keyed by ISO week key
/// (`YYYY-Www`). Used for the goal-oriented Progress hero metric.
int goalHitWeeks({
  required Map<String, int> countsByWeek,
  required int weeklyGoal,
  required int windowWeeks,
  required DateTime now,
}) {
  if (weeklyGoal <= 0 || windowWeeks <= 0) return 0;
  final anchorWeek = isoWeekNumber(now);
  final anchorStart = startOfIsoWeek(now.year, anchorWeek);
  var hits = 0;
  for (var back = 0; back < windowWeeks; back++) {
    final weekStart = anchorStart.subtract(Duration(days: 7 * back));
    final week = isoWeekNumber(weekStart);
    final key = '${weekStart.year}-W${week.toString().padLeft(2, '0')}';
    if ((countsByWeek[key] ?? 0) >= weeklyGoal) hits++;
  }
  return hits;
}

int isoWeekNumber(DateTime date) {
  final thursday = date.add(Duration(days: 3 - ((date.weekday + 6) % 7)));
  final firstThursday = DateTime(thursday.year, 1, 4);
  final firstWeekStart = firstThursday.subtract(
    Duration(days: (firstThursday.weekday + 6) % 7),
  );
  return 1 + (thursday.difference(firstWeekStart).inDays ~/ 7);
}

DateTime startOfIsoWeek(int year, int week) {
  final jan4 = DateTime(year, 1, 4);
  final firstWeekStart = jan4.subtract(Duration(days: (jan4.weekday + 6) % 7));
  return firstWeekStart.add(Duration(days: (week - 1) * 7));
}
