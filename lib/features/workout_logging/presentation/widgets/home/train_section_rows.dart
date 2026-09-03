import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/animated_metric_text.dart';

/// A flat navigation row for the TRAINING section: 15px label, quiet caption,
/// trailing chevron. No icon blocks, no card chrome — hairline dividers come
/// from the enclosing [SectionList].
class TrainNavRow extends StatelessWidget {
  const TrainNavRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Semantics(
      container: true,
      button: true,
      label: '$title. $subtitle',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An aligned stat row for the THIS WEEK section: 15px label left, 15px
/// tabular value right (a calm count-up).
class TrainStatRow extends StatelessWidget {
  const TrainStatRow({
    super.key,
    required this.label,
    required this.value,
    this.fractionDigits = 0,
    this.suffix = '',
  });

  final String label;
  final double value;
  final int fractionDigits;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          AnimatedMetricText(
            value: value,
            fractionDigits: fractionDigits,
            suffix: suffix,
            grouped: true,
            style: theme.textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}
