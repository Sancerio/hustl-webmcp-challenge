import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_colors.dart';

import 'chart_axis.dart';
import 'trend_line_chart.dart';

/// Color of the expenditure (TDEE) series — amber, matching the app's existing
/// "TDEE / reference" hue in the energy-balance chart.
Color get expenditureColor => AppColors.accentWarningAmber;

/// Color of the intake context line — electric blue, the app's intake hue.
Color get intakeColor => AppColors.accentElectricBlue;

/// The Expenditure trend chart: the smoothed expenditure (TDEE) line as the
/// hero — open ring markers over a soft amber "flux" fill — with the daily
/// intake drawn behind it as a thin context line. A kcal-flavoured wrapper over
/// the shared [TrendLineChart].
class ExpenditureTrendChart extends StatelessWidget {
  const ExpenditureTrendChart({
    super.key,
    required this.baseDate,
    required this.expenditureSpots,
    required this.intakeSpots,
    required this.showExpenditure,
    required this.showIntake,
    required this.minY,
    required this.maxY,
    this.rangeDays = 30,
    this.fitYAxis = false,
  });

  final DateTime baseDate;
  final List<FlSpot> expenditureSpots;
  final List<FlSpot> intakeSpots;
  final bool showExpenditure;
  final bool showIntake;
  final double minY;
  final double maxY;
  final int rangeDays;
  final bool fitYAxis;

  @override
  Widget build(BuildContext context) {
    final axis = computeNiceAxis(minY, maxY, tight: fitYAxis);

    return TrendLineChart(
      baseDate: baseDate,
      axisMin: axis.min,
      axisMax: axis.max,
      axisInterval: axis.interval,
      formatAxis: axis.format,
      isAxisTick: axis.isTick,
      rangeDays: rangeDays,
      valueSuffix: 'kcal',
      valueDecimals: 0,
      semanticsLabel: 'Expenditure chart over $rangeDays days.',
      series: [
        // INTAKE first => paints BEHIND: a thin blue context line, no markers.
        if (showIntake)
          TrendSeries(
            spots: intakeSpots,
            color: intakeColor.withValues(alpha: 0.7),
            width: 1.6,
            marker: TrendMarker.none,
          ),
        // EXPENDITURE on top => the hero amber line with rings + soft fill.
        if (showExpenditure)
          TrendSeries(
            spots: expenditureSpots,
            color: expenditureColor,
            width: 2.5,
            marker: TrendMarker.autoRing,
            fill: true,
            fillTopAlpha: 0.22,
          ),
      ],
    );
  }
}
