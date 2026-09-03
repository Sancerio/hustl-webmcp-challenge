import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_radius.dart';

import 'segmented_pill_selector.dart';

// The Insights screen is assembled from these card widgets — each lives in its
// own file now (the old 1000-line monolith was split). Re-exported here so the
// screen keeps a single import.
export 'data_quality_card.dart';
export 'energy_balance_card.dart';
export 'insights_adherence_card.dart';
export 'insights_averages_card.dart';
export 'insights_coach_recommendations.dart';
export 'insights_weight_change_card.dart';

class InsightsRangeSelectorCard extends StatelessWidget {
  const InsightsRangeSelectorCard({
    super.key,
    required this.selectedDays,
    required this.onSelect,
  });

  final int selectedDays;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SegmentedPillSelector<int>(
      options: const [7, 14, 30],
      selected: selectedDays,
      onSelect: onSelect,
      labels: const {7: '1W', 14: '2W', 30: '1M'},
    );
  }
}

/// A compact label-over-value stat pill (icon optional).
class InsightsStatPill extends StatelessWidget {
  const InsightsStatPill({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    this.icon,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$value $unit',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
