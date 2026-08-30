import 'package:fl_chart/fl_chart.dart';

/// Point granularity for a MacroFactor-style trend chart: the "D / W / M"
/// dropdown next to the range selector aggregates the plotted points into daily,
/// weekly, or monthly buckets so long spans stay legible (sparse markers) while
/// short spans keep every weigh-in.
enum ChartGranularity { day, week, month }

extension ChartGranularityX on ChartGranularity {
  /// Single-letter label shown in the dropdown pill ('D' / 'W' / 'M').
  String get shortLabel => switch (this) {
    ChartGranularity.day => 'D',
    ChartGranularity.week => 'W',
    ChartGranularity.month => 'M',
  };

  /// Full label shown in the dropdown menu.
  String get menuLabel => switch (this) {
    ChartGranularity.day => 'Daily',
    ChartGranularity.week => 'Weekly',
    ChartGranularity.month => 'Monthly',
  };

  /// Bucket width in days (months approximated at 30 — the x-axis is days from a
  /// base date, so calendar months aren't needed for visual bucketing).
  int get bucketDays => switch (this) {
    ChartGranularity.day => 1,
    ChartGranularity.week => 7,
    ChartGranularity.month => 30,
  };
}

/// The granularities that make sense for a [rangeDays] window: never offer a
/// bucket so coarse the chart collapses to a point or two. `0` == All.
List<ChartGranularity> availableGranularities(int rangeDays) {
  switch (rangeDays) {
    case 7:
      return const [ChartGranularity.day];
    case 30:
    case 90:
      return const [ChartGranularity.day, ChartGranularity.week];
    case 180:
      return const [ChartGranularity.week, ChartGranularity.month];
    default: // 365 + All
      return const [ChartGranularity.week, ChartGranularity.month];
  }
}

/// The sensible default granularity for a range (the finest one available).
ChartGranularity defaultGranularity(int rangeDays) =>
    availableGranularities(rangeDays).first;

/// Aggregates [spots] (x = days from a base date, y = value) into [granularity]
/// buckets, averaging x and y within each bucket. Daily granularity (or fewer
/// than three points) returns the input untouched so we never smear sparse data.
List<FlSpot> aggregateSpots(List<FlSpot> spots, ChartGranularity granularity) {
  final width = granularity.bucketDays;
  if (width <= 1 || spots.length < 3) return spots;

  final buckets = <int, List<FlSpot>>{};
  for (final spot in spots) {
    final bucket = (spot.x ~/ width);
    (buckets[bucket] ??= <FlSpot>[]).add(spot);
  }

  final keys = buckets.keys.toList()..sort();
  return [
    for (final key in keys)
      () {
        final group = buckets[key]!;
        final sumX = group.fold<double>(0, (a, s) => a + s.x);
        final sumY = group.fold<double>(0, (a, s) => a + s.y);
        return FlSpot(sumX / group.length, sumY / group.length);
      }(),
  ];
}
