import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hustl_app/app/theme/app_radius.dart';

import '../nutrition_chart_style.dart';
import 'trend_chart_support.dart';

// Re-export the series model + bar builder so callers only import this file.
export 'trend_chart_support.dart' show TrendMarker, TrendSeries;

/// The shared MacroFactor-style trend line surface used by the weight and
/// expenditure screens: hollow ring markers, dashed hairline gridlines, a
/// right-rail y-axis, and a date x-axis — rendered directly on the page canvas
/// (no card) so markers punch through to the background.
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    super.key,
    required this.baseDate,
    required this.series,
    required this.axisMin,
    required this.axisMax,
    required this.axisInterval,
    required this.formatAxis,
    required this.isAxisTick,
    required this.rangeDays,
    required this.valueSuffix,
    this.valueDecimals = 1,
    this.height = 240,
    this.semanticsLabel,
  });

  final DateTime baseDate;
  final List<TrendSeries> series;

  final double axisMin;
  final double axisMax;
  final double axisInterval;
  final String Function(double) formatAxis;
  final bool Function(double) isAxisTick;

  final int rangeDays;
  final String valueSuffix;
  final int valueDecimals;
  final double height;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final markerRing = theme.scaffoldBackgroundColor;
    final hasData = series.any((s) => s.spots.isNotEmpty);

    return RepaintBoundary(
      child: Semantics(
        label: semanticsLabel,
        excludeSemantics: semanticsLabel != null,
        child: SizedBox(
          height: height,
          child: !hasData
              ? _empty(theme)
              : _chart(theme, colors, markerRing),
        ),
      ),
    );
  }

  Widget _chart(ThemeData theme, ColorScheme colors, Color markerRing) {
    final spotsMaxX = series
        .where((s) => s.spots.isNotEmpty)
        .map((s) => s.spots.last.x)
        .fold<double>(1, (a, b) => a > b ? a : b);

    return LineChart(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
      LineChartData(
        minX: 0,
        maxX: spotsMaxX,
        minY: axisMin,
        maxY: axisMax,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: axisInterval,
          getDrawingHorizontalLine: (value) =>
              NutritionChartStyle.gridLine(theme, dashed: true),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: axisInterval,
              getTitlesWidget: (value, meta) {
                if (!isAxisTick(value)) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    formatAxis(value),
                    style: NutritionChartStyle.axisLabelStyle(theme),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: _bottomInterval(spotsMaxX),
              getTitlesWidget: (value, meta) {
                if (value < 0 || value > spotsMaxX + 1e-6) {
                  return const SizedBox.shrink();
                }
                final date = baseDate.add(Duration(days: value.round()));
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _bottomLabel(date),
                    style: NutritionChartStyle.axisLabelStyle(theme),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          for (final s in series) buildTrendBar(s, markerRing),
        ],
        lineTouchData: _touch(theme, colors, markerRing),
      ),
    );
  }

  LineTouchData _touch(ThemeData theme, ColorScheme colors, Color markerRing) {
    return LineTouchData(
      handleBuiltInTouches: true,
      getTouchedSpotIndicator: (barData, indexes) {
        return indexes.map((index) {
          return TouchedSpotIndicatorData(
            FlLine(
              color: colors.primary.withValues(alpha: 0.45),
              strokeWidth: 1.5,
              dashArray: const [4, 4],
            ),
            FlDotData(
              getDotPainter: (spot, percent, bar, i) => FlDotCirclePainter(
                radius: 4,
                color: markerRing,
                strokeWidth: 2.5,
                strokeColor: barData.color ?? colors.primary,
              ),
            ),
          );
        }).toList();
      },
      touchTooltipData: LineTouchTooltipData(
        tooltipBorderRadius: BorderRadius.circular(AppRadius.control),
        tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        maxContentWidth: 160,
        getTooltipColor: (_) => colors.surfaceContainerHighest,
        getTooltipItems: (touchedSpots) {
          if (touchedSpots.isEmpty) return const [];
          final date = baseDate.add(
            Duration(days: touchedSpots.first.x.round()),
          );
          final dateFmt = DateFormat('EEE, MMM d');
          return [
            for (var i = 0; i < touchedSpots.length; i++)
              LineTooltipItem(
                i == 0
                    ? '${dateFmt.format(date)}\n${touchedSpots[i].y.toStringAsFixed(valueDecimals)} $valueSuffix'
                    : '${touchedSpots[i].y.toStringAsFixed(valueDecimals)} $valueSuffix',
                (i == 0 ? theme.textTheme.labelMedium : theme.textTheme.bodySmall)
                        ?.copyWith(
                          color: i == 0
                              ? colors.onSurface
                              : colors.onSurfaceVariant,
                        ) ??
                    TextStyle(color: colors.onSurface),
              ),
          ];
        },
      ),
    );
  }

  /// 1-week windows label every day; longer spans show ~4 evenly-spaced ticks.
  double _bottomInterval(double spotsMaxX) {
    final isWeek = rangeDays == 7 || (rangeDays != 0 && rangeDays <= 7);
    if (isWeek) return 1;
    return (spotsMaxX / 4).clamp(1, double.infinity);
  }

  String _bottomLabel(DateTime date) {
    final isWeek = rangeDays == 7 || (rangeDays != 0 && rangeDays <= 7);
    if (isWeek) return DateFormat('E').format(date);
    return DateFormat('MMM d').format(date);
  }

  Widget _empty(ThemeData theme) => Center(
    child: Text(
      'Not enough data to chart yet',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
