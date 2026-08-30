import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/onboarding/domain/coach_readiness.dart';

void main() {
  group('CoachReadiness.estimate', () {
    test('returns 0 with no data at all', () {
      expect(CoachReadiness.estimate(), 0.0);
    });

    test('one workout reads as just getting started (low)', () {
      final r = CoachReadiness.estimate(workouts: 1);
      expect(r, greaterThan(0.0));
      expect(r, lessThan(0.1));
    });

    test('many workouts read as a big head start (high vs. one)', () {
      final one = CoachReadiness.estimate(workouts: 1);
      final many = CoachReadiness.estimate(workouts: 60);
      expect(many, greaterThan(one));
      // ~60 sessions saturates the workouts pillar, which is half the score.
      expect(many, greaterThan(0.45));
    });

    test('diminishing returns: later workouts move the needle less', () {
      final firstStep =
          CoachReadiness.estimate(workouts: 2) -
          CoachReadiness.estimate(workouts: 1);
      final laterStep =
          CoachReadiness.estimate(workouts: 21) -
          CoachReadiness.estimate(workouts: 20);
      expect(firstStep, greaterThan(laterStep));
    });

    test('healthConnected toggles its own band (~0.15)', () {
      final off = CoachReadiness.estimate(workouts: 10);
      final on = CoachReadiness.estimate(workouts: 10, healthConnected: true);
      final delta = on - off;
      expect(delta, closeTo(0.15, 1e-9));
    });

    test('a full picture approaches 1', () {
      final r = CoachReadiness.estimate(
        workouts: 60,
        meals: 60,
        healthConnected: true,
        approvedProposals: 12,
      );
      expect(r, greaterThan(0.9));
      expect(r, lessThanOrEqualTo(1.0));
    });

    test('estimatePercent mirrors estimate, rounded', () {
      const args = (workouts: 10, meals: 5, health: true, proposals: 1);
      final pct = CoachReadiness.estimatePercent(
        workouts: args.workouts,
        meals: args.meals,
        healthConnected: args.health,
        approvedProposals: args.proposals,
      );
      final expected =
          (CoachReadiness.estimate(
                    workouts: args.workouts,
                    meals: args.meals,
                    healthConnected: args.health,
                    approvedProposals: args.proposals,
                  ) *
                  100)
              .round();
      expect(pct, expected);
    });
  });
}
