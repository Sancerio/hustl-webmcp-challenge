import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';

import 'progress_charts.dart';

/// Surfaces the per-region training balance — which BodyScoreService already
/// computes but the Progress tab never linked to — as a calm card with a
/// one-line plain cue and a tap into the full `/progress/body-score` heat map.
class ProgressBalanceCard extends StatelessWidget {
  const ProgressBalanceCard({
    super.key,
    required this.regionSets,
    required this.onTap,
  });

  /// Weekly-equivalent sets per display region (label → sets). Rendered in the
  /// map's iteration order, so callers pass it sorted most-trained first.
  final Map<String, double> regionSets;
  final VoidCallback onTap;

  String _cue() {
    final entries = regionSets.entries.where((e) => e.value > 0).toList();
    if (entries.length < 2) {
      return 'Train across muscle groups to balance.';
    }
    entries.sort((a, b) => b.value.compareTo(a.value));
    return '${entries.first.key} leads · ${entries.last.key} is lagging';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Training balance',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _cue(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (regionSets.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.x2),
                SimpleHorizontalBars(
                  data: regionSets,
                  formatValue: (v) => '${v.toStringAsFixed(0)} sets',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
