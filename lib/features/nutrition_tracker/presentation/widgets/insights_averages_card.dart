import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/app_section.dart';

class InsightsAveragesCard extends StatelessWidget {
  const InsightsAveragesCard({
    super.key,
    required this.rangeDays,
    required this.averages,
  });

  final int rangeDays;
  final Map averages;

  @override
  Widget build(BuildContext context) {
    double n(dynamic v) => (v as num?)?.toDouble() ?? 0;
    final calories = n(averages['calories']);
    final protein = n(averages['proteinGrams']);
    final carbs = n(averages['carbsGrams']);
    final fat = n(averages['fatGrams']);
    final maxBar = [protein, carbs, fat].reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('$rangeDays-day averages'),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: AppRadius.cardRadius,
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AverageRow(
                label: 'Calories',
                value: calories,
                unit: 'kcal',
                color: AppColors.accentElectricBlue,
                fraction: 1,
              ),
              const Divider(),
              _AverageRow(
                label: 'Protein',
                value: protein,
                unit: 'g',
                color: AppColors.macroProtein,
                fraction: maxBar <= 0 ? 0 : (protein / maxBar).clamp(0.0, 1.0),
              ),
              const Divider(),
              _AverageRow(
                label: 'Carbs',
                value: carbs,
                unit: 'g',
                color: AppColors.macroCarbs,
                fraction: maxBar <= 0 ? 0 : (carbs / maxBar).clamp(0.0, 1.0),
              ),
              const Divider(),
              _AverageRow(
                label: 'Fat',
                value: fat,
                unit: 'g',
                color: AppColors.macroFat,
                fraction: maxBar <= 0 ? 0 : (fat / maxBar).clamp(0.0, 1.0),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AverageRow extends StatelessWidget {
  const _AverageRow({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.fraction,
  });

  final String label;
  final double value;
  final String unit;
  final Color color;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
              Text(
                '${value.toStringAsFixed(0)} $unit',
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Container(
              height: 4,
              color: theme.colorScheme.surfaceContainerHighest,
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedFractionallySizedBox(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  widthFactor: fraction.clamp(0.0, 1.0),
                  child: ColoredBox(color: color),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
