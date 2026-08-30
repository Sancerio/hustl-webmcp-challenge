import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/core/utils/number_format_util.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/workout_progress_utils.dart';

class SimpleHorizontalBars extends StatelessWidget {
  final Map<String, double> data;
  final String Function(double) formatValue;

  const SimpleHorizontalBars({
    super.key,
    required this.data,
    required this.formatValue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxValue = data.values.fold<double>(0, (p, c) => c > p ? c : p);
    final keys = data.keys.toList();
    return Column(
      children: [
        for (final key in keys)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Wave G §12.1: aligned label/value row — 15/w500 label,
                // 15/w600 tabular value.
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        key,
                        style: theme.textTheme.bodyLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatValue(data[key]!),
                      style: theme.textTheme.labelLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // §12.4: slim bar, square-ish 2px radius.
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.4,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: maxValue == 0
                          ? 0.0
                          : (data[key]! / maxValue).clamp(0.0, 1.0).toDouble(),
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          // §12.4: volume accent = blue.
                          color: AppColors.accentElectricBlue,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class LineChartTimeSeries extends StatelessWidget {
  final Map<String, double> data; // keys depend on TimeGroup
  final TimeGroup group;
  final Set<int>? highlightIndices; // optional indices to highlight with dots
  final String yUnit;
  const LineChartTimeSeries({
    super.key,
    required this.data,
    required this.group,
    this.highlightIndices,
    this.yUnit = '',
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox.shrink();
    }
    try {
      final theme = Theme.of(context);
      final entries = data.entries.toList();
      final spots = <FlSpot>[];
      final values = <double>[];
      for (int i = 0; i < entries.length; i++) {
        final value = entries[i].value;
        spots.add(FlSpot(i.toDouble(), value));
        values.add(value);
      }
      final rawMaxY = values.reduce(math.max);
      final rawMinY = values.reduce(math.min);
      final axis = _computeAxis(rawMinY, rawMaxY);
      final showYear = _shouldShowYear(entries);

      return LineChart(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
        LineChartData(
          minX: 0.0,
          maxX: spots.isEmpty ? 0.0 : spots.last.x,
          minY: axis.minY,
          maxY: axis.maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            // §12.4: at most a few faint hairline gridlines.
            horizontalInterval: axis.interval <= 0
                ? null
                : (axis.maxY - axis.minY) / 2,
            getDrawingHorizontalLine: (value) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              strokeWidth: 1.0,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44.0,
                interval: axis.interval,
                getTitlesWidget: (value, meta) {
                  if (axis.maxY > 0 && (value - axis.maxY).abs() < 0.0001) {
                    return const SizedBox.shrink();
                  }
                  final base = value == 0 ? '0' : _formatCompact(value);
                  final unit = yUnit.isEmpty ? '' : ' $yUnit';
                  return Text(
                    '$base$unit',
                    style: Theme.of(context).textTheme.labelSmall,
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1.0,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= entries.length) {
                    return const SizedBox.shrink();
                  }
                  if (index != 0 &&
                      index != entries.length - 1 &&
                      index != (entries.length / 2).floor()) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    fitInside: SideTitleFitInsideData.fromTitleMeta(
                      meta,
                      distanceFromEdge: 4,
                    ),
                    child: Text(
                      _formatLabel(entries[index].key, showYear),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) => touchedSpots.map((ts) {
                final unit = yUnit.isEmpty ? '' : ' $yUnit';
                final label = _formatLabel(entries[ts.spotIndex].key, showYear);
                final val = _formatCompact(ts.y);
                return LineTooltipItem(
                  '$label\n$val$unit',
                  Theme.of(context).textTheme.bodySmall!,
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              preventCurveOverShooting: true,
              // Wave F §11: flat accent color, no gradient on chart lines.
              color: AppColors.accentElectricBlue,
              barWidth: 2.0,
              // Wave F §11.1: no glow shadow.
              // Wave F §11: latest point only — small solid dot, no pulse.
              dotData: FlDotData(
                show: spots.isNotEmpty,
                getDotPainter: (spot, percent, bar, index) {
                  final isLatest = index == spots.length - 1;
                  final isExtraHighlight =
                      highlightIndices?.contains(index) ?? false;
                  if (!isLatest && !isExtraHighlight) {
                    return FlDotCirclePainter(
                      radius: 0,
                      color: Colors.transparent,
                      strokeWidth: 0,
                      strokeColor: Colors.transparent,
                    );
                  }
                  // Small solid dot — no stroke for pulse appearance.
                  return FlDotCirclePainter(
                    radius: 3.0,
                    color: AppColors.accentElectricBlue,
                    strokeWidth: 0,
                    strokeColor: Colors.transparent,
                  );
                },
              ),
              // Wave F §11.2: flat subtle area fill ≤12% alpha.
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.accentElectricBlue.withValues(alpha: 0.10),
              ),
            ),
          ],
        ),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to render chart: $e');
        debugPrintStack(stackTrace: st);
      }
      return const SizedBox.shrink();
    }
  }

  bool _shouldShowYear(List<MapEntry<String, double>> entries) {
    if (entries.isEmpty) return false;
    final first = _parseKey(entries.first.key);
    final last = _parseKey(entries.last.key);
    if (first == null || last == null) return false;
    return first.year != last.year;
  }

  DateTime? _parseKey(String key) {
    try {
      switch (group) {
        case TimeGroup.day:
          return DateTime.parse(key);
        case TimeGroup.week:
          final parts = key.split('-W');
          final year = int.parse(parts[0]);
          final week = int.parse(parts[1]);
          return startOfIsoWeek(year, week);
        case TimeGroup.month:
          final parts = key.split('-');
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          return DateTime(year, month);
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to parse date: $e');
        debugPrintStack(stackTrace: st);
      }
    }
    return null;
  }

  String _formatLabel(String key, bool showYear) {
    final date = _parseKey(key);
    if (date != null) {
      switch (group) {
        case TimeGroup.day:
        case TimeGroup.week:
          return DateFormat(showYear ? 'MMM yyyy' : 'dd MMMM').format(date);
        case TimeGroup.month:
          return DateFormat.yMMM().format(date);
      }
    }
    return 'N/A';
  }

  String _formatCompact(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}m';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return NumberFormatUtil.formatDouble(value, decimalDigits: 0);
  }

  _Axis _computeAxis(double rawMin, double rawMax) {
    double minY = math.min(0, rawMin);
    double maxY = math.max(0, rawMax);
    if (minY == maxY) {
      if (maxY == 0) {
        minY = -1;
        maxY = 1;
      } else {
        final padding = math.max(1.0, maxY.abs() * 0.1);
        minY = math.min(minY, maxY - padding);
        maxY = math.max(maxY, maxY + padding);
        minY = math.min(minY, 0);
        maxY = math.max(maxY, 0);
      }
    }
    final span = maxY - minY;
    if (span <= 0) {
      return const _Axis(minY: -1, maxY: 1, interval: 0.5);
    }
    final double magnitude = math
        .pow(10, (math.log(span) / math.ln10).floor())
        .toDouble();
    final double normalized = span / magnitude;
    double niceNormalized;
    if (normalized <= 1) {
      niceNormalized = 1;
    } else if (normalized <= 2) {
      niceNormalized = 2;
    } else if (normalized <= 5) {
      niceNormalized = 5;
    } else {
      niceNormalized = 10;
    }
    final double niceSpan = niceNormalized * magnitude;
    final double interval = niceSpan / 4.0;
    final double niceMax = interval == 0
        ? maxY
        : (maxY / interval).ceilToDouble() * interval;
    final double niceMin = interval == 0
        ? minY
        : (minY / interval).floorToDouble() * interval;
    return _Axis(minY: niceMin, maxY: niceMax, interval: interval);
  }
}

class _Axis {
  final double minY;
  final double maxY;
  final double interval;
  const _Axis({required this.minY, required this.maxY, required this.interval});
}
