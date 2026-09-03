import 'package:flutter/material.dart';

import '../utils/weight_unit.dart';

class WeighInPromptCard extends StatelessWidget {
  const WeighInPromptCard({
    super.key,
    required this.onLogTap,
    required this.onDismissTap,
    this.latestWeightKg,
    this.latestWeightDate,
    this.unit = const WeightUnit('kg'),
  });

  final VoidCallback onLogTap;
  final VoidCallback onDismissTap;
  final double? latestWeightKg;
  final DateTime? latestWeightDate;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final localizations = MaterialLocalizations.of(context);

    final lastLabel = (latestWeightKg != null && latestWeightDate != null)
        ? 'Last: ${unit.formatWeight(latestWeightKg)} · ${localizations.formatMediumDate(latestWeightDate!.toLocal())}'
        : null;

    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Weigh-in', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 2),
            Text(
              'Log today’s weigh-in. Morning is best for consistency.',
              style: theme.textTheme.bodySmall,
            ),
            if (lastLabel != null) ...[
              const SizedBox(height: 6),
              Text(
                lastLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onLogTap,
                    child: const Text('Log weigh-in'),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: onDismissTap,
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
