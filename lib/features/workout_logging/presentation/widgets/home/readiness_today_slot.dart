import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';

import 'readiness_today_row.dart';

enum ReadinessTodayStatus { loading, available, unavailable }

/// The independently loaded state of the Train-home readiness annotation.
@immutable
class ReadinessTodayState {
  const ReadinessTodayState.loading()
    : status = ReadinessTodayStatus.loading,
      snapshot = null;

  const ReadinessTodayState.available(this.snapshot)
    : assert(snapshot != null),
      status = ReadinessTodayStatus.available;

  const ReadinessTodayState.unavailable()
    : status = ReadinessTodayStatus.unavailable,
      snapshot = null;

  final ReadinessTodayStatus status;
  final DailyRecoverySnapshot? snapshot;
}

/// A fixed-height viewport that prevents late Health hydration from moving the
/// next-session card while the user is scrolling.
class ReadinessTodaySlot extends StatelessWidget {
  const ReadinessTodaySlot({super.key, required this.state});

  final ReadinessTodayState state;

  static const double height = AppSpacing.x6 + AppSpacing.x2;

  /// Keeps all readiness states the same height at the current accessibility
  /// text scale while preserving the compact 64px default geometry.
  static double heightFor(TextScaler scaler) {
    final scaleDelta = scaler.scale(1) - 1;
    return height + (scaleDelta > 0 ? scaleDelta * 40 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : AppMotion.fast;

    return SizedBox(
      height: heightFor(MediaQuery.textScalerOf(context)),
      child: AnimatedSwitcher(
        duration: duration,
        reverseDuration: duration,
        switchInCurve: AppMotion.enterCurve,
        switchOutCurve: AppMotion.exitCurve,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: switch (state.status) {
          ReadinessTodayStatus.loading => const _LoadingPlaceholder(
            key: ValueKey('readiness-loading'),
          ),
          ReadinessTodayStatus.available => ReadinessTodayRow(
            key: const ValueKey('readiness-available'),
            snapshot: state.snapshot!,
          ),
          ReadinessTodayStatus.unavailable => const _UnavailableRow(
            key: ValueKey('readiness-unavailable'),
          ),
        },
      ),
    );
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading readiness',
      child: const ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.x2,
            vertical: AppSpacing.x1 + 4,
          ),
          child: Row(
            children: [
              AppSkeleton(
                width: 10,
                height: 10,
                shape: BoxShape.circle,
                animate: false,
              ),
              SizedBox(width: AppSpacing.x1 + 2),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeleton(width: 132, height: 12, animate: false),
                    SizedBox(height: 7),
                    AppSkeleton(width: 212, height: 10, animate: false),
                  ],
                ),
              ),
              SizedBox(width: AppSpacing.x1),
              AppSkeleton(width: 20, height: 20, animate: false),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnavailableRow extends StatelessWidget {
  const _UnavailableRow({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    void openHealth() {
      Haptics.selection();
      context.push('/health');
    }

    return Semantics(
      container: true,
      button: true,
      onTap: openHealth,
      label:
          'Readiness, not available yet, open Health to check your synced '
          'data, opens recovery details',
      child: ExcludeSemantics(
        child: Material(
          color: colors.surface,
          borderRadius: AppRadius.cardRadius,
          child: InkWell(
            borderRadius: AppRadius.cardRadius,
            onTap: openHealth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x2,
                vertical: AppSpacing.x1 + 4,
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors.outlineVariant,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x1 + 2),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Readiness',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.x1),
                            Flexible(
                              child: Text(
                                'Not available yet',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Open Health to check your synced data.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x1),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
