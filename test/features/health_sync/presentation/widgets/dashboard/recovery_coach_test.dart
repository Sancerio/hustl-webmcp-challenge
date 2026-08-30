import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/coaching/coach_insight.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/dashboard/recovery_coach.dart';

void main() {
  DailyRecoverySnapshot snap({
    RecoveryFlowBand? band,
    bool calibrating = false,
    int coverage = 14,
    List<String> anomalies = const [],
  }) => DailyRecoverySnapshot(
    date: DateTime(2026, 1, 1),
    readinessScore: 70,
    flowBand: band,
    isCalibrating: calibrating,
    baselineCoverageDays: coverage,
    anomalyFlags: anomalies,
  );

  group('recoveryCoachInsight', () {
    test('no snapshot → calibrating headline, neutral tone', () {
      final insight = recoveryCoachInsight(null);
      expect(insight.headline, 'Building your baseline');
      expect(insight.tone, CoachTone.neutral);
      // Confidence + learn-more live on the recovery hero ring, not the card.
      expect(insight.confidence, CoachConfidence.none);
      expect(insight.action, isNull);
    });

    test('charged → positive tone, with a plain-language why-it-matters', () {
      final insight = recoveryCoachInsight(
        snap(band: RecoveryFlowBand.charged),
      );
      expect(insight.headline, "You're well recovered.");
      expect(insight.tone, CoachTone.positive);
      expect(insight.why, contains('harder session'));
    });

    test('recharge → attention (amber), never red', () {
      final insight = recoveryCoachInsight(
        snap(band: RecoveryFlowBand.recharge),
      );
      expect(insight.tone, CoachTone.attention);
      expect(insight.why, contains('recovery work pays off'));
    });

    test('calibrating → neutral tone, no why-it-matters appended', () {
      final insight = recoveryCoachInsight(
        snap(band: RecoveryFlowBand.ready, calibrating: true, coverage: 3),
      );
      expect(insight.tone, CoachTone.neutral);
      expect(insight.why, isNot(contains('harder session')));
    });

    test('an anomaly forces attention tone even on a good band', () {
      final insight = recoveryCoachInsight(
        snap(band: RecoveryFlowBand.charged, anomalies: const ['hrv_drop']),
      );
      expect(insight.tone, CoachTone.attention);
    });
  });
}
