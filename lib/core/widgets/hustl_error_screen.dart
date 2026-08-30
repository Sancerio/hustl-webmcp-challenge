import 'package:flutter/material.dart';

import '../../app/theme/app_spacing.dart';

/// Error screen for failed startup / loads with a retry path.
class HustlErrorScreen extends StatelessWidget {
  final String title;
  final String? details;
  final VoidCallback? onRetry;

  const HustlErrorScreen({
    super.key,
    this.title = 'Failed to load screen',
    this.details,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: AppSpacing.x1 + AppSpacing.x1 / 2),
                Text(
                  title,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (details != null) ...[
                  const SizedBox(height: AppSpacing.x1),
                  Text(
                    details!,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: AppSpacing.x2),
                if (onRetry != null)
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
