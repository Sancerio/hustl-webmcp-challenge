import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/coaching/recovery_explain_facts.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';

// PHI GUARD — the headline constraint. The recovery snapshot co-locates SAFE
// derived scores with RAW BIOMETRICS. recoveryExplainFacts must be a STRICT
// WHITELIST: only derived, PII-safe fields + vetted copy may travel; NO raw
// biometric (hrv ms / resting HR bpm / respiratory rate / blood oxygen /
// temperature / raw sleep minutes / steps / active energy / raw training load)
// may appear in the produced map, by KEY or by VALUE.

// The EXACT whitelist the backend RecoveryFacts schema accepts. The mapper's keys
// must equal this set — nothing more, nothing less.
const _whitelistKeys = {
  'readinessScore',
  'recoveryScore',
  'band',
  'confidence',
  'strainScore',
  'sleepPerformanceScore',
  'sleepConsistencyScore',
  'baselineCoverageDays',
  'isCalibrating',
  'calibrationDaysRemaining',
  'loadRatio',
  'anomalyFlags',
  'headline',
  'guidance',
  'anomalyNote',
  'whyItMatters',
};

// Forbidden raw-biometric snapshot fields that must NEVER appear as a key.
const _forbiddenKeys = {
  'hrvValue',
  'hrvKind',
  'restingHeartRateBpm',
  'respiratoryRate',
  'bloodOxygenPercent',
  'temperatureCelsius',
  'temperatureDeltaCelsius',
  'remSleepMinutes',
  'deepSleepMinutes',
  'lightSleepMinutes',
  'awakeMinutes',
  'sleepDurationMinutes',
  'timeInBedMinutes',
  'sleepNeedMinutes',
  'sleepEfficiency',
  'steps',
  'activeEnergyKilocalories',
  'exerciseMinutes',
  'trainingLoad',
  'acuteLoad7',
  'chronicLoad42',
};

// A snapshot carrying BOTH the safe derived scores AND every raw biometric, with
// DISTINCTIVE raw values (>= 200, multi-digit) so a leak would be unmistakable.
DailyRecoverySnapshot _snapshotWithRawBiometrics() {
  return DailyRecoverySnapshot(
    date: DateTime(2026, 6, 19),
    // Derived, safe scores.
    recoveryScore: 78,
    readinessScore: 78,
    strainScore: 12,
    sleepPerformanceScore: 84,
    sleepConsistencyScore: 70,
    baselineCoverageDays: 30,
    isCalibrating: false,
    flowBand: RecoveryFlowBand.ready,
    confidence: RecoveryConfidence.high,
    loadRatio: 1,
    anomalyFlags: const [],
    // RAW biometrics — must NEVER leak. Distinctive large values.
    hrvValue: 634,
    hrvKind: HrvKind.rmssd,
    restingHeartRateBpm: 582,
    respiratoryRate: 147,
    bloodOxygenPercent: 973,
    temperatureCelsius: 366,
    temperatureDeltaCelsius: 204,
    remSleepMinutes: 288,
    deepSleepMinutes: 276,
    lightSleepMinutes: 233,
    awakeMinutes: 219,
    sleepDurationMinutes: 397,
    timeInBedMinutes: 416,
    sleepNeedMinutes: 480,
    sleepEfficiency: 555,
    steps: 8421,
    activeEnergyKilocalories: 612,
    exerciseMinutes: 247,
    trainingLoad: 311,
    acuteLoad7: 289,
    chronicLoad42: 264,
  );
}

