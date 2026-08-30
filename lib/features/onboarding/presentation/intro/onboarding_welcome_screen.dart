import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/di/service_locator.dart';
import 'package:hustl_app/app/navigation/app_router.dart' show navigatorKey;
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/widgets/legal_links_text.dart';
import 'package:hustl_app/features/auth/presentation/widgets/account_sheet.dart'
    show showLoginSheet;
import 'package:hustl_app/features/health_sync/domain/repositories/health_metrics_repository.dart';
import 'package:hustl_app/features/onboarding/domain/onboarding_telemetry.dart';

import 'onboarding_intro_art.dart';
import 'onboarding_trail_plan.dart';
import 'onboarding_welcome_terrain.dart';

/// The guest-first welcome / sign-in handoff at the end of the intro.
/// Connect-recovery-first: the primary action connects Apple Health / Health
/// Connect, because recovery-aware planning is the coach's differentiator.
/// Starting a workout with no account is the secondary action; import and
/// sign-in are reachable from the trail-plan card and the footer link.
/// Completing any path marks onboarding seen (and suppresses the legacy v2
/// entry sheet) and routes into the app. Gated by `HUSTL_ONBOARDING_V3`.
///
/// Health Connect / HealthKit don't exist on web, so [webFallback] (defaults
/// to [kIsWeb]) degrades the screen back to the original start-first
/// hierarchy: no recovery waypoint, "Start your first workout" primary,
/// "Bring your Strong history" secondary.
class OnboardingWelcomeScreen extends StatelessWidget {
  const OnboardingWelcomeScreen({super.key, bool? webFallback})
    : _webFallback = webFallback ?? kIsWeb;

  final bool _webFallback;

  Future<void> _finish(BuildContext context, String? push) async {
    await _markIntroSeen();
    if (!context.mounted) return;
    context.go('/');
    if (push != null) context.push(push);
  }

  /// Marks onboarding seen without navigating. Shared by every path that
  /// leaves the welcome screen for good (connect, start workout, import,
  /// sign-in), so an app-kill mid-flow always resumes past the carousel
  /// instead of replaying it.
  Future<void> _markIntroSeen() async {
    final prefs = getIt<PreferencesService>();
    await prefs.setOnboardingIntroSeen(true);
    // Don't stack the legacy v2 first-run surfaces on top of this welcome: the
    // entry sheet and the "tap here to start" coachmark are both now redundant.
    await prefs.setOnboardingV2SeenEntry(true);
    await prefs.setOnboardingV2SeenCoachmarkStartWorkout(true);
  }

  Future<void> _startImport(BuildContext context) async {
    // Mark seen before pushing (not just on the restored screen's completion):
    // if the app is killed mid-import, relaunch resumes at the welcome→home
    // gate instead of replaying the carousel. The router gate allowlists
    // `/onboarding/import` for already-seen users, so this push is unaffected.
    await _markIntroSeen();
    if (!context.mounted) return;
    context.push('/onboarding/import');
  }

  /// Completes onboarding like every other exit, then opens the real sign-in
  /// sheet directly instead of landing on the Account tab. `go('/')` disposes
  /// this screen, so the sheet is opened against the global navigator context
  /// (which outlives it) rather than the local one.
  Future<void> _openSignIn(BuildContext context) async {
    await _markIntroSeen();
    if (!context.mounted) return;
    final router = GoRouter.of(context);
    router.go('/');
    // `go` only schedules the page-stack change; opening the sheet before that
    // frame lands would stack it on the doomed welcome page, which the
    // transition then sweeps away along with it. Wait for the frame so the
    // sheet opens on top of the settled '/' page instead.
    await SchedulerBinding.instance.endOfFrame;
    final rootContext = navigatorKey.currentContext;
    if (rootContext == null) return;
    // ignore: use_build_context_synchronously
    await showLoginSheet(rootContext);
  }

