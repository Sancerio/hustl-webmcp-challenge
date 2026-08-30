import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';
import 'package:hustl_app/core/widgets/app_section.dart';

import '../../domain/models/nutrition_target_plan.dart';
import '../utils/goal_rate_color.dart';
import 'nutrition_chart_kit.dart';

String goalSentence(NutritionTargetPlan plan) {
  final rate = plan.ratePerWeek;
  switch (plan.goal) {
    case 'lose':
      return rate != null
          ? 'Lose ${rate.abs().toStringAsFixed(2)} kg/week'
          : 'Lose weight';
    case 'gain':
      return rate != null
          ? 'Gain ${rate.abs().toStringAsFixed(2)} kg/week'
          : 'Gain weight';
    default:
      return 'Maintain weight';
  }
}

/// The data-as-hero card: the goal as a sentence, the calorie budget as the big
/// numeral, and a plain deficit/surplus line under it (replacing the opaque
/// "vs TDEE" ratio bar).
class StrategyHeroCard extends StatelessWidget {
  const StrategyHeroCard({
    super.key,
    required this.plan,
    required this.tdeeKcal,
  });

  final NutritionTargetPlan plan;
  final double? tdeeKcal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.cardRadius,
      ),
      padding: const EdgeInsets.all(AppSpacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            goalSentence(plan),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                plan.caloriesTarget.toStringAsFixed(0),
                style: AppTextStyles.nutritionHero(context),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'kcal/day',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x1 + 2),
          DeficitLine(plan: plan, tdeeKcal: tdeeKcal),
          if (plan.needsSetup) ...[
            const SizedBox(height: AppSpacing.x1 + 2),
            Text(
              'Complete setup (height, weight, age, activity) to sharpen target accuracy.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One calm line stating the daily deficit/surplus against estimated upkeep,
/// with a plain weekly-rate caption. Adherence-neutral (never red).
class DeficitLine extends StatelessWidget {
  const DeficitLine({super.key, required this.plan, required this.tdeeKcal});

  final NutritionTargetPlan plan;
  final double? tdeeKcal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tdee = tdeeKcal;

    if (tdee == null || tdee <= 0) {
      return Text(
        'Upkeep estimate building — keep logging',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      );
    }
    if (plan.goal == 'maintain') {
      return Text(
        'Matched to your ${tdee.toStringAsFixed(0)} kcal upkeep',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      );
    }

    final delta = plan.caloriesTarget - tdee; // negative = deficit
    final sign = delta >= 0 ? '+' : '−';
    final toneColor = goalRateColor(
      goalType: plan.goal,
      value: delta,
      neutral: colors.onSurfaceVariant,
      maintainTolerance: 50,
    );
    final rate = plan.ratePerWeek;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$sign${delta.abs().toStringAsFixed(0)} kcal/day',
                style: AppTextStyles.metric(
                  theme.textTheme.bodyLarge ?? const TextStyle(),
                ).copyWith(color: toneColor, fontWeight: FontWeight.w700),
              ),
              TextSpan(
                text: ' vs your ${tdee.toStringAsFixed(0)} kcal upkeep',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (rate != null) ...[
          const SizedBox(height: 2),
          Text(
            '≈ ${rate.abs().toStringAsFixed(2)} kg/week if you stay on target',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Macros that visibly fill the calorie budget: a stacked proportion bar on top
/// of the three macro rows.
class StrategyMacrosGridCard extends StatelessWidget {
  const StrategyMacrosGridCard({super.key, required this.plan});

  final NutritionTargetPlan plan;

  @override
  Widget build(BuildContext context) {
    final cal = plan.caloriesTarget <= 0 ? 1.0 : plan.caloriesTarget;
    final proteinPct = (plan.proteinTarget * 4 / cal).clamp(0.0, 1.0);
    final carbsPct = (plan.carbsTarget * 4 / cal).clamp(0.0, 1.0);
    final fatPct = (plan.fatTarget * 9 / cal).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Macros'),
        SectionList(
          card: true,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
              child: ProportionBar(
                segments: [
                  (fraction: proteinPct, color: AppColors.macroProtein),
                  (fraction: carbsPct, color: AppColors.macroCarbs),
                  (fraction: fatPct, color: AppColors.macroFat),
                ],
              ),
            ),
            _MacroRow(
              label: 'Protein',
              grams: plan.proteinTarget,
              percent: proteinPct,
              color: AppColors.macroProtein,
            ),
            _MacroRow(
              label: 'Carbs',
              grams: plan.carbsTarget,
              percent: carbsPct,
              color: AppColors.macroCarbs,
            ),
            _MacroRow(
              label: 'Fat',
              grams: plan.fatTarget,
              percent: fatPct,
              color: AppColors.macroFat,
            ),
          ],
        ),
      ],
    );
  }
}

/// Flat macro row: macro dot + label left; grams value + % share right.
class _MacroRow extends StatelessWidget {
  const _MacroRow({
    required this.label,
    required this.grams,
    required this.percent,
    required this.color,
  });

  final String label;
  final double grams;
  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          Text(
            '${grams.toStringAsFixed(0)} g',
            style: AppTextStyles.metric(
              theme.textTheme.labelLarge ?? const TextStyle(),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '· ${(percent * 100).toStringAsFixed(0)}%',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
