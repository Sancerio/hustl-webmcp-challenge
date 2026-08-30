import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_shadows.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../domain/models/daily_health_summary.dart';
import 'health_info_card.dart';

/// Describes the user's current weight goal so the chart can apply
/// goal-aware colouring (gaining is positive when the goal is gain).
enum WeightGoal { lose, gain, maintain }

class WeightTrendCard extends StatelessWidget {
  const WeightTrendCard({
    super.key,
    required this.summaries,
    this.weightGoal = WeightGoal.lose,
  });

  final List<DailyHealthSummary> summaries;

  /// The user's current goal — used to decide whether a weight gain is
  /// positive (emerald) or unwanted (amber).  Never uses error/red for
  /// weight change per spec §1 principle 5 and §2.1.
  final WeightGoal weightGoal;

  @override
  Widget build(BuildContext context) {
    final weightSummaries = summaries
        .where((summary) => summary.latestWeightKg != null)
        .toList();

    if (weightSummaries.length < 2) {
      return const HealthInfoCard(
        title: 'Weight trend',
        message: 'We need at least two weight samples to chart a trend.',
      );
    }

    final baseDate = weightSummaries.first.date;
    final spots = weightSummaries.map((summary) {
      final days = summary.date.difference(baseDate).inDays.toDouble();
      return FlSpot(days, summary.latestWeightKg!);
    }).toList();

    final minX = spots.first.x;
    final maxX = spots.last.x;
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);

    final firstWeight = weightSummaries.first.latestWeightKg!;
    final latestWeight = weightSummaries.last.latestWeightKg!;
    final weightDelta = latestWeight - firstWeight;

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final lineColor = colorScheme.primary;
    final yPadding = _calculateYPadding(minY, maxY);
    final yInterval = _calculateYInterval(minY, maxY);
    final chartMinY = (minY - yPadding).clamp(0.0, double.infinity);
    final chartMaxY = maxY + yPadding;
    final weightDeltaLabel = weightDelta.abs().toStringAsFixed(1);
    final weightDeltaPrefix = weightDelta >= 0 ? '+' : '−';
    final formattedDelta = weightDelta == 0
        ? 'No change'
        : '$weightDeltaPrefix$weightDeltaLabel kg';
    // Goal-aware colouring: never use error/red for weight change.
    // Gaining is positive (emerald) when the goal is gain; unwanted gain is
    // amber. Losing is positive (emerald) when the goal is lose; unwanted loss
    // is amber.  Zero change is always neutral (onSurfaceVariant).
    final Color deltaColor;
    if (weightDelta == 0) {
      deltaColor = colorScheme.onSurfaceVariant;
    } else {
      final bool isGain = weightDelta > 0;
      final bool isGoalAligned = switch (weightGoal) {
        WeightGoal.gain => isGain,
        WeightGoal.lose => !isGain,
        WeightGoal.maintain => false, // any movement is mildly unwanted
      };
      deltaColor = isGoalAligned
          ? AppColors.accentEmeraldGreen
          : AppColors.accentWarningAmber;
    }
    final tooltipTitleStyle =
        textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ) ??
        TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface);
    final tooltipValueStyle =
        textTheme.bodyMedium?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w700,
        ) ??
        TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w700);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [AppShadows.subtle(context)],
      ),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Weight trend',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${weightSummaries.length} samples',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x1),
            Row(
              children: [
                Icon(
                  weightDelta > 0
                      ? Icons.north_east
                      : (weightDelta < 0 ? Icons.south_east : Icons.remove),
                  size: 18,
                  color: deltaColor,
                ),
                const SizedBox(width: AppSpacing.x1),
                Text(
                  formattedDelta,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: deltaColor,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'since ${DateFormat('MMM d').format(baseDate)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x2),
            RepaintBoundary(
              child: Semantics(
                label:
                    'Weight trend chart: ${spots.length} data points. '
                    'Start ${firstWeight.toStringAsFixed(1)} kg, '
                    'current ${latestWeight.toStringAsFixed(1)} kg, '
                    'change $formattedDelta.',
                excludeSemantics: true,
                child: SizedBox(
                  height: 220,
                  child: LineChart(
                    LineChartData(
                      lineTouchData: LineTouchData(
                        handleBuiltInTouches: true,
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => colorScheme.surface,
                          tooltipPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          tooltipBorderRadius: BorderRadius.circular(12),
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots.map((spot) {
                              final date = baseDate.add(
                                Duration(days: spot.x.toInt()),
                              );
                              return LineTooltipItem(
                                '${DateFormat('EEE, MMM d').format(date)}\n',
                                tooltipTitleStyle,
                                children: [
                                  TextSpan(
                                    text: '${spot.y.toStringAsFixed(1)} kg',
                                    style: tooltipValueStyle,
                                  ),
                                ],
                              );
                            }).toList();
                          },
                        ),
                      ),
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        horizontalInterval: yInterval,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.4,
                            ),
                            strokeWidth: 1,
                            dashArray: const [4, 4],
                          );
                        },
                      ),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            getTitlesWidget: (value, meta) {
                              final date = baseDate.add(
                                Duration(days: value.toInt()),
                              );
                              if (value == minX || value == maxX) {
                                return Text(
                                  DateFormat('MMM d').format(date),
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                );
                              }
                              final mid = (minX + maxX) / 2;
                              if ((value - mid).abs() < 0.1) {
                                return Text(
                                  DateFormat('MMM d').format(date),
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 48,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                '${value.toStringAsFixed(1)} kg',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              );
                            },
                          ),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      minX: minX,
                      maxX: maxX,
                      minY: chartMinY,
                      maxY: chartMaxY,
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: lineColor,
                          barWidth: 2,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, bar, index) {
                              return FlDotCirclePainter(
                                radius: 4,
                                color: colorScheme.surface,
                                strokeWidth: 2,
                                strokeColor: lineColor,
                              );
                            },
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            color: lineColor.withValues(alpha: 0.08),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _calculateYPadding(double minY, double maxY) {
    final range = (maxY - minY).abs();
    if (range == 0) {
      return minY == 0 ? 1 : minY * 0.05;
    }
    if (range < 0.5) {
      return 0.3;
    }
    if (range < 1.5) {
      return range * 0.25;
    }
    return range * 0.15;
  }

  double _calculateYInterval(double minY, double maxY) {
    final range = (maxY - minY).abs();
    if (range <= 1) {
      return 0.2;
    }
    if (range <= 2.5) {
      return 0.5;
    }
    final interval = range / 4;
    if (interval < 0.5) {
      return 0.5;
    }
    if (interval > 5) {
      return 5;
    }
    return interval;
  }
}
