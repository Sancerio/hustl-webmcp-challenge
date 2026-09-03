import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';

/// The NUTRITION pillar's "aha": the scanned meal measured against the day's
/// target the user set earlier. It shows the running day total against the
/// target, how much this meal added and what's left, a quiet line that the coach
/// factors it in, and a one-tap jump to the existing portion-correction path.
///
/// Purely presentational — it reads numbers passed in and never owns the edit
/// flow; [onAdjustPortion] hands control back to the caller's existing plate
/// editor so there is no second, invented correction surface.
class MealScanTargetCompare extends StatelessWidget {
  const MealScanTargetCompare({
    super.key,
    required this.targetCalories,
    required this.consumedBeforeCalories,
    required this.mealCalories,
    this.onAdjustPortion,
  });

  /// The day's calorie target (must be > 0 for the card to be meaningful).
  final double targetCalories;

  /// Calories already logged today, before this meal is added.
  final double consumedBeforeCalories;

  /// This scanned meal's current calories (updates live as portions change).
  final double mealCalories;

  /// Jumps to the existing portion editor. When null the affordance is hidden
  /// (e.g. a total-only estimate with no per-item breakdown to adjust).
  final VoidCallback? onAdjustPortion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final consumed = consumedBeforeCalories + mealCalories;
    final remaining = targetCalories - consumed;
    final progress = targetCalories <= 0
        ? 0.0
        : (consumed / targetCalories).clamp(0.0, 1.0);
    final overBudget = remaining < 0;
    final added = mealCalories.round();
    final remainingLabel = overBudget
        ? '${(-remaining).round()} kcal over'
        : '${remaining.round()} kcal left — on track';
    final progressColor = overBudget
        ? colors.error
        : AppColors.accentEmeraldGreen;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.x2),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Today',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${consumed.round()} / ${targetCalories.round()} kcal',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x1),
              ClipRRect(
                borderRadius: AppRadius.pillRadius,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: colors.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                ),
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(
                '+$added kcal added · $remainingLabel',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        Row(
          children: [
            Icon(Icons.insights_rounded, size: 14, color: colors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                "Your coach factors this into tomorrow's targets.",
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (onAdjustPortion != null) ...[
          const SizedBox(height: AppSpacing.x1),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAdjustPortion,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Looks off? Adjust portion'),
            ),
          ),
        ],
      ],
    );
  }
}
