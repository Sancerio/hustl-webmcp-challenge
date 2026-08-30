import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:hustl_app/app/di/service_locator.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/onboarding/domain/onboarding_telemetry.dart';

import '../../domain/import_summary.dart';
import '../../domain/workout_import_runner.dart';
import 'import_ui.dart';

/// The switcher's magic moment. After the real [WorkoutImportRunner] writes the
/// history, this celebrates with real restored stats and completes onboarding —
/// this CTA is the ONLY completion for the import path.
class OnboardingImportRestoredScreen extends StatelessWidget {
  const OnboardingImportRestoredScreen({
    super.key,
    required this.outcome,
    required this.summary,
  });

  final ImportOutcome outcome;
  final ImportSummary summary;

  Future<void> _finish(BuildContext context) async {
    Haptics.confirm();
    final prefs = getIt<PreferencesService>();
    await prefs.setOnboardingIntroSeen(true);
    // Mirror the welcome's _finish: suppress the legacy v2 first-run surfaces so
    // they don't stack on top of a freshly imported history.
    await prefs.setOnboardingV2SeenEntry(true);
    await prefs.setOnboardingV2SeenCoachmarkStartWorkout(true);
    if (!context.mounted) return;
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    OnboardingTelemetry.instance.importCompleted(workouts: summary.workouts);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final since = summary.firstDate != null
        ? DateFormat('MMM yyyy').format(summary.firstDate!)
        : null;
    final replacedNote = outcome.replaced > 0
        ? '${outcome.imported} workouts restored from Strong — '
              '${outcome.replaced} updated in place.'
        : '${outcome.imported} workouts imported from Strong — '
              'nothing left behind.';

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x3,
            AppSpacing.x3,
            AppSpacing.x3,
            AppSpacing.x4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentEmeraldGreen.withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    Icons.cloud_done_rounded,
                    size: 34,
                    color: AppColors.accentEmeraldGreen,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.x2),
              Text(
                'Your training came with you',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(
                replacedNote,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.x3),
              Row(
                children: [
                  Expanded(
                    child: ImportStatTile(
                      value: '${summary.workouts}',
                      label: 'workouts',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x1),
                  Expanded(
                    child: ImportStatTile(
                      value: '${summary.exercises}',
                      label: 'exercises',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x1),
                  Expanded(
                    child: ImportStatTile(
                      value: '${summary.totalVolumeTonnes.round()} t',
                      label: 'lifted',
                    ),
                  ),
                ],
              ),
              if (since != null) ...[
                const SizedBox(height: AppSpacing.x1),
                Center(
                  child: Text(
                    'Your full history since $since',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.x4),
              Container(
                padding: const EdgeInsets.all(AppSpacing.x2),
                decoration: importCard(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your coach got a head start',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      'It already knows your lifts from your '
                      '${summary.workouts} imported sessions, so it can pick up '
                      'right where you left off.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.x4),
              FilledButton.icon(
                onPressed: () => _finish(context),
                icon: const Icon(Icons.bolt_rounded, size: 20),
                label: const Text('Take me to Hustl'),
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
              Text(
                'Everything you imported is saved on this device.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
