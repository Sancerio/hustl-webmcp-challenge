import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';

/// A kind, compact inline error card for nutrition surfaces that can't earn a
/// full-screen hero. A soft tinted holder, a plain-language sentence-case
/// headline, the technical cause demoted to a quiet supportive line, and a
/// single 'Try again' action that re-triggers the load. Never alarmist — the
/// tint is a gentle error wash, not a red block, and the raw cause is never the
/// primary text.
class NutritionInlineError extends StatelessWidget {
  const NutritionInlineError({
    super.key,
    this.title = 'Couldn’t load this',
    this.detail,
    required this.onRetry,
    this.retryLabel = 'Try again',
  });

  /// Plain-language headline (sentence case).
  final String title;

  /// Optional technical cause, demoted to a quiet supportive line.
  final String? detail;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x2),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.4),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: colors.error),
          const SizedBox(width: AppSpacing.x1 + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail != null && detail!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.x1),
          TextButton(onPressed: onRetry, child: Text(retryLabel)),
        ],
      ),
    );
  }
}
