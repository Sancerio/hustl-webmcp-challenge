import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/domain/usecases/recovery_flow_copy.dart';

DailyRecoverySnapshot _snapshot({
  RecoveryFlowBand? flowBand = RecoveryFlowBand.ready,
  RecoveryConfidence? confidence = RecoveryConfidence.high,
  bool isCalibrating = false,
  int? strainScore = 12,
  bool withData = true,
}) => DailyRecoverySnapshot(
  date: DateTime(2026, 6, 13),
  sleepPerformanceScore: withData ? 80 : null,
  hrvValue: withData ? 56 : null,
  hrvKind: HrvKind.sdnn,
  restingHeartRateBpm: withData ? 55 : null,
  readinessScore: 60,
  recoveryScore: 58,
  strainScore: strainScore,
  baselineCoverageDays: 21,
  band: flowBand?.legacyBand,
  flowBand: flowBand,
  confidence: confidence,
  isCalibrating: isCalibrating,
);

void main() {
  group('shouldSuggestMoreRest', () {
    test('suggests on the lowest band (Recharge)', () {
      expect(
        RecoveryFlowCopy.shouldSuggestMoreRest(
          _snapshot(flowBand: RecoveryFlowBand.recharge),
        ),
        isTrue,
      );
    });

    test('suggests on Steady when confidence is not low', () {
      expect(
        RecoveryFlowCopy.shouldSuggestMoreRest(
          _snapshot(
            flowBand: RecoveryFlowBand.steady,
            confidence: RecoveryConfidence.medium,
          ),
        ),
        isTrue,
      );
    });

    test(
      'does NOT suggest on Steady with low confidence (noisy single day)',
      () {
        expect(
          RecoveryFlowCopy.shouldSuggestMoreRest(
            _snapshot(
              flowBand: RecoveryFlowBand.steady,
              confidence: RecoveryConfidence.low,
            ),
          ),
          isFalse,
        );
      },
    );

    test('does NOT suggest on Ready / Charged', () {
      expect(
        RecoveryFlowCopy.shouldSuggestMoreRest(
          _snapshot(flowBand: RecoveryFlowBand.ready),
        ),
        isFalse,
      );
      expect(
        RecoveryFlowCopy.shouldSuggestMoreRest(
          _snapshot(flowBand: RecoveryFlowBand.charged),
        ),
        isFalse,
      );
    });

    test('does NOT suggest when null, calibrating, bandless, or dataless', () {
      expect(RecoveryFlowCopy.shouldSuggestMoreRest(null), isFalse);
      expect(
        RecoveryFlowCopy.shouldSuggestMoreRest(
          _snapshot(flowBand: RecoveryFlowBand.recharge, isCalibrating: true),
        ),
        isFalse,
      );
      expect(
        RecoveryFlowCopy.shouldSuggestMoreRest(_snapshot(flowBand: null)),
        isFalse,
      );
      expect(
        RecoveryFlowCopy.shouldSuggestMoreRest(
          _snapshot(flowBand: RecoveryFlowBand.recharge, withData: false),
        ),
        isFalse,
      );
    });
  });

  group('postWorkoutNote', () {
    test('renders nothing for null / low-confidence / calibrating', () {
      expect(RecoveryFlowCopy.postWorkoutNote(null), isNull);
      expect(
        RecoveryFlowCopy.postWorkoutNote(
          _snapshot(confidence: RecoveryConfidence.low),
        ),
        isNull,
      );
      expect(
        RecoveryFlowCopy.postWorkoutNote(_snapshot(isCalibrating: true)),
        isNull,
      );
      expect(
        RecoveryFlowCopy.postWorkoutNote(_snapshot(flowBand: null)),
        isNull,
      );
    });

    test('big session + low band → gentle lighter-day note', () {
      final note = RecoveryFlowCopy.postWorkoutNote(
        _snapshot(flowBand: RecoveryFlowBand.recharge, strainScore: 16),
      );
      expect(note, isNotNull);
      expect(note, contains('lighter day'));
      // Kind, non-medical: never alarmist.
      expect(note!.toLowerCase(), isNot(contains('risk')));
      expect(note.toLowerCase(), isNot(contains('injury')));
    });

    test('good band → quiet affirmation', () {
      final note = RecoveryFlowCopy.postWorkoutNote(
        _snapshot(flowBand: RecoveryFlowBand.ready, strainScore: 8),
      );
      expect(note, 'Solid work. You\'re recovering well.');
    });
  });
}
