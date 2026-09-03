import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/onboarding/domain/onboarding_telemetry.dart';

import '../../domain/repositories/health_metrics_repository.dart';

/// The user's response to the value-timed Apple Health connect primer.
enum HealthConnectPrimerChoice { connect, manual }

/// Shows the value-timed Apple Health connect primer ONCE — before the first
/// weight-log — then returns so the caller can proceed to the manual weight
/// entry either way. Never dead-ends: declining (or dismissing) still proceeds.
///
/// The locked rule is honoured: the OS HealthKit permission request only fires
/// after the user taps "Connect" at a genuine value moment (logging weight),
/// never at launch and never before the primer states the payoff.
Future<void> maybeRunHealthConnectPrimer(
  BuildContext context, {
  PreferencesService? preferences,
  HealthMetricsRepository? healthMetricsRepository,
}) async {
  final prefs = preferences ?? GetIt.instance<PreferencesService>();
  if (prefs.seenHealthConnectPrimer) return;
  // Mark seen up-front so the primer shows exactly once, even if the user
  // dismisses it with a swipe rather than tapping a button.
  await prefs.setSeenHealthConnectPrimer(true);
  if (!context.mounted) return;

  final choice = await showHealthConnectPrimer(context);
  OnboardingTelemetry.instance.healthPrimerResult(
    choice == HealthConnectPrimerChoice.connect ? 'connect' : 'later',
  );
  if (choice != HealthConnectPrimerChoice.connect) return;

  // "Connect" → the real OS permission request, reusing the same repository
  // call the rest of the app uses. Best-effort: a declined/failed request must
  // never block the manual save that follows.
  try {
    final repo =
        healthMetricsRepository ??
        (GetIt.instance.isRegistered<HealthMetricsRepository>()
            ? GetIt.instance<HealthMetricsRepository>()
            : null);
    await repo?.requestPermissions();
  } catch (_) {
    // Swallowed on purpose — the weight-log flow continues regardless.
  }
}

/// Presents the primer as a bottom sheet (lower-risk than a route) and resolves
/// with the user's [HealthConnectPrimerChoice], or null if dismissed.
Future<HealthConnectPrimerChoice?> showHealthConnectPrimer(
  BuildContext context,
) {
  return showModalBottomSheet<HealthConnectPrimerChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (context) => const HealthConnectPrimer(),
  );
}

/// The HEALTH pillar moment: a value-stating primer BEFORE the OS HealthKit
/// dialog. It leads with the cross-pillar payoff ("your weight trend makes your
/// coach's targets sharper"), states exactly what's read, and keeps a manual
/// fallback so declining never dead-ends.
class HealthConnectPrimer extends StatelessWidget {
  const HealthConnectPrimer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // The same sheet backs iOS (Apple Health) and Android (Health Connect), so
    // name the right service per platform; fall back to neutral wording on web.
    final String serviceName;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      serviceName = 'Apple Health';
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      serviceName = 'Health Connect';
    } else {
      serviceName = 'your health data';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x3,
        AppSpacing.x1,
        AppSpacing.x3,
        AppSpacing.x3,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentEmeraldGreen.withValues(alpha: 0.06),
              ),
              child: Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentEmeraldGreen.withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.favorite_rounded,
                  size: 32,
                  color: AppColors.accentEmeraldGreen,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          Text(
            'Connect $serviceName',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(
            'Your weight and workouts auto-fill — and your weight trend makes '
            "your coach's targets sharper.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          Container(
            padding: const EdgeInsets.all(AppSpacing.x2),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: AppRadius.cardRadius,
              border: Border.all(color: colors.outlineVariant),
            ),
            child: const Column(
              children: [
                _ReadRow(
                  icon: Icons.monitor_weight_outlined,
                  label: 'Body weight & trend',
                ),
                SizedBox(height: AppSpacing.x1 + 4),
                _ReadRow(
                  icon: Icons.fitness_center_rounded,
                  label: 'Workouts & energy',
                ),
                SizedBox(height: AppSpacing.x1 + 4),
                _ReadRow(
                  icon: Icons.favorite_border_rounded,
                  label: 'Heart rate',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          FilledButton.icon(
            onPressed: () {
              Haptics.confirm();
              context.pop(HealthConnectPrimerChoice.connect);
            },
            icon: const Icon(Icons.favorite_rounded, size: 20),
            label: Text('Connect $serviceName'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
              textStyle: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              shape: const RoundedRectangleBorder(
                borderRadius: AppRadius.controlRadius,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          Center(
            child: TextButton(
              onPressed: () => context.pop(HealthConnectPrimerChoice.manual),
              child: Text(
                'Log manually instead',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 14,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Read-only · disconnect anytime in Settings',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadRow extends StatelessWidget {
  const _ReadRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: colors.onSurfaceVariant),
        const SizedBox(width: AppSpacing.x2),
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Icon(
          Icons.check_rounded,
          size: 18,
          color: AppColors.accentEmeraldGreen,
        ),
      ],
    );
  }
}