void main() {
  group('recoveryExplainFacts PHI whitelist', () {
    test('produced map keys are EXACTLY the whitelist — no raw biometric key', () {
      final facts = recoveryExplainFacts(_snapshotWithRawBiometrics());

      expect(facts.keys.toSet(), _whitelistKeys);
      for (final key in _forbiddenKeys) {
        expect(
          facts.containsKey(key),
          isFalse,
          reason: 'PHI LEAK: raw biometric key "$key" reached RecoveryFacts',
        );
      }
    });

    test('no distinctive raw biometric VALUE appears anywhere in the map', () {
      final facts = recoveryExplainFacts(_snapshotWithRawBiometrics());

      // Flatten every value (incl. the anomalyFlags list) to strings.
      final emitted = <String>[];
      for (final v in facts.values) {
        if (v == null) continue;
        if (v is Iterable) {
          emitted.addAll(v.map((e) => '$e'));
        } else {
          emitted.add('$v');
        }
      }

      // The distinctive raw values that were on the snapshot.
      const rawValues = [
        '634', // hrv
        '582', // resting HR
        '147', // respiratory rate
        '973', // blood oxygen
        '366', // temperature
        '204', // temperature delta
        '288', '276', '233', '219', '397', '416', '480', '555', // sleep raw
        '8421', // steps
        '612', // active energy
        '247', // exercise minutes
        '311', '289', '264', // raw training loads
      ];
      for (final raw in rawValues) {
        expect(
          emitted,
          isNot(contains(raw)),
          reason: 'PHI LEAK: raw biometric value "$raw" reached RecoveryFacts',
        );
      }
    });

    test('carries the derived scores, band/confidence labels, and vetted copy', () {
      final facts = recoveryExplainFacts(_snapshotWithRawBiometrics());

      expect(facts['readinessScore'], 78);
      expect(facts['strainScore'], 12);
      expect(facts['sleepPerformanceScore'], 84);
      // band / confidence are LABEL strings, never raw signals or enums.
      expect(facts['band'], isA<String>());
      expect(facts['confidence'], isA<String>());
      expect((facts['headline'] as String).isNotEmpty, isTrue);
      expect((facts['guidance'] as String).isNotEmpty, isTrue);
    });

    test('a calibrating snapshot keeps the same whitelist keys (null scores ok)', () {
      final calibrating = DailyRecoverySnapshot(
        date: DateTime(2026, 6, 19),
        isCalibrating: true,
        baselineCoverageDays: 3,
      );
      final facts = recoveryExplainFacts(calibrating);
      expect(facts.keys.toSet(), _whitelistKeys);
      expect(facts['readinessScore'], isNull);
      expect(facts['isCalibrating'], isTrue);
    });
  });
  group('recoveryExplainResetKey', () {
    // A settled, gate-passing snapshot (so the affordance + reset key are live).
    // Parameterized so a single non-(readiness/band/strain) input can be varied
    // while everything else is held fixed.
    DailyRecoverySnapshot snap({
      RecoveryConfidence confidence = RecoveryConfidence.high,
      double? sleepConsistencyScore = 70,
      double? loadRatio = 1,
      List<String> anomalyFlags = const [],
      int baselineCoverageDays = 30,
    }) {
      return DailyRecoverySnapshot(
        date: DateTime(2026, 6, 19),
        recoveryScore: 78,
        readinessScore: 78,
        strainScore: 12,
        sleepPerformanceScore: 84,
        sleepConsistencyScore: sleepConsistencyScore,
        baselineCoverageDays: baselineCoverageDays,
        isCalibrating: false,
        flowBand: RecoveryFlowBand.ready,
        confidence: confidence,
        loadRatio: loadRatio,
        anomalyFlags: anomalyFlags,
      );
    }

    String keyOf(DailyRecoverySnapshot s) =>
        recoveryExplainResetKey(recoveryExplainFacts(s));

    test('is stable for an unchanged snapshot', () {
      expect(keyOf(snap()), keyOf(snap()));
    });

    test('changes when confidence changes (not readiness/band/strain)', () {
      final a = snap();
      final b = snap(confidence: RecoveryConfidence.medium);
      // readiness, band, and strain are all identical between a and b.
      expect(a.readinessScore, b.readinessScore);
      expect(a.flowBand, b.flowBand);
      expect(a.strainScore, b.strainScore);
      // The OLD key (readiness:band:strain) would NOT have changed; the full-facts
      // key MUST, because confidence is part of the narrative inputs.
      expect(keyOf(a), isNot(keyOf(b)));
    });

    test('changes when a sleep sub-score changes', () {
      final a = snap();
      final b = snap(sleepConsistencyScore: 55);
      expect(a.readinessScore, b.readinessScore);
      expect(a.flowBand, b.flowBand);
      expect(a.strainScore, b.strainScore);
      expect(keyOf(a), isNot(keyOf(b)));
    });

    test('changes when the load ratio changes', () {
      expect(keyOf(snap()), isNot(keyOf(snap(loadRatio: 2))));
    });

    test('changes when anomaly flags appear (guidance/anomaly copy shifts)', () {
      final a = snap();
      final b = snap(anomalyFlags: const ['markers_off_baseline']);
      expect(a.readinessScore, b.readinessScore);
      expect(a.flowBand, b.flowBand);
      expect(a.strainScore, b.strainScore);
      expect(keyOf(a), isNot(keyOf(b)));
    });

    test('changes when calibration coverage changes', () {
      expect(keyOf(snap()), isNot(keyOf(snap(baselineCoverageDays: 31))));
    });
  });

}
