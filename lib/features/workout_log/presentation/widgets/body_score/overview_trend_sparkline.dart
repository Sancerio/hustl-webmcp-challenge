import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_colors.dart';

/// A compact, axis-free trend line of daily training load over the period,
/// shown on the Body Score overview card so users can see whether their effort
/// is trending up. Renders nothing when there is too little data to be useful.
class OverviewTrendSparkline extends StatelessWidget {
  const OverviewTrendSparkline({
    super.key,
    required this.dailyTotals,
    this.height = 40,
  });

  /// Total hard sets per day, in chronological order.
  final List<double> dailyTotals;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (dailyTotals.length < 3) {
      return const SizedBox.shrink();
    }
    final maxValue = dailyTotals.reduce((a, b) => a > b ? a : b);
    final spots = <FlSpot>[
      for (var i = 0; i < dailyTotals.length; i++)
        FlSpot(i.toDouble(), dailyTotals[i]),
    ];

    return Semantics(
      label: 'Training load trend over the selected period',
      child: RepaintBoundary(
        child: SizedBox(
          height: height,
          child: LineChart(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOutCubic,
            LineChartData(
              minX: 0,
              maxX: (dailyTotals.length - 1).toDouble(),
              minY: 0,
              maxY: maxValue <= 0 ? 1 : maxValue * 1.15,
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  preventCurveOverShooting: true,
                  // Wave F §11: flat accent line, no gradient.
                  color: AppColors.accentElectricBlue,
                  barWidth: 2.0,
                  dotData: const FlDotData(show: false),
                  // Wave F §11.2: flat subtle area fill ≤12% alpha.
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppColors.accentElectricBlue.withValues(alpha: 0.10),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
