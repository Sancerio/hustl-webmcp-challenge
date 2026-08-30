import 'package:intl/intl.dart';

import '../../utils/weight_unit.dart';
import 'chart_changes_card.dart';

/// A single (date, value) sample of a trend series, value in stored units.
typedef TrendSample = ({DateTime date, double value});

/// Builds a short-window change row (e.g. "3-day") from a daily [series],
/// comparing the latest value to the value [days] ago. Returns null when the
/// window doesn't hold at least two samples.
ChartChangeRow? buildChangeRow({
  required List<TrendSample> series,
  required int days,
  required String Function(double delta) formatDelta,
  required double Function(double value) toDisplay,
  double deadband = 0,
}) {
  if (series.length < 2) return null;
  final last = series.last;
  final cutoff = last.date.subtract(Duration(days: days));
  final window = [
    for (final s in series)
      if (!s.date.isBefore(cutoff)) s,
  ];
  if (window.length < 2) return null;
  final delta = last.value - window.first.value;
  return ChartChangeRow(
    label: '$days-day',
    sparkline: [for (final s in window) toDisplay(s.value)],
    valueText: formatDelta(delta),
    direction: directionOf(delta, deadband: deadband),
  );
}

/// Builds the standard 3-day / 7-day change rows for a stored-kg [series] using
/// the user's [unit] for display + formatting.
List<ChartChangeRow> weightChangeRows({
  required List<TrendSample> series,
  required WeightUnit unit,
}) => [
  for (final days in const [3, 7])
    buildChangeRow(
      series: series,
      days: days,
      formatDelta: (d) => unit.formatDelta(d),
      toDisplay: unit.toDisplay,
      deadband: 0.05,
    ),
].whereType<ChartChangeRow>().toList();

/// Builds the standard 3-day / 7-day change rows for a kcal [series] (e.g.
/// expenditure), formatting signed whole-kcal deltas.
List<ChartChangeRow> kcalChangeRows({required List<TrendSample> series}) => [
  for (final days in const [3, 7])
    buildChangeRow(
      series: series,
      days: days,
      formatDelta: (d) => '${d >= 0 ? '+' : '−'}${d.abs().round()} kcal',
      toDisplay: (v) => v,
      deadband: 5,
    ),
].whereType<ChartChangeRow>().toList();

/// "Apr 6 – Apr 12, 2025" style window label from the first/last plotted dates.
String formatDateRange(DateTime start, DateTime end) {
  final startFmt = DateFormat('MMM d');
  final endFmt = DateFormat('MMM d, yyyy');
  return '${startFmt.format(start)} – ${endFmt.format(end)}';
}
