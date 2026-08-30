import '../../../core/services/preferences_service.dart';
import 'coach_readiness_service.dart';

/// Decides whether to surface the onboarding "AI magic moment" (the starter
/// proposal at `/onboarding/proposal`). Kept as a tiny, pure-ish service so the
/// trigger logic is unit-testable and the call sites stay a one-liner.
///
/// Eligibility is deliberately conservative (low-risk): the moment only fires
/// when it will feel earned and the backend will almost certainly have enough to
/// draft from — so it never nags an empty account or dead-ends on
/// `not_enough_data`.
class OnboardingProposalGate {
  OnboardingProposalGate({
    required this.preferences,
    required this.readinessService,
  });

  final PreferencesService preferences;
  final CoachReadinessService readinessService;

  /// Coach-readiness floor for the magic moment. Tuned against
  /// [CoachReadiness.estimate]: a lifter with a handful of logged sessions (or
  /// fewer sessions plus connected Health / logged meals) clears it, while a
  /// near-empty account does not — so the draft reads as earned, not premature.
  /// The backend remains the authority on "enough data"; this just avoids
  /// prompting too early. One-line tunable.
  static const double readinessThreshold = 0.15;

  /// Minimum completed workouts so this is NEVER the user's first session (the
  /// first session already has its own "first win" celebration).
  static const int minCompletedWorkouts = 2;

  /// True when the magic moment should be surfaced: not yet seen, the user has
  /// more than one completed workout (not session 1), and the coach is ready
  /// enough. Degrades to `false` on any readiness-read failure (never throws).
  Future<bool> isEligible() async {
    if (preferences.onboardingProposalSeen) return false;
    try {
      final snapshot = await readinessService.snapshot();
      if (snapshot.workouts < minCompletedWorkouts) return false;
      return snapshot.readiness >= readinessThreshold;
    } catch (_) {
      return false;
    }
  }
}
