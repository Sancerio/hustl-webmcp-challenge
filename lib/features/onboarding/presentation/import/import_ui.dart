import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_shadows.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';

/// Resting-card treatment for the onboarding import surfaces: surface-ladder
/// fill + a subtle soft shadow + card radius, no hard border.
BoxDecoration importCard(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: colors.surfaceContainerHigh,
    borderRadius: AppRadius.cardRadius,
    boxShadow: [AppShadows.subtle(context)],
  );
}

/// A raised stat tile — emphasized tabular numeral + quiet caption. Used for the
/// restored-history stat row.
class ImportStatTile extends StatelessWidget {
  const ImportStatTile({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.x2,
        horizontal: AppSpacing.x1,
      ),
      decoration: importCard(context),
      child: Column(
        children: [
          Text(value, style: AppTextStyles.metricEmphasis(context)),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// A reassurance line — emerald check + quiet body copy. Used on the preview to
/// promise nothing is lost or overwritten.
class ImportReassurance extends StatelessWidget {
  const ImportReassurance(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_circle_outline_rounded,
          size: 18,
          color: AppColors.accentEmeraldGreen,
        ),
        const SizedBox(width: AppSpacing.x1),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
