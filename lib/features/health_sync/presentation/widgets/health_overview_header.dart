import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/hustl_menu_button.dart';

enum HealthSyncHeaderStatus {
  preview,
  checking,
  live,
  notConnected,
  mobileRequired,
  unavailable,
}

/// Wave G (§12.1): a quiet screen header — 20/w700 title, a flat status chip,
/// and a muted supporting line. No outlined pills, no oversized numerals.
class HealthScreenHeader extends StatelessWidget {
  const HealthScreenHeader({super.key, required this.status});

  final HealthSyncHeaderStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = switch (status) {
      HealthSyncHeaderStatus.live => AppColors.accentEmeraldGreen,
      HealthSyncHeaderStatus.unavailable => colorScheme.error,
      _ => colorScheme.onSurfaceVariant,
    };
    final statusLabel = switch (status) {
      HealthSyncHeaderStatus.preview => 'Preview data',
      HealthSyncHeaderStatus.checking => 'Checking health sync',
      HealthSyncHeaderStatus.live => 'Live health sync',
      HealthSyncHeaderStatus.notConnected => 'Health sync not connected',
      HealthSyncHeaderStatus.mobileRequired => 'Mobile device required',
      HealthSyncHeaderStatus.unavailable => 'Health sync unavailable',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const HustlMenuButton(radius: 18),
            const Spacer(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  key: const Key('health-sync-status-dot'),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  statusLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x2),
        Text('Biology', style: theme.textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(
          'Your recovery and body signals for today.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
