import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';

import '../utils/goal_rate_color.dart';
import '../utils/weight_unit.dart';

/// A three-up stat strip beneath the Weight hero+chart: period change, weekly
/// rate, and period average. The change + rate are goal-aware and
/// adherence-neutral (emerald toward the goal, amber drift, never red); the
/// average is neutral.
class WeightStatStrip extends StatelessWidget {
  const WeightStatStrip({
    super.key,
    required this.unit,
    required this.periodChangeKg,
    required this.weeklyRateKg,
    required this.periodAverageKg,
    required this.goalType,
    required this.periodLabel,
  });

  final WeightUnit unit;
  final double? periodChangeKg;
  final double? weeklyRateKg;
  final double? periodAverageKg;
  final String? goalType;

  /// Short label for the selected window, e.g. '1M' (used in the change caption).
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final neutral = theme.colorScheme.onSurfaceVariant;

    final changeColor = goalRateColor(
      goalType: goalType,
      value: periodChangeKg,
      neutral: neutral,
    );
    final rateColor = goalRateColor(
      goalType: goalType,
      value: weeklyRateKg,
      neutral: neutral,
    );

    final rateText = weeklyRateKg == null
        ? '—'
        : '${unit.formatDelta(weeklyRateKg, decimals: 2).replaceFirst(' ${unit.suffix}', '')} ${unit.suffix}/wk';

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.cardRadius,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: AppSpacing.x2,
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              label: 'Change · $periodLabel',
              value: unit.formatDelta(periodChangeKg),
              color: changeColor,
            ),
          ),
          _Divider(),
          Expanded(
            child: _Stat(
              label: 'Weekly rate',
              value: rateText,
              color: rateColor,
            ),
          ),
          _Divider(),
          Expanded(
            child: _Stat(
              label: 'Average',
              value: unit.formatWeight(periodAverageKg),
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.x1),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTextStyles.metric(
            theme.textTheme.titleMedium ?? const TextStyle(),
          ).copyWith(color: color, fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
