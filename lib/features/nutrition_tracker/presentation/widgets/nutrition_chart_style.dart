import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class NutritionChartStyle {
  const NutritionChartStyle._();

  // Wave F (MacroFactor pivot): flat, subtle area fills (≤12% alpha) — no glow.
  static LinearGradient areaGradient(
    Color color, {
    double topAlpha = 0.12,
    double bottomAlpha = 0.02,
  }) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      color.withValues(alpha: topAlpha),
      color.withValues(alpha: bottomAlpha),
    ],
  );

  // Hairline grid: 1px, outlineVariant at ~40%. Target/goal lines pass dashed.
  static FlLine gridLine(ThemeData theme, {bool dashed = false}) => FlLine(
    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
    strokeWidth: 1,
    dashArray: dashed ? const [4, 4] : null,
  );

  static TextStyle axisLabelStyle(ThemeData theme) =>
      theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11);
}
