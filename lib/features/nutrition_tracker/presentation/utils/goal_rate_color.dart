import 'package:flutter/widgets.dart';
import 'package:hustl_app/app/theme/app_colors.dart';

/// Adherence-NEUTRAL, goal-aware colour for a signed rate/delta.
///
/// Movement TOWARD the goal reads emerald; drift away reads amber — NEVER red,
/// no shame. Shared by the Weight rate tile + delta, the Strategy deficit line,
/// and the Insights under/over row so over/under semantics are identical across
/// all three nutrition screens.
///
/// [value] is the signed amount (e.g. kg/week, or a kcal deficit/surplus).
/// [goalType] is 'lose' | 'gain' | 'maintain' (anything else is treated like
/// 'lose'). [neutral] is returned when [value] is null (caller passes e.g.
/// `colorScheme.onSurfaceVariant`). [maintainTolerance] is the dead-band within
/// which 'maintain' still counts as on-target (default 0.1, tuned for kg/week —
/// pass a unit-appropriate value for calories etc.).
Color goalRateColor({
  required String? goalType,
  required double? value,
  required Color neutral,
  double maintainTolerance = 0.1,
}) {
  if (value == null) return neutral;
  final isGaining = value > 0;
  switch (goalType) {
    case 'gain':
      return isGaining
          ? AppColors.accentEmeraldGreen
          : AppColors.accentWarningAmber;
    case 'maintain':
      return value.abs() < maintainTolerance
          ? AppColors.accentEmeraldGreen
          : AppColors.accentWarningAmber;
    case 'lose':
    default:
      return isGaining
          ? AppColors.accentWarningAmber
          : AppColors.accentEmeraldGreen;
  }
}
