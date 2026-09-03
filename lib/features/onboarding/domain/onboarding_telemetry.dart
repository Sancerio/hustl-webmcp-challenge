import 'package:get_it/get_it.dart';

import '../../../core/services/analytics_service.dart';

/// Typed, PII-free funnel telemetry for the onboarding flow. A thin wrapper over
/// [AnalyticsService]: every method emits a stable event name with primitive,
/// enum-like props only — never free text, names, or identifiers.
///
/// Call sites use [OnboardingTelemetry.instance], which resolves the
/// DI-registered service or falls back to a safe no-op (tests / goldens), so a
/// telemetry call can never throw into a UI or auth flow.
class OnboardingTelemetry {
  OnboardingTelemetry(this._analytics);

  /// A no-op instance for contexts where DI isn't wired (tests, goldens).
  OnboardingTelemetry.disabled() : _analytics = null;

  final AnalyticsService? _analytics;

  /// The DI-registered instance, or a safe no-op when telemetry isn't wired.
  /// Never throws.
  static OnboardingTelemetry get instance {
    try {
      final getIt = GetIt.instance;
      if (getIt.isRegistered<OnboardingTelemetry>()) {
        return getIt<OnboardingTelemetry>();
      }
    } catch (_) {
      // Fall through to the no-op below.
    }
    return OnboardingTelemetry.disabled();
  }

  void _log(String name, [Map<String, Object?> props = const {}]) {
    _analytics?.logEvent(name, props: props);
  }

  // ---- Funnel ----
  void welcomeShown() => _log('onboarding_welcome_shown');

  /// [action] is one of 'connect' | 'start' | 'import' | 'signin'.
  void welcomeAction(String action) =>
      _log('onboarding_welcome_action', {'action': action});

  void firstWinShown() => _log('onboarding_first_win_shown');

  void importCompleted({required int workouts}) =>
      _log('onboarding_import_completed', {'workouts': workouts});

  /// [result] is one of 'connect' | 'later'.
  void healthPrimerResult(String result) =>
      _log('onboarding_health_primer_result', {'result': result});

  void proposalShown() => _log('onboarding_proposal_shown');

  void proposalApproved() => _log('onboarding_proposal_approved');

  void upgradePromptShown() => _log('onboarding_upgrade_prompt_shown');

  void upgradeLinked() => _log('onboarding_upgrade_linked');

  // ---- Migration-risk ----
  /// [kind] is one of 'guestUpgrade' | 'accountSwitch' | 'signOut'.
  void migrationApplied(String kind) =>
      _log('onboarding_migration_applied', {'kind': kind});

  void syncCursorReset(String scope) =>
      _log('onboarding_sync_cursor_reset', {'scope': scope});
}
