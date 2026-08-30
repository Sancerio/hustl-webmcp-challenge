import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/health_platform_labels.dart';
import '../bloc/health_overview_bloc.dart';
import 'health_sync_warnings_banner.dart';

class HealthOverviewEmptyState extends StatelessWidget {
  const HealthOverviewEmptyState({
    super.key,
    this.lastSyncedAt,
    this.warnings = const [],
    this.debugPanel,
  });

  final DateTime? lastSyncedAt;
  final List<String> warnings;
  final Widget? debugPanel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final providerLabel = healthPlatformLabel(platform: theme.platform);

    final colors = theme.colorScheme;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.primary.withValues(alpha: 0.10),
          ),
          child: Icon(Icons.track_changes, size: 32, color: colors.primary),
        ),
        const SizedBox(height: AppSpacing.x3),
        Text(
          'Your health data is on its way',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          '$providerLabel can take a few minutes to share new entries after you connect — that is completely normal.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          "If it's still empty, there may not be enough recent sleep, recovery, activity, or weight data yet. Keep wearing your device, log a body measurement in $providerLabel, then check back.",
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          _syncStatusMessage(context),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        FilledButton(
          onPressed: () => context.read<HealthOverviewBloc>().add(
            const HealthOverviewRefreshed(),
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3),
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.controlRadius,
            ),
          ),
          child: const Text('Check again'),
        ),
        if (warnings.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.x3),
          HealthSyncWarningsBanner(warnings: warnings),
        ],
        if (debugPanel != null) ...[
          const SizedBox(height: AppSpacing.x3),
          debugPanel!,
        ],
      ],
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final minHeight = constraints.hasBoundedHeight
                ? math.max(0.0, constraints.maxHeight - AppSpacing.x6)
                : 0.0;
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.x3,
                horizontal: AppSpacing.x1,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Align(alignment: Alignment.topCenter, child: content),
              ),
            );
          },
        ),
      ),
    );
  }

  String _syncStatusMessage(BuildContext context) {
    final syncTime = lastSyncedAt?.toLocal();
    if (syncTime == null) {
      return 'We’ll keep checking for updates automatically and let you know when your first sync finishes.';
    }

    final difference = DateTime.now().difference(syncTime);
    final timeOfDay = TimeOfDay.fromDateTime(syncTime).format(context);

    if (difference.inMinutes < 1) {
      return 'We checked for new data just now at $timeOfDay.';
    }
    if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      final unit = minutes == 1 ? 'minute' : 'minutes';
      return 'We last checked $minutes $unit ago at $timeOfDay.';
    }
    if (difference.inHours < 24) {
      final hours = difference.inHours;
      final unit = hours == 1 ? 'hour' : 'hours';
      return 'We last checked $hours $unit ago at $timeOfDay.';
    }
    return 'We last checked on ${_formatMonthDay(syncTime)} at $timeOfDay.';
  }

  String _formatMonthDay(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}
