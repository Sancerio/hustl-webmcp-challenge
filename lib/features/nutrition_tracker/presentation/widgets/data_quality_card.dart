import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/app_section.dart';

import 'nutrition_chart_kit.dart';

/// Delivers the Insights screen's third promise: how much data is behind the
/// numbers. Shows days-logged coverage as a slim meter, tied to the verdict's
/// confidence cue above.
class DataQualityCard extends StatelessWidget {
  const DataQualityCard({
    super.key,
    required this.loggedDays,
    required this.totalDays,
  });

  final int loggedDays;
  final int totalDays;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fraction = totalDays <= 0
        ? 0.0
        : (loggedDays / totalDays).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Data quality'),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: AppRadius.cardRadius,
          ),
          padding: const EdgeInsets.all(AppSpacing.x2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Days logged',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  Text(
                    '$loggedDays / $totalDays',
                    style: theme.textTheme.labelLarge,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x1),
              ProportionBar(
                segments: [
                  (fraction: fraction, color: AppColors.accentElectricBlue),
                ],
              ),
              const SizedBox(height: AppSpacing.x1 + 2),
              Text(
                'More logged days sharpen the confidence cue above.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
