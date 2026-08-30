import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../utils/weight_unit.dart';
import 'charts/trend_line_chart.dart';
import 'weight_axis.dart';

/// The Weight trend chart (MacroFactor V5 — the clean reference look):
///   • TREND is the hero — a smooth primary-accent curve with hollow ring
///     markers and NO area fill, so the line reads crisp on the canvas.
///   • SCALE is context — the raw daily weigh-ins drawn as one thin, muted
///     flowing line (no markers) the trend smooths through.
///
/// The hero numerals, range selector, and legend live OUTSIDE this widget (in
/// the screen's [ChartStatHeader], [ChartRangeBar], and [ChartLegendCard]); this
/// is a thin weight-flavoured wrapper over the shared [TrendLineChart].
class WeightTrendChart extends StatelessWidget {
  const WeightTrendChart({
    super.key,
    required this.baseDate,
    required this.scaleSpots,
    required this.trendSpots,
    required this.showScale,
    required this.showTrend,
    required this.minY,
    required this.maxY,
    required this.unit,
    this.rangeDays = 30,
    this.fitYAxis = false,
  });

  final DateTime baseDate;

  /// Spots already in the DISPLAY unit (kg or lb), x = days from [baseDate].
  final List<FlSpot> scaleSpots;
  final List<FlSpot> trendSpots;
  final bool showScale;
  final bool showTrend;

  /// The selected time range in days (0 == All). Drives the x-axis label format.
  final int rangeDays;

  /// Display-unit y bounds.
  final double minY;
  final double maxY;

  final WeightUnit unit;

  /// When true the y-axis fits tightly to the data (the header's resize toggle).
  final bool fitYAxis;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final axis = computeWeightAxis(minY, maxY, tight: fitYAxis);

    return TrendLineChart(
      baseDate: baseDate,
      axisMin: axis.min,
      axisMax: axis.max,
      axisInterval: axis.interval,
      formatAxis: axis.format,
      isAxisTick: axis.isTick,
      rangeDays: rangeDays,
      valueSuffix: unit.suffix,
      semanticsLabel: 'Weight chart over $rangeDays days.',
      series: [
        // SCALE first => paints BEHIND the trend: one thin, muted flowing line.
        if (showScale)
          TrendSeries(
            spots: scaleSpots,
            color: colors.primary.withValues(alpha: 0.55),
            width: 1.6,
            marker: TrendMarker.none,
          ),
        // TREND on top => the hero line with hollow ring markers, no fill.
        if (showTrend)
          TrendSeries(
            spots: trendSpots,
            color: colors.primary,
            width: 2.5,
            marker: TrendMarker.autoRing,
          ),
      ],
    );
  }
}
