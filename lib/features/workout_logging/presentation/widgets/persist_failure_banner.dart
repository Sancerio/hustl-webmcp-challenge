import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_spacing.dart';

/// A slim, theme-consistent banner shown at the top of the active workout when
/// a set edit failed to persist. The optimistic UI otherwise renders the lost
/// edit as saved, so this surfaces the failure with a one-tap retry that
/// re-persists the current session (the source of truth).
class PersistFailureBanner extends StatelessWidget {
  const PersistFailureBanner({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2,
          vertical: AppSpacing.x1,
        ),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 18,
              color: colorScheme.onErrorContainer,
            ),
            const SizedBox(width: AppSpacing.x1),
            Expanded(
              child: Text(
                "Changes couldn't be saved",
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onErrorContainer,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
