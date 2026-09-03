import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_shadows.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/health_platform_labels.dart';
import '../bloc/health_permissions_bloc.dart';

class HealthSyncWarningsBanner extends StatelessWidget {
  const HealthSyncWarningsBanner({super.key, required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final providerLabel = healthPlatformLabel(platform: theme.platform);
    final visibleWarnings = warnings.take(2).map(_compactWarning).toList();
    final hiddenCount = warnings.length - visibleWarnings.length;

    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.accentWarningAmber.withValues(alpha: 0.35),
        ),
        boxShadow: [AppShadows.subtle(context)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accentWarningAmber.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.accentWarningAmber,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Some health signals still need attention',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hustl can still use the data that is available. Review $providerLabel if this keeps showing up.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (warnings.length > 1)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Text(
                    '${warnings.length}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          ...visibleWarnings.map(
            (warning) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.x1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 7),
                    decoration: BoxDecoration(
                      color: AppColors.accentWarningAmber,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x1),
                  Expanded(
                    child: Text(
                      warning,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (hiddenCount > 0)
            Text(
              '+ $hiddenCount more signal${hiddenCount == 1 ? '' : 's'} still need attention.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: AppSpacing.x2),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                context.read<HealthPermissionsBloc>().add(
                  HealthPermissionsGrantRequested(),
                );
              },
              icon: const Icon(Icons.health_and_safety_outlined),
              label: Text('Review $providerLabel access'),
            ),
          ),
        ],
      ),
    );
  }

  String _compactWarning(String warning) {
    if (warning.startsWith("We couldn't read ")) {
      final labelMatch = RegExp(
        r"We couldn't read (.+?) from ",
      ).firstMatch(warning);
      final label = labelMatch?.group(1) ?? 'This metric';
      if (warning.toLowerCase().contains('authorization not determined')) {
        return '$label is not shared with Hustl yet.';
      }
      return '$label needs attention in your health provider.';
    }
    if (warning.contains('denied access to ')) {
      final labelMatch = RegExp(
        r'denied access to (.+?)\.',
      ).firstMatch(warning);
      final label = labelMatch?.group(1) ?? 'Health access';
      return '$label access is turned off.';
    }
    if (warning.startsWith('No recent health data found')) {
      return 'No recent health data found. Showing your most recent saved measurements instead.';
    }
    return warning;
  }
}
