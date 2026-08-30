import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/coaching/coach_insight.dart';
import 'package:hustl_app/features/workout_log/domain/models/muscle_group.dart';
import 'package:hustl_app/features/workout_logging/domain/services/next_workout_focus_service.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/training_balance_coach.dart';

NextWorkoutFocusPlan _plan(
  NextWorkoutFocusTone tone, {
  CoachConfidence confidence = CoachConfidence.high,
  String windowLabel = 'last 4 weeks',
}) => NextWorkoutFocusPlan(
  headline: 'Add 3 chest sets this week',
  detail: 'Chest is 45% of its weekly goal.',
  statusLabel: 'Build',
  primaryRegion: DisplayRegion.chest,
  primaryPercent: 45,
  exerciseSuggestions: const [],
  tone: tone,
  confidence: confidence,
  windowLabel: windowLabel,
);

void main() {
  group('trainingBalanceInsight', () {
    test('carries the plan headline + detail and a destination-labelled action', () {
      final insight = trainingBalanceInsight(
        _plan(NextWorkoutFocusTone.build),
        onSeeDetails: () {},
      );
      expect(insight.headline, 'Add 3 chest sets this week');
      expect(insight.why, 'Chest is 45% of its weekly goal.');
      // The action opens the Training-balance breakdown, so it's labelled for
      // that destination — never a "show exercises" view that doesn't exist.
      expect(insight.action?.label, 'See training balance');
    });

    test('build/rebalance read as an amber attention nudge; confidence + '
        'window come straight from the plan', () {
      for (final tone in [
        NextWorkoutFocusTone.build,
        NextWorkoutFocusTone.rebalance,
      ]) {
        final insight = trainingBalanceInsight(
          _plan(
            tone,
            confidence: CoachConfidence.high,
            windowLabel: 'last full month',
          ),
          onSeeDetails: () {},
        );
        expect(insight.tone, CoachTone.attention);
        // Confidence is whatever the plan derived — not hard-coded "high".
        expect(insight.confidence, CoachConfidence.high);
        // The window label tracks the plan's period, not a fixed "last 4 weeks".
        expect(insight.windowLabel, 'last full month');
      }
    });

    test('a derived medium confidence flows through unchanged', () {
      final insight = trainingBalanceInsight(
        _plan(NextWorkoutFocusTone.build, confidence: CoachConfidence.medium),
        onSeeDetails: () {},
      );
      expect(insight.confidence, CoachConfidence.medium);
      expect(insight.windowLabel, 'last 4 weeks');
    });

    test('balanced reads as positive (emerald)', () {
      final insight = trainingBalanceInsight(
        _plan(NextWorkoutFocusTone.balanced),
        onSeeDetails: () {},
      );
      expect(insight.tone, CoachTone.positive);
    });

    test('a building-confidence plan is neutral-toned and hides its window', () {
      final insight = trainingBalanceInsight(
        _plan(
          NextWorkoutFocusTone.earlySignal,
          confidence: CoachConfidence.building,
        ),
        onSeeDetails: () {},
      );
      expect(insight.tone, CoachTone.neutral);
      expect(insight.confidence, CoachConfidence.building);
      // A still-building read is an early signal, not a settled window claim.
      expect(insight.windowLabel, isNull);
    });

    test('no exercise prescription => action labels its destination, not '
        '"show exercises"', () {
      // Early-signal ("log more first") and balanced reads prescribe nothing, so
      // the action must not promise exercises that aren't there.
      for (final tone in [
        NextWorkoutFocusTone.earlySignal,
        NextWorkoutFocusTone.balanced,
      ]) {
        final insight = trainingBalanceInsight(_plan(tone), onSeeDetails: () {});
        expect(insight.action?.label, 'See training balance');
      }
    });
  });
}