  /// Marks onboarding (and the later weight-log health primer) seen, then
  /// best-effort requests the real OS recovery permission — mirroring
  /// `maybeRunHealthConnectPrimer`'s pattern exactly, just without its sheet,
  /// since this screen's own copy already states the payoff and read-only
  /// promise. A denial or throw must never dead-end: the Health overview has
  /// its own disconnected/connect state, so navigation proceeds regardless.
  Future<void> _connectRecovery(BuildContext context) async {
    await _markIntroSeen();
    final prefs = getIt<PreferencesService>();
    // Suppresses the value-timed weight-log primer, which would otherwise
    // re-ask for the same permission the user just granted (or declined)
    // here.
    await prefs.setSeenHealthConnectPrimer(true);
    try {
      final repo = getIt.isRegistered<HealthMetricsRepository>()
          ? getIt<HealthMetricsRepository>()
          : null;
      await repo?.requestPermissions();
    } catch (_) {
      // Swallowed on purpose — connecting is best-effort.
    }
    if (!context.mounted) return;
    context.go('/');
    context.push('/health');
  }

  void _handleConnect(BuildContext context) {
    OnboardingTelemetry.instance.welcomeAction('connect');
    Haptics.confirm();
    _connectRecovery(context);
  }

  void _handleStart(BuildContext context) {
    OnboardingTelemetry.instance.welcomeAction('start');
    Haptics.confirm();
    _finish(context, '/workout');
  }

  void _handleImport(BuildContext context) {
    OnboardingTelemetry.instance.welcomeAction('import');
    Haptics.selection();
    _startImport(context);
  }

  void _handleSignIn(BuildContext context) {
    OnboardingTelemetry.instance.welcomeAction('signin');
    Haptics.selection();
    _openSignIn(context);
  }

  @override
  Widget build(BuildContext context) {
    OnboardingTelemetry.instance.welcomeShown();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: Stack(
        children: [
          // The climb ahead: route mostly dashed, flag planted at the summit,
          // the icon-climber standing at the trailhead. Painted behind the
          // content so it degrades gracefully when the column scrolls.
          const Positioned.fill(
            bottom: 700,
            child: ExcludeSemantics(
              child: RepaintBoundary(child: LivingSummit()),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.x3),
              // LayoutBuilder + ConstrainedBox(minHeight) + IntrinsicHeight lets
              // the Spacers below keep distributing space exactly as before
              // when content fits, but makes the column scroll instead of
              // overflowing when it doesn't (e.g. large Dynamic Type on a
              // small screen).
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const ExcludeSemantics(
                                  child: LogoMark(size: 48, radius: 14),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Hustl',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              'The climb starts\nat base camp.',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                height: 1.05,
                                letterSpacing: -0.8,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.x2),
                            Text(
                              'Three quick steps set up your coach. Do them '
                              'in any order — or just lift.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.x3),
                            OnboardingTrailPlanCard(
                              showRecovery: !_webFallback,
                              onConnectRecovery: () => _handleConnect(context),
                              onStartWorkout: () => _handleStart(context),
                              onImportStrong: () => _handleImport(context),
                            ),
                            const SizedBox(height: AppSpacing.x3),
                            _WelcomePrimaryButton(
                              label: _webFallback
                                  ? 'Start your first workout'
                                  : 'Connect recovery data',
                              onPressed: () => _webFallback
                                  ? _handleStart(context)
                                  : _handleConnect(context),
                            ),
                            const SizedBox(height: AppSpacing.x1 + 4),
                            _WelcomeSecondaryButton(
                              label: _webFallback
                                  ? 'Bring your Strong history'
                                  : 'Start a workout first',
                              onPressed: () => _webFallback
                                  ? _handleImport(context)
                                  : _handleStart(context),
                            ),
                            const SizedBox(height: AppSpacing.x1),
                            Center(
                              child: TextButton(
                                onPressed: () => _handleSignIn(context),
                                child: Text(
                                  'I already have an account',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.x1),
                            const Center(
                              child: LegalLinksText(
                                leading: 'By continuing you agree to our',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The screen's primary pill CTA — same visual weight regardless of which
/// label/handler the web-fallback branch wires up.
class _WelcomePrimaryButton extends StatelessWidget {
  const _WelcomePrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 54),
        textStyle: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillRadius),
      ),
      child: Text(label),
    );
  }
}

/// The screen's secondary outlined pill CTA — same visual weight regardless
/// of which label/handler the web-fallback branch wires up.
class _WelcomeSecondaryButton extends StatelessWidget {
  const _WelcomeSecondaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        foregroundColor: colors.onSurface,
        textStyle: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide(color: colors.outlineVariant),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillRadius),
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}
