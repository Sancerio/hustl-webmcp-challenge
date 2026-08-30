import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/health_sync/domain/models/daily_health_summary.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/domain/usecases/derive_health_insights.dart';

void main() {
  group('DeriveHealthInsightsUseCase', () {
    const baseMacros = DailyMacroBreakdown(
      calories: 0,
      proteinGrams: 0,
      carbsGrams: 0,
      fatGrams: 0,
    );

    DailyMacroBreakdown macrosWithWater(double waterLiters) {
      return DailyMacroBreakdown(
        calories: 0,
        proteinGrams: 0,
        carbsGrams: 0,
        fatGrams: 0,
        waterLiters: waterLiters,
      );
    }

    DailyHealthSummary summary(DateTime date, {DailyMacroBreakdown? macros}) {
      return DailyHealthSummary(
        date: date,
        latestWeightKg: 80,
        metrics: const [],
        nutritionLogs: const [],
        macros: macros ?? baseMacros,
      );
    }

    test(
      'does not show hydration opportunity when no hydration data exists',
      () {
        final useCase = DeriveHealthInsightsUseCase();
        final summaries = List.generate(
          7,
          (i) => summary(DateTime(2025, 1, i + 1)),
        );

        final insights = useCase(summaries);

        expect(insights.any((i) => i.title.contains('Hydration')), isFalse);
      },
    );

    test('shows hydration insights when hydration data exists', () {
      final useCase = DeriveHealthInsightsUseCase();
      final summaries = <DailyHealthSummary>[
        summary(DateTime(2025, 1, 1), macros: macrosWithWater(2.2)),
        summary(DateTime(2025, 1, 2), macros: macrosWithWater(1.5)),
        summary(DateTime(2025, 1, 3), macros: macrosWithWater(1.0)),
      ];

      final insights = useCase(summaries);

      expect(insights.any((i) => i.title.contains('Hydration')), isTrue);
    });

    test('surfaces readiness insight when recovery snapshot is low', () {
      final useCase = DeriveHealthInsightsUseCase();
      final summaries = [summary(DateTime(2025, 1, 1))];

      final insights = useCase(
        summaries,
        recoverySnapshots: [
          DailyRecoverySnapshot(
            date: DateTime(2025, 1, 1),
            readinessScore: 52,
            recoveryScore: 55,
            sleepDurationMinutes: 360,
            sleepNeedMinutes: 480,
          ),
        ],
      );

      // A readiness of 52 maps to the "Steady" four-band, surfaced with kind,
      // band-aware copy and a non-alarmist (info) severity.
      final steady = insights.firstWhere(
        (i) => i.title.contains('Steady'),
        orElse: () => throw StateError('expected a Steady readiness insight'),
      );
      expect(steady.severity, HealthInsightSeverity.info);
      expect(steady.message, contains('A bit below your usual.'));
      expect(steady.message, contains('readiness 52/100'));
      final sleepShort = insights.firstWhere(
        (i) => i.title.contains('Sleep came in short'),
        orElse: () => throw StateError('expected a sleep-short insight'),
      );
      // New copy cites "your usual {N}h" (the personalized need), never a
      // "recent need", and reports the gap. 6.0h slept vs 8.0h usual => 2.0h gap.
      expect(sleepShort.message, contains('your usual'));
      expect(sleepShort.message, isNot(contains('recent need')));
      expect(sleepShort.message, contains('You slept 6.0h'));
      expect(sleepShort.message, contains('2.0h under your usual 8.0h'));
    });

    test(
      'surfaces a calibrating note while the baseline is still building',
      () {
        final useCase = DeriveHealthInsightsUseCase();
        final summaries = [summary(DateTime(2025, 1, 1))];

        final insights = useCase(
          summaries,
          recoverySnapshots: [
            DailyRecoverySnapshot(
              date: DateTime(2025, 1, 1),
              readinessScore: 61,
              recoveryScore: 60,
              sleepDurationMinutes: 430,
              sleepNeedMinutes: 480,
              flowBand: RecoveryFlowBand.ready,
              confidence: RecoveryConfidence.low,
              baselineCoverageDays: 4,
              isCalibrating: true,
            ),
          ],
        );

        final calibrating = insights.firstWhere(
          (i) => i.title.contains('Building your readiness baseline'),
          orElse: () =>
              throw StateError('expected a calibrating readiness insight'),
        );
        expect(calibrating.severity, HealthInsightSeverity.info);
        // Never leads with a hard band claim while calibrating.
        expect(insights.any((i) => i.title.contains('Ready today')), isFalse);
      },
    );

    test(
      'surfaces calibration when vitals are present but the score is withheld',
      () {
        // Regression for PR #393 [P2]: HRV/RHR are flowing (hasRecoveryData is
        // true) but the baseline is not ready, so the model withholds the score
        // (readinessScore == null). The user must see a "building your baseline"
        // calibration state, never the unrelated "All clear" fallback.
        final useCase = DeriveHealthInsightsUseCase();
        final summaries = [summary(DateTime(2025, 1, 1))];

        final insights = useCase(
          summaries,
          recoverySnapshots: [
            DailyRecoverySnapshot(
              date: DateTime(2025, 1, 1),
              // Vitals present -> hasRecoveryData == true.
              hrvValue: 55,
              restingHeartRateBpm: 58,
              // Score withheld because the baseline isn't ready yet.
              readinessScore: null,
              recoveryScore: null,
              flowBand: null,
              baselineCoverageDays: 2,
              isCalibrating: true,
            ),
          ],
        );

        final calibrating = insights.firstWhere(
          (i) => i.title.contains('Building your readiness baseline'),
          orElse: () => throw StateError(
            'expected a signal-present calibration insight',
          ),
        );
        expect(calibrating.severity, HealthInsightSeverity.info);
        // Must NOT fall through to the unrelated "All clear" copy, and must not
        // fabricate a hard readiness number while the score is withheld.
        expect(insights.any((i) => i.title.contains('All clear')), isFalse);
        // No fabricated hard number while the score is withheld.
        expect(calibrating.message, isNot(contains('/100')));
      },
    );

    test(
      'no sleep-short insight for a 7.5h sleeper whose usual is 7.5h',
      () {
        // The original bug: 7.5h slept flagged as short against an inflated
        // ~9.5h need. With a personalized 7.5h need, 7.5h is on target — no flag.
        final useCase = DeriveHealthInsightsUseCase();
        final summaries = [summary(DateTime(2025, 1, 1))];

        final insights = useCase(
          summaries,
          recoverySnapshots: [
            DailyRecoverySnapshot(
              date: DateTime(2025, 1, 1),
              readinessScore: 70,
              recoveryScore: 66,
              sleepDurationMinutes: 450, // 7.5h
              sleepNeedMinutes: 455, // personalized ~7.5h base + small load
              flowBand: RecoveryFlowBand.ready,
            ),
          ],
        );

        expect(
          insights.any((i) => i.title.contains('Sleep came in short')),
          isFalse,
        );
      },
    );

    test('a genuinely short night (<6h) warns even when need is low', () {
      // Low personalized need (7.0h) but only 5.5h slept: the absolute 6h floor
      // fires with a warning regardless of band.
      final useCase = DeriveHealthInsightsUseCase();
      final summaries = [summary(DateTime(2025, 1, 1))];

      final insights = useCase(
        summaries,
        recoverySnapshots: [
          DailyRecoverySnapshot(
            date: DateTime(2025, 1, 1),
            readinessScore: 82,
            recoveryScore: 80,
            sleepDurationMinutes: 330, // 5.5h
            sleepNeedMinutes: 420, // 7.0h
            flowBand: RecoveryFlowBand.charged,
          ),
        ],
      );

      final sleepShort = insights.firstWhere(
        (i) => i.title.contains('Sleep came in short'),
        orElse: () => throw StateError('expected a sleep-short insight'),
      );
      // Absolute floor always warns, even for a well-recovered (charged) day.
      expect(sleepShort.severity, HealthInsightSeverity.warning);
    });

    test(
      'a well-recovered, slightly-short night downgrades to info tone',
      () {
        // Only the relative -0.75 slack fires (6.75h vs 7.75h need, never < 6h)
        // and the band is ready => info, not warning.
        final useCase = DeriveHealthInsightsUseCase();
        final summaries = [summary(DateTime(2025, 1, 1))];

        final insights = useCase(
          summaries,
          recoverySnapshots: [
            DailyRecoverySnapshot(
              date: DateTime(2025, 1, 1),
              readinessScore: 68,
              recoveryScore: 66,
              sleepDurationMinutes: 405, // 6.75h
              sleepNeedMinutes: 465, // 7.75h
              flowBand: RecoveryFlowBand.ready,
            ),
          ],
        );

        final sleepShort = insights.firstWhere(
          (i) => i.title.contains('Sleep came in short'),
          orElse: () => throw StateError('expected a sleep-short insight'),
        );
        expect(sleepShort.severity, HealthInsightSeverity.info);
      },
    );

    test('the debt line is appended when weekly sleep debt is building', () {
      // Seven snapshots each ~2h under their own personalized need => weekly
      // debt well over 60 min => the "earlier night" line is appended.
      final useCase = DeriveHealthInsightsUseCase();
      final summaries = [summary(DateTime(2025, 1, 7))];
      final snapshots = [
        for (var i = 0; i < 7; i++)
          DailyRecoverySnapshot(
            date: DateTime(2025, 1, 1 + i),
            readinessScore: 50,
            recoveryScore: 50,
            sleepDurationMinutes: 360, // 6.0h
            sleepNeedMinutes: 480, // 8.0h => 2h short each night
          ),
      ];

      final insights = useCase(summaries, recoverySnapshots: snapshots);

      final sleepShort = insights.firstWhere(
        (i) => i.title.contains('Sleep came in short'),
        orElse: () => throw StateError('expected a sleep-short insight'),
      );
      expect(sleepShort.message, contains('Sleep debt is building this week'));
    });

    test('anomaly markers read as off baseline, never as illness', () {
      final useCase = DeriveHealthInsightsUseCase();
      final summaries = [summary(DateTime(2025, 1, 1))];

      final insights = useCase(
        summaries,
        recoverySnapshots: [
          DailyRecoverySnapshot(
            date: DateTime(2025, 1, 1),
            readinessScore: 70,
            recoveryScore: 66,
            sleepDurationMinutes: 430,
            flowBand: RecoveryFlowBand.ready,
            confidence: RecoveryConfidence.high,
            anomalyFlags: const ['elevated_resting_hr', 'low_hrv'],
          ),
        ],
      );

      final anomaly = insights.firstWhere(
        (i) => i.title.contains('off baseline'),
        orElse: () => throw StateError('expected an off-baseline insight'),
      );
      expect(anomaly.severity, HealthInsightSeverity.info);
      expect(anomaly.message.toLowerCase(), isNot(contains('sick')));
      expect(anomaly.message.toLowerCase(), isNot(contains('illness')));
    });
  });
}
