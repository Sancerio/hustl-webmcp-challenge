import '../../../domain/models/workout_session.dart';
import '../../../domain/models/workout_session_stats.dart';
import '../../../domain/utils/working_set_count.dart';

/// One calendar day inside the current training week (Mon–Sun).
class HomeDayTraining {
  const HomeDayTraining({
    required this.date,
    required this.volume,
    required this.sets,
    required this.isToday,
  });

  final DateTime date;

  /// Volume (kg) logged on this day.
  final double volume;

  /// Completed sets logged on this day.
  final int sets;

  final bool isToday;
}

/// Pure aggregation of recent completed sessions for the Train dashboard:
/// the current calendar week (Mon–Sun) day-by-day, quiet targets derived
/// from prior weeks, and a weekly-volume series for the insights trend.
/// Computed off a small in-memory list, so no `compute()` offload is needed.
class HomeWeekStats {
  const HomeWeekStats({
    required this.days,
    required this.weekVolume,
    required this.weekWorkouts,
    required this.weekSets,
    required this.dayVolumeTarget,
    required this.daySetsTarget,
    required this.weekVolumeTarget,
    required this.weeklyVolumes,
  });

  /// Mon..Sun of the current calendar week.
  final List<HomeDayTraining> days;

  /// Total volume (kg) logged this calendar week.
  final double weekVolume;

  /// Completed workouts this calendar week.
  final int weekWorkouts;

  /// Completed sets this calendar week.
  final int weekSets;

  /// Per-training-day volume target derived from prior weeks (0 = unknown).
  final double dayVolumeTarget;

  /// Per-training-day sets target derived from prior weeks (0 = unknown).
  final double daySetsTarget;

  /// Weekly volume target = prior weeks' average volume (0 = unknown).
  final double weekVolumeTarget;

  /// Weekly volume totals, oldest first, ending with the current week.
  /// Weeks without training are honest zeros. At most [maxTrendWeeks] long.
  final List<double> weeklyVolumes;

  static const int maxTrendWeeks = 6;

  /// The widest history this aggregation can DISPLAY, expressed as a lookback
  /// from "now" for callers to fetch/slice against: the in-progress current week
  /// plus the [maxTrendWeeks] of prior weeks the volume trend is derived from.
  /// Anything older is invisible on the dashboard, so bounding the input to this
  /// window keeps the aggregation O(recent) instead of O(all-history).
  ///
  /// Sized as [maxTrendWeeks] + 1 whole weeks (not the bare [maxTrendWeeks]) so
  /// that, wherever "now" falls inside the current week, the lookback still
  /// reaches the Monday of the oldest trend week — the actual floor [from] uses
  /// internally — with a full week of slack. The slack costs only a few extra
  /// in-window sessions (still O(recent)); [from] re-clips to the exact trend
  /// weeks, so the displayed numbers are unaffected.
  static const Duration displayWindow = Duration(days: 7 * (maxTrendWeeks + 1));

  // Date-only keys are built in UTC so day/week arithmetic is exact across
  // DST transitions (a local "+7 days" Duration can land on the wrong day).
  static DateTime _dayOf(DateTime t) {
    final local = t.toLocal();
    return DateTime.utc(local.year, local.month, local.day);
  }

  static DateTime _weekStartOf(DateTime t) {
    final day = _dayOf(t);
    return DateTime.utc(day.year, day.month, day.day - (day.weekday - 1));
  }

