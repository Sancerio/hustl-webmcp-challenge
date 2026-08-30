import 'package:flutter/material.dart';

import '../../../../app/theme/app_shadows.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../domain/usecases/derive_health_insights.dart';

class InsightsList extends StatelessWidget {
  const InsightsList({super.key, required this.insights});

  final List<HealthInsight> insights;

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [AppShadows.subtle(context)],
      ),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Insights',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              'What changed in your latest health data and what to do with it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            ...insights.indexed.expand((entry) {
              final index = entry.$1;
              final insight = entry.$2;
              return [
                _InsightRow(insight: insight),
                if (index != insights.length - 1)
                  Divider(
                    height: AppSpacing.x3,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                  ),
              ];
            }),
          ],
        ),
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.insight});

  final HealthInsight insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tone = _toneFor(colorScheme, insight.severity);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: tone.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(tone.icon, color: tone.foreground, size: 18),
        ),
        const SizedBox(width: AppSpacing.x2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                insight.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                insight.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static _InsightTone _toneFor(
    ColorScheme colorScheme,
    HealthInsightSeverity severity,
  ) {
    return switch (severity) {
      HealthInsightSeverity.success => _InsightTone(
        icon: Icons.check_rounded,
        background: colorScheme.secondaryContainer,
        foreground: colorScheme.onSecondaryContainer,
      ),
      HealthInsightSeverity.warning => _InsightTone(
        icon: Icons.warning_amber_rounded,
        background: colorScheme.errorContainer,
        foreground: colorScheme.onErrorContainer,
      ),
      HealthInsightSeverity.info => _InsightTone(
        icon: Icons.insights_outlined,
        background: colorScheme.primaryContainer,
        foreground: colorScheme.onPrimaryContainer,
      ),
    };
  }
}

class _InsightTone {
  const _InsightTone({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
}
