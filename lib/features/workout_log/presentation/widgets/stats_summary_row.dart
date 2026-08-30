import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/utils/number_format_util.dart';
import 'package:hustl_app/core/widgets/app_section.dart';

/// Key Progress statistics as a grouped card (Wave I — "data as hero"): label
/// left, tabular value right, hairline dividers between rows inside one rounded
/// surface so the rows read as objects, not ledger lines.
class StatsSummaryRow extends StatelessWidget {
  const StatsSummaryRow({
    super.key,
    required this.bestSessionVolume,
    required this.avgWeeklyEffectiveSets,
  });

  final double bestSessionVolume;
  final double avgWeeklyEffectiveSets;

  @override
  Widget build(BuildContext context) {
    return SectionList(
      card: true,
      children: [
        _StatRow(
          label: 'Best session',
          value: NumberFormatUtil.formatDouble(
            bestSessionVolume,
            decimalDigits: 0,
          ),
          unit: 'kg',
        ),
        _StatRow(
          label: 'Avg weekly hard sets',
          value: NumberFormatUtil.formatDouble(
            avgWeeklyEffectiveSets,
            decimalDigits: 1,
          ),
          unit: 'sets',
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1 + 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          Text(value, style: theme.textTheme.labelLarge),
          const SizedBox(width: 4),
          Text(
            unit,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
