import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';
import 'package:hustl_app/core/widgets/app_section.dart';

import 'nutrition_chart_kit.dart';

/// Data quality: two coverage meters + a hint tying back to the coach's
/// confidence cue. Sits directly under macros so thin data is seen first.
class StrategyDataQualityRingsCard extends StatelessWidget {
  const StrategyDataQualityRingsCard({super.key, required this.coverage});

  final Map<String, dynamic>? coverage;

  @override
  Widget build(BuildContext context) {
    final daysLogged =
        (coverage?['daysWithCaloriesLogged'] as num?)?.toInt() ?? 0;
    final weighIns = (coverage?['weighInDays'] as num?)?.toInt() ?? 0;
    final accent = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Data quality'),
        SectionList(
          card: true,
          children: [
            _DataQualityRow(
              label: 'Logging',
              valueLabel: '$daysLogged/7',
              fraction: (daysLogged / 7).clamp(0.0, 1.0),
              color: accent,
            ),
            _DataQualityRow(
              label: 'Weigh-ins',
              valueLabel: '$weighIns/7',
              fraction: (weighIns / 7).clamp(0.0, 1.0),
              color: accent,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1 + 2),
              child: Text(
                'More logs sharpen the confidence cue above.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Flat data-quality row: label left, value right, slim bar beneath.
class _DataQualityRow extends StatelessWidget {
  const _DataQualityRow({
    required this.label,
    required this.valueLabel,
    required this.fraction,
    required this.color,
  });

  final String label;
  final String valueLabel;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
              Text(
                valueLabel,
                style: AppTextStyles.metric(
                  theme.textTheme.labelLarge ?? const TextStyle(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ProportionBar(
            segments: [(fraction: fraction.clamp(0.0, 1.0), color: color)],
            height: 4,
            gap: 0,
          ),
        ],
      ),
    );
  }
}
