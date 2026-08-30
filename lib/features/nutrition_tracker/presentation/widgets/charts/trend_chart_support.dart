import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../nutrition_chart_style.dart';

/// How a series renders its point markers.
enum TrendMarker {
  /// No markers — a bare line (raw scale weigh-ins, intake context line).
  none,

  /// Hollow ring markers, shown only while the points are sparse (≤16) so a
  /// dense series stays a clean curve.
  autoRing,
}

/// One plotted series for the shared `TrendLineChart`.
class TrendSeries {
  const TrendSeries({
    required this.spots,
    required this.color,
    this.width = 2.5,
    this.curved = true,
    this.marker = TrendMarker.none,
    this.fill = false,
    this.fillTopAlpha = 0.22,
  });

  final List<FlSpot> spots;
  final Color color;
  final double width;
  final bool curved;
  final TrendMarker marker;

  /// Draw a soft gradient area beneath the line (the expenditure "flux" fill).
  final bool fill;
  final double fillTopAlpha;
}

/// Builds the fl_chart bar for [s]: a smooth line with optional hollow ring
/// markers (background fill + accent ring) and an optional soft area fill.
LineChartBarData buildTrendBar(TrendSeries s, Color markerRing) {
  final showMarkers =
      s.marker == TrendMarker.autoRing && s.spots.length <= 16;
  return LineChartBarData(
    spots: s.spots,
    isCurved: s.curved,
    curveSmoothness: 0.35,
    preventCurveOverShooting: true,
    color: s.color,
    barWidth: s.width,
    isStrokeCapRound: true,
    dotData: FlDotData(
      show: showMarkers,
      getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
        radius: 4,
        // Background fill + accent ring => a hollow open circle.
        color: markerRing,
        strokeWidth: 2,
        strokeColor: s.color,
      ),
    ),
    belowBarData: BarAreaData(
      show: s.fill,
      gradient: s.fill
          ? NutritionChartStyle.areaGradient(
              s.color,
              topAlpha: s.fillTopAlpha,
              bottomAlpha: 0.0,
            )
          : null,
    ),
  );
}
