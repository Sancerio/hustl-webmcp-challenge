import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';

/// Shared sign-out confirmation sheet used by both the account sheet and
/// Settings, so the warning + reassurance copy can't drift between the two
/// surfaces. Returns `true` only when the user confirms sign-out.
Future<bool> confirmSignOut(BuildContext context) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x2,
          AppSpacing.x1,
          AppSpacing.x2,
          AppSpacing.x3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sign out?',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              'Your local workouts are safe. You can sign back in at any time.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => sheetContext.pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    onPressed: () => sheetContext.pop(true),
                    child: const Text('Sign out'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  return confirmed == true;
}