  static HomeWeekStats from(
    List<WorkoutSession> completedSessions, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final today = _dayOf(reference);
    final weekStart = _weekStartOf(reference);

    // Bound the work to the window the dashboard actually shows (current week +
    // [maxTrendWeeks] prior). Sessions older than that are invisible here, so
    // dropping them BEFORE the nested set-iteration keeps this O(recent) even if
    // a caller hands us the full history - the displayed numbers are identical
    // because every consumed figure (this week, prior-week targets, the trend)
    // is sourced from inside this window. The floor is taken from the oldest
    // trend week's Monday so a full [maxTrendWeeks] of weeks is always covered.
    final windowFloor = weekStart.subtract(
      const Duration(days: 7 * maxTrendWeeks),
    );

    final dayVolume = <DateTime, double>{};
    final daySets = <DateTime, int>{};
    final weekVolumes = <DateTime, double>{};
    final weekSetsByWeek = <DateTime, int>{};
    final weekActiveDays = <DateTime, Set<DateTime>>{};
    var thisWeekWorkouts = 0;

    for (final session in completedSessions) {
      final week = _weekStartOf(session.startTime);
      // Skip anything older than the trend window before the per-set work.
      if (week.isBefore(windowFloor)) continue;
      final day = _dayOf(session.startTime);
      final volume = session.calculateTotalVolume().toDouble();
      var sets = 0;
      for (final exercise in session.exercises) {
        // Count working sets only — a dropset is one set toward the weekly
        // tally even though each drop still adds volume.
        sets += exercise.completedWorkingSetCount;
      }

      weekVolumes.update(week, (v) => v + volume, ifAbsent: () => volume);
      weekSetsByWeek.update(week, (v) => v + sets, ifAbsent: () => sets);
      (weekActiveDays[week] ??= <DateTime>{}).add(day);

      if (week == weekStart) {
        thisWeekWorkouts++;
        dayVolume.update(day, (v) => v + volume, ifAbsent: () => volume);
        daySets.update(day, (v) => v + sets, ifAbsent: () => sets);
      }
    }

    final days = List<HomeDayTraining>.generate(7, (i) {
      final date = weekStart.add(Duration(days: i));
      return HomeDayTraining(
        date: date,
        volume: dayVolume[date] ?? 0,
        sets: daySets[date] ?? 0,
        isToday: date == today,
      );
    });

    // Quiet targets from prior weeks: average volume/sets per active
    // training day, and the average weekly volume. 0 when there is no
    // history to learn from (callers hide the target ticks).
    final priorWeeks =
        weekVolumes.keys.where((w) => w.isBefore(weekStart)).toList()..sort();
    var dayVolumeTarget = 0.0;
    var daySetsTarget = 0.0;
    var weekVolumeTarget = 0.0;
    if (priorWeeks.isNotEmpty) {
      var totalVolume = 0.0;
      var totalSets = 0;
      var totalActiveDays = 0;
      for (final week in priorWeeks) {
        totalVolume += weekVolumes[week] ?? 0;
        totalSets += weekSetsByWeek[week] ?? 0;
        totalActiveDays += weekActiveDays[week]?.length ?? 0;
      }
      weekVolumeTarget = totalVolume / priorWeeks.length;
      if (totalActiveDays > 0) {
        dayVolumeTarget = totalVolume / totalActiveDays;
        daySetsTarget = totalSets / totalActiveDays;
      }
    }

    // Contiguous weekly series ending at the current week (gaps are zeros).
    final firstWeek = priorWeeks.isEmpty ? weekStart : priorWeeks.first;
    final spanWeeks = (weekStart.difference(firstWeek).inDays ~/ 7) + 1;
    final weeklySeries = List<double>.generate(spanWeeks, (i) {
      final week = firstWeek.add(Duration(days: i * 7));
      return weekVolumes[week] ?? 0;
    });
    final trend = weeklySeries.length > maxTrendWeeks
        ? weeklySeries.sublist(weeklySeries.length - maxTrendWeeks)
        : weeklySeries;

    return HomeWeekStats(
      days: days,
      weekVolume: weekVolumes[weekStart] ?? 0,
      weekWorkouts: thisWeekWorkouts,
      weekSets: weekSetsByWeek[weekStart] ?? 0,
      dayVolumeTarget: dayVolumeTarget,
      daySetsTarget: daySetsTarget,
      weekVolumeTarget: weekVolumeTarget,
      weeklyVolumes: trend,
    );
  }
}
