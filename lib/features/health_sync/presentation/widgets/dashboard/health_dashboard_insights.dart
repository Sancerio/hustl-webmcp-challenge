import 'package:flutter/material.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_radius.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../domain/usecases/derive_health_insights.dart';

/// Wave I (Apple Fitness+ x Whoop, "data as hero"): insights read as a single
/// grouped card of objects — each row a small severity dot (emerald / amber /
/// primary), a title, and a quiet message. Hairline dividers, no spreadsheet.
class InsightDeck extends StatelessWidget {
  const InsightDeck({super.key, required this.insights});

  final List<HealthInsight> insights;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shown = insights.take(3).toList();
    final children = <Widget>[];
    for (var i = 0; i < shown.length; i++) {
      if (i > 0) children.add(const Divider(height: 1));
      children.add(InsightRow(insight: shown[i]));
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

class InsightRow extends StatelessWidget {
  const InsightRow({super.key, required this.insight});

  final HealthInsight insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = switch (insight.severity) {
      HealthInsightSeverity.success => AppColors.accentEmeraldGreen,
      HealthInsightSeverity.warning => AppColors.accentWarningAmber,
      HealthInsightSeverity.info => theme.colorScheme.primary,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: AppSpacing.x2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(insight.title, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  insight.message,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
