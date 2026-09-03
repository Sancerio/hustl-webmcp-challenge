import 'package:flutter/material.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_radius.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../app/theme/app_text_styles.dart';
import 'health_dashboard_charts.dart';
import 'health_dashboard_copy.dart';

/// "Body" — the below-the-fold baselines card. HRV, resting heart rate, and
/// sleep moved up into the conditions overview's instruments row (see
/// `conditions_instruments.dart`); this grid keeps only the signals that
/// don't otherwise appear on the screen — weight and body composition — so no
/// metric is shown twice.
class BiologyGrid extends StatelessWidget {
  const BiologyGrid({
    super.key,
    required this.latestWeightKg,
    required this.latestBmi,
    required this.weeklyWeightChangeKg,
    required this.weightTrend,
    required this.bmiTrend,
  });

  final double? latestWeightKg;
  final double? latestBmi;
  final double? weeklyWeightChangeKg;
  final List<double> weightTrend;
  final List<double> bmiTrend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rows = <Widget>[
      _BaselineRow(
        title: 'Weight',
        value: latestWeightKg == null
            ? '—'
            : '${latestWeightKg!.toStringAsFixed(1)} kg',
        status: weightStatus(weeklyWeightChangeKg),
        accent: colors.primary,
        values: weightTrend,
      ),
      _BaselineRow(
        title: 'Body composition',
        value: latestBmi == null ? '—' : latestBmi!.toStringAsFixed(1),
        status: bmiStatus(latestBmi),
        accent: AppColors.accentEmeraldGreen,
        values: bmiTrend,
      ),
    ];

    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) children.add(const Divider(height: 1));
      children.add(rows[i]);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _BaselineRow extends StatelessWidget {
  const _BaselineRow({
    required this.title,
    required this.value,
    required this.status,
    required this.accent,
    required this.values,
  });

  final String title;
  final String value;
  final String status;
  final Color accent;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$title: $value, $status',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2,
          vertical: AppSpacing.x2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text(title, style: theme.textTheme.bodyLarge)),
                Text(value, style: AppTextStyles.metricEmphasis(context)),
              ],
            ),
            const SizedBox(height: 2),
            Text(status, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.x1),
            SparklineShell(accent: accent, values: values),
          ],
        ),
      ),
    );
  }
}
