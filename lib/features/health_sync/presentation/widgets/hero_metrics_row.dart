import 'package:flutter/material.dart';

import '../../../../app/theme/app_shadows.dart';
import '../../../../app/theme/app_spacing.dart';

class HeroMetricsRow extends StatelessWidget {
  const HeroMetricsRow({
    super.key,
    this.latestWeightKg,
    this.weeklyWeightChangeKg,
    this.latestHeightCm,
    this.latestBmi,
  });

  final double? latestWeightKg;
  final double? weeklyWeightChangeKg;
  final double? latestHeightCm;
  final double? latestBmi;

  @override
  Widget build(BuildContext context) {
    final entries = <_MetricEntry>[];

    if (latestWeightKg != null) {
      final changeLabel = _formatDelta(weeklyWeightChangeKg);
      entries.add(
        _MetricEntry(
          label: 'Weight',
          value: '${latestWeightKg!.toStringAsFixed(1)} kg',
          detail: changeLabel == null
              ? null
              : changeLabel == 'Stable'
              ? 'Stable vs last week'
              : changeLabel,
        ),
      );
    }

    if (latestHeightCm != null) {
      entries.add(
        _MetricEntry(
          label: 'Height',
          value: '${latestHeightCm!.toStringAsFixed(1)} cm',
        ),
      );
    }

    if (latestBmi != null) {
      entries.add(
        _MetricEntry(label: 'BMI', value: latestBmi!.toStringAsFixed(1)),
      );
    }

    if (entries.isEmpty) {
      return const _EmptyMetricsMessage();
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
              'Body metrics',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              'Latest body measurements from your connected provider.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 420;
                if (stacked) {
                  return Column(
                    children: entries.indexed.expand((entry) {
                      final index = entry.$1;
                      final item = entry.$2;
                      return [
                        _MetricInline(entry: item),
                        if (index != entries.length - 1)
                          Divider(
                            height: AppSpacing.x3,
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.8,
                            ),
                          ),
                      ];
                    }).toList(),
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: entries.indexed.expand((entry) {
                    final index = entry.$1;
                    final item = entry.$2;
                    return [
                      Expanded(child: _MetricInline(entry: item)),
                      if (index != entries.length - 1)
                        Container(
                          width: 1,
                          height: 88,
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.8,
                          ),
                        ),
                      if (index != entries.length - 1)
                        const SizedBox(width: AppSpacing.x2),
                    ];
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricEntry {
  const _MetricEntry({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;
}

class _MetricInline extends StatelessWidget {
  const _MetricInline({required this.entry});

  final _MetricEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          entry.value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (entry.detail != null) ...[
          const SizedBox(height: 4),
          Text(
            entry.detail!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyMetricsMessage extends StatelessWidget {
  const _EmptyMetricsMessage();

  @override
  Widget build(BuildContext context) {
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
              'Body metrics',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              'Connect and sync to see body measurements here.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _formatDelta(double? delta) {
  if (delta == null) return null;
  if (delta.abs() < 0.1) return 'Stable';
  final sign = delta > 0 ? '+' : '';
  return '$sign${delta.toStringAsFixed(1)} kg vs last week';
}
