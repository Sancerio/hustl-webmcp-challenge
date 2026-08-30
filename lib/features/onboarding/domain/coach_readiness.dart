import 'dart:math' as math;

/// Build-ready estimator for the "Coach readiness" score — a single 0..1 number
/// driven by how much the coach actually knows, weighted by DATA DEPTH (not just
/// how many pillars have any data). This is why a switcher who imports 142
/// Strong workouts reads as a big head start, while a brand-new user who logged
/// one set is just getting started.
class CoachReadiness {
  const CoachReadiness._();

  // Each pillar's share of full readiness. Workouts are the backbone the AI
  // reasons from, so they dominate; coaching (approving proposals) is the last
  // mile that confirms the loop.
  static const double _workouts = 0.50;
  static const double _nutrition = 0.25;
  static const double _health = 0.15;
  static const double _coaching = 0.10;

  /// Diminishing-returns curve: the first chunk of data moves readiness a lot,
  /// later data less. `saturateAt` is the count that fills that pillar.
  static double _depth(num count, num saturateAt) {
    if (count <= 0) return 0;
    // 1 - e^(-k * ratio): ~0.63 at the saturation point, asymptotic to 1.
    final ratio = count / saturateAt;
    return (1 - math.exp(-1.0 * ratio)).clamp(0.0, 1.0);
  }

  /// Overall readiness in [0, 1].
  static double estimate({
    int workouts = 0,
    int meals = 0,
    bool healthConnected = false,
    int approvedProposals = 0,
  }) {
    final w = _depth(workouts, 12); // ~12 sessions ≈ a known training pattern
    final n = _depth(meals, 14); // ~2 weeks of meals ≈ a known intake pattern
    final h = healthConnected ? 1.0 : 0.0;
    final c = _depth(approvedProposals, 3); // a few approvals ≈ a working loop
    return (w * _workouts + n * _nutrition + h * _health + c * _coaching).clamp(
      0.0,
      1.0,
    );
  }

  static int estimatePercent({
    int workouts = 0,
    int meals = 0,
    bool healthConnected = false,
    int approvedProposals = 0,
  }) =>
      (estimate(
                workouts: workouts,
                meals: meals,
                healthConnected: healthConnected,
                approvedProposals: approvedProposals,
              ) *
              100)
          .round();
}
