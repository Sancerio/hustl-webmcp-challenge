import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/domain/models/health_metric_sample.dart';
import 'package:hustl_app/features/health_sync/domain/usecases/build_daily_recovery_snapshots.dart';

void main() {
  final useCase = BuildDailyRecoverySnapshotsUseCase();

  HealthMetricSample sample({
    required HealthMetricType type,
    required double value,
    required DateTime at,
    String unit = '',
  }) {
    return HealthMetricSample(
      type: type,
      value: value,
      unit: unit.isEmpty ? type.preferredUnit : unit,
      startTime: at,
      endTime: at.add(const Duration(minutes: 1)),
      source: 'watch',
    );
  }

  test(
    'builds readiness snapshots from sleep, vitals, and activity samples',
    () {
      final metrics = <HealthMetricSample>[
        sample(
          type: HealthMetricType.sleepAsleep,
          value: 430,
          at: DateTime(2025, 1, 1, 7),
        ),
        sample(
          type: HealthMetricType.sleepInBed,
          value: 470,
          at: DateTime(2025, 1, 1, 7),
        ),
        sample(
          type: HealthMetricType.heartRateVariabilitySdnn,
          value: 52,
          at: DateTime(2025, 1, 1, 7),
        ),
        sample(
          type: HealthMetricType.restingHeartRate,
          value: 58,
          at: DateTime(2025, 1, 1, 7),
        ),
        sample(
          type: HealthMetricType.activeEnergyBurned,
          value: 540,
          at: DateTime(2025, 1, 1, 18),
        ),
        sample(
          type: HealthMetricType.steps,
          value: 9100,
          at: DateTime(2025, 1, 1, 20),
        ),
        sample(
          type: HealthMetricType.sleepAsleep,
          value: 470,
          at: DateTime(2025, 1, 2, 7),
        ),
        sample(
          type: HealthMetricType.sleepInBed,
          value: 500,
          at: DateTime(2025, 1, 2, 7),
        ),
        sample(
          type: HealthMetricType.heartRateVariabilitySdnn,
          value: 60,
          at: DateTime(2025, 1, 2, 7),
        ),
        sample(
          type: HealthMetricType.restingHeartRate,
          value: 54,
          at: DateTime(2025, 1, 2, 7),
        ),
        sample(
          type: HealthMetricType.respiratoryRate,
          value: 14,
          at: DateTime(2025, 1, 2, 7),
        ),
        sample(
          type: HealthMetricType.activeEnergyBurned,
          value: 620,
          at: DateTime(2025, 1, 2, 18),
        ),
        sample(
          type: HealthMetricType.exerciseTime,
          value: 75,
          at: DateTime(2025, 1, 2, 18),
        ),
        sample(
          type: HealthMetricType.steps,
          value: 11200,
          at: DateTime(2025, 1, 2, 20),
        ),
      ];

      final snapshots = useCase(metrics: metrics);

      expect(snapshots, hasLength(2));
      final latest = snapshots.last;
      expect(latest.date, DateTime(2025, 1, 2));
      expect(latest.sleepDurationMinutes, 470);
      expect(latest.timeInBedMinutes, 500);
      expect(latest.hrvKind, HrvKind.sdnn);
      expect(latest.trainingLoad, greaterThan(0));
      expect(latest.strainScore, inInclusiveRange(0, 21));
      expect(latest.readinessScore, isNotNull);
      expect(latest.band, isA<RecoveryReadinessBand>());
    },
  );

  test('fills missing calendar days so load windows do not compress time', () {
    final metrics = <HealthMetricSample>[
      sample(
        type: HealthMetricType.activeEnergyBurned,
        value: 500,
        at: DateTime(2025, 1, 1, 18),
      ),
      sample(
        type: HealthMetricType.activeEnergyBurned,
        value: 500,
        at: DateTime(2025, 1, 3, 18),
      ),
    ];

    final snapshots = useCase(metrics: metrics);

    expect(snapshots.map((snapshot) => snapshot.date), [
      DateTime(2025, 1, 1),
      DateTime(2025, 1, 2),
      DateTime(2025, 1, 3),
    ]);
    expect(snapshots[1].trainingLoad, 0);
    expect(snapshots[2].acuteLoad7, lessThan(snapshots[0].trainingLoad!));
  });

  // ---- R1 phase 1: robust baselines, weights, caps, confidence, bands ----

  tearDown(HrvPlatform.debugReset);

  /// Builds [days] of HRV samples on consecutive nights, the last being [last].
  List<HealthMetricSample> hrvSeries(List<double> values, {int startDay = 1}) {
    return [
      for (var i = 0; i < values.length; i++)
        sample(
          type: HealthMetricType.heartRateVariabilitySdnn,
          value: values[i],
          at: DateTime(2025, 1, startDay + i, 7),
        ),
    ];
  }

  group('robust median + MAD baseline', () {
    test('a single outlier night does not poison the baseline center', () {
      // 9 stable nights of HRV ~50 then a wild outlier on day 5 — the median
      // ignores it, so the final day (also ~50) scores near neutral, not low.
      final stable = [50.0, 51.0, 49.0, 50.0, 200.0, 50.0, 51.0, 49.0, 50.0];
      final withFinal = [...stable, 50.0];
      final snapshots = useCase(metrics: hrvSeries(withFinal));
      final last = snapshots.last;
      // A mean baseline would be pulled up by the 200 outlier and score the
      // final 50 as a big drop. The robust median keeps it near neutral.
      expect(last.recoveryScore, isNotNull);
      expect(last.recoveryScore, greaterThan(40));
      expect(last.recoveryScore, lessThan(60));
    });

    test('unbaselined signal is excluded, not pulled to a synthetic 50', () {
      // Day 1 and 2 only — day 2 has <3 priors, so there is no HRV baseline.
      // The HRV sub-score is excluded (null) rather than substituting 50, and
      // with no other baselined signal the HRV-only recovery is null.
      final snapshots = useCase(metrics: hrvSeries([55.0, 60.0]));
      expect(snapshots, hasLength(2));
      expect(snapshots.last.recoveryScore, isNull);
    });

    test('deviation is clamped to +/-3 MAD so a spike cannot zero the score', () {
      // Tight baseline (spread small), then a huge final-day HRV spike.
      final values = [50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 5000.0];
      final snapshots = useCase(metrics: hrvSeries(values));
      // HRV higher is better and clamped at +3 MAD => 50 + 3*16 = 98, not 100+.
      expect(snapshots.last.recoveryScore, lessThanOrEqualTo(98));
      expect(snapshots.last.recoveryScore, greaterThan(90));
    });
  });

  group('HRV-led renormalized weights', () {
    test('a sleep-only user still gets a sleep-based recovery estimate', () {
      // Only sleep, for several nights. recoveryScore renormalizes onto sleep.
      final metrics = <HealthMetricSample>[
        for (var i = 0; i < 6; i++)
          sample(
            type: HealthMetricType.sleepAsleep,
            value: 470,
            at: DateTime(2025, 2, 1 + i, 7),
          ),
      ];
      final snapshots = useCase(metrics: metrics);
      final last = snapshots.last;
      expect(last.hrvValue, isNull);
      expect(last.restingHeartRateBpm, isNull);
      expect(last.recoveryScore, isNotNull);
      expect(last.recoveryScore, greaterThan(0));
      // Sleep-only is low confidence.
      expect(last.confidence, RecoveryConfidence.low);
    });
  });

  group('illness cap (respiratory + temperature gate)', () {
    test('a fever day caps recovery below an otherwise-good score', () {
      // Strong HRV every night so base recovery is high; raise body temp on the
      // final day well above baseline to trigger the illness cap.
      final metrics = <HealthMetricSample>[];
      for (var i = 0; i < 8; i++) {
        final day = DateTime(2025, 3, 1 + i, 7);
        metrics
          ..add(
            sample(
              type: HealthMetricType.heartRateVariabilitySdnn,
              value: 70,
              at: day,
            ),
          )
          ..add(sample(type: HealthMetricType.sleepAsleep, value: 470, at: day))
          ..add(
            sample(
              type: HealthMetricType.bodyTemperature,
              // Stable 36.6C baseline, then +0.8C on the final day.
              value: i == 7 ? 37.4 : 36.6,
              at: day,
            ),
          );
      }
      final snapshots = useCase(metrics: metrics);
      final feverDay = snapshots.last;
      final priorDay = snapshots[snapshots.length - 2];
      // The cap lowers the final day below the prior, healthy day.
      expect(feverDay.recoveryScore, lessThan(priorDay.recoveryScore!));
      expect(feverDay.recoveryScore, lessThanOrEqualTo(75));
      expect(feverDay.anomalyFlags, contains('elevated_temperature'));
    });
  });

  group('confidence levels', () {
    test('high confidence with HRV + RHR + sleep over a long baseline', () {
      final metrics = <HealthMetricSample>[];
      for (var i = 0; i < 16; i++) {
        final day = DateTime(2025, 4, 1 + i, 7);
        metrics
          ..add(
            sample(
              type: HealthMetricType.heartRateVariabilitySdnn,
              value: 55,
              at: day,
            ),
          )
          ..add(
            sample(type: HealthMetricType.restingHeartRate, value: 55, at: day),
          )
          ..add(
            sample(type: HealthMetricType.sleepAsleep, value: 470, at: day),
          );
      }
      final snapshots = useCase(metrics: metrics);
      expect(snapshots.last.confidence, RecoveryConfidence.high);
      expect(snapshots.last.isCalibrating, isFalse);
    });

    test('low confidence and calibrating early in the baseline', () {
      final metrics = <HealthMetricSample>[];
      for (var i = 0; i < 4; i++) {
        final day = DateTime(2025, 5, 1 + i, 7);
        metrics.add(
          sample(type: HealthMetricType.sleepAsleep, value: 470, at: day),
        );
      }
      final snapshots = useCase(metrics: metrics);
      expect(snapshots.last.confidence, RecoveryConfidence.low);
      expect(snapshots.last.isCalibrating, isTrue);
      expect(snapshots.last.calibrationDaysRemaining, greaterThan(0));
    });
  });

  group('four-band mapping', () {
    test('maps high/mid/low readiness to Charged/Steady/Recharge', () {
      // Drive readiness with HRV deviation: a strong final day -> Charged.
      final high = useCase(
        metrics: hrvSeries([50, 50, 50, 50, 50, 50, 50, 130]),
      );
      expect(high.last.flowBand, RecoveryFlowBand.charged);
      expect(high.last.flowBand!.displayLabel, 'Charged');
      expect(high.last.flowBand!.tintHint, RecoveryBandTint.vital);
      expect(high.last.band, RecoveryReadinessBand.high);

      // A weak final day (HRV well below baseline) -> Recharge, warm amber.
      final low = useCase(metrics: hrvSeries([60, 60, 60, 60, 60, 60, 60, 12]));
      expect(low.last.flowBand, RecoveryFlowBand.recharge);
      expect(low.last.flowBand!.displayLabel, 'Recharge');
      expect(low.last.flowBand!.tintHint, RecoveryBandTint.warmAmber);
      expect(low.last.band, RecoveryReadinessBand.low);
    });

    test('low confidence widens bands toward the gentle middle', () {
      // A borderline-low readiness (~33-39) on a thin (low-confidence) baseline
      // should not drop to Recharge; the widened low-confidence threshold
      // (Steady >= 32 instead of >= 40) keeps it in Steady.
      // Baseline [44,50,56] -> center 50, spread ~8.9; final 42 -> readiness ~36.
      final snapshots = useCase(metrics: hrvSeries([44, 50, 56, 42]));
      final last = snapshots.last;
      expect(last.confidence, RecoveryConfidence.low);
      expect(last.recoveryScore, inInclusiveRange(32, 40));
      expect(last.flowBand, RecoveryFlowBand.steady);
    });
  });

  group('HRV platform selection', () {
    test('iOS prefers SDNN and tags the kind', () {
      HrvPlatform.debugOverrideKind = HrvKind.sdnn;
      final metrics = <HealthMetricSample>[
        sample(
          type: HealthMetricType.heartRateVariabilitySdnn,
          value: 52,
          at: DateTime(2025, 6, 1, 7),
        ),
        sample(
          type: HealthMetricType.heartRateVariabilityRmssd,
          value: 40,
          at: DateTime(2025, 6, 1, 7),
        ),
      ];
      final snapshots = useCase(metrics: metrics);
      expect(snapshots.last.hrvKind, HrvKind.sdnn);
      expect(snapshots.last.hrvValue, 52);
    });

    test('Android prefers RMSSD and tags the kind', () {
      HrvPlatform.debugOverrideKind = HrvKind.rmssd;
      final metrics = <HealthMetricSample>[
        sample(
          type: HealthMetricType.heartRateVariabilitySdnn,
          value: 52,
          at: DateTime(2025, 6, 1, 7),
        ),
        sample(
          type: HealthMetricType.heartRateVariabilityRmssd,
          value: 40,
          at: DateTime(2025, 6, 1, 7),
        ),
      ];
      final snapshots = useCase(metrics: metrics);
      expect(snapshots.last.hrvKind, HrvKind.rmssd);
      expect(snapshots.last.hrvValue, 40);
    });

    test('baseline never mixes SDNN and RMSSD into one trend', () {
      HrvPlatform.debugOverrideKind = HrvKind.rmssd;
      // Several SDNN-only nights (ignored for the RMSSD baseline) then a single
      // RMSSD day: with no same-kind priors, the RMSSD day scores neutral (50)
      // rather than being compared against the SDNN history.
      final metrics = <HealthMetricSample>[
        for (var i = 0; i < 6; i++)
          sample(
            type: HealthMetricType.heartRateVariabilitySdnn,
            value: 90,
            at: DateTime(2025, 7, 1 + i, 7),
          ),
        sample(
          type: HealthMetricType.heartRateVariabilityRmssd,
          value: 30,
          at: DateTime(2025, 7, 7, 7),
        ),
      ];
      final snapshots = useCase(metrics: metrics);
      final last = snapshots.last;
      expect(last.hrvKind, HrvKind.rmssd);
      // No same-kind baseline => HRV sub-score is excluded (null), not compared
      // against the SDNN history; with no other baselined signal recovery is null.
      expect(last.recoveryScore, isNull);
    });
  });

  // ---- Recovery model tune (v2): personalized sleep need + strain decay ----

  group('personalized sleep need', () {
    test(
      'a 7.5h-on-a-normal-week sleeper gets a defensible need, never ~9.5h',
      () {
        // 28 habitual nights at 7.5h (450 min) with a normal-load day, then a
        // final 7.5h night. Need = habitual base (~450, clamped 420-540) + a
        // small load bump, never the old debt-inflated ~9.5h (570 min).
        final metrics = <HealthMetricSample>[];
        for (var i = 0; i < 29; i++) {
          final day = DateTime(2025, 8, 1).add(Duration(days: i));
          metrics
            ..add(
              sample(
                type: HealthMetricType.sleepAsleep,
                value: 450,
                at: DateTime(day.year, day.month, day.day, 7),
              ),
            )
            // Normal-week activity (~200 AU): 9k steps + 30 min exercise.
            ..add(
              sample(
                type: HealthMetricType.steps,
                value: 9000,
                at: DateTime(day.year, day.month, day.day, 12),
              ),
            )
            ..add(
              sample(
                type: HealthMetricType.exerciseTime,
                value: 30,
                at: DateTime(day.year, day.month, day.day, 18),
              ),
            );
        }
        final snapshots = useCase(metrics: metrics);
        final need = snapshots.last.sleepNeedMinutes!;
        // Personalized base ~450 + small load bump; bounded well under 9h.
        expect(need, inInclusiveRange(450, 495));
        expect(need, lessThan(540));
      },
    );

    test('cold start need is the personalized fallback, not a flat 8h', () {
      // First night ever: no qualifying baseline => 465 min (7.75h) + tiny load.
      final snapshots = useCase(metrics: hrvSeries([55.0]));
      final need = snapshots.first.sleepNeedMinutes!;
      expect(need, inInclusiveRange(465, 510));
    });

    test('a short night does NOT inflate the computed need', () {
      // 5 habitual 8h nights then a single 5h night: need stays anchored on the
      // habitual base, it does not jump up because the latest night was short.
      final metrics = <HealthMetricSample>[];
      for (var i = 0; i < 5; i++) {
        metrics.add(
          sample(
            type: HealthMetricType.sleepAsleep,
            value: 480,
            at: DateTime(2025, 9, 1 + i, 7),
          ),
        );
      }
      metrics.add(
        sample(
          type: HealthMetricType.sleepAsleep,
          value: 300,
          at: DateTime(2025, 9, 6, 7),
        ),
      );
      final snapshots = useCase(metrics: metrics);
      // Need on the short night ~= habitual base (~480), with no load bump.
      expect(snapshots.last.sleepNeedMinutes, inInclusiveRange(420, 500));
    });
  });

  group('strain score discrimination', () {
    test('a light day scores lower strain than a hard day', () {
      final lightDay = useCase(
        metrics: [
          sample(
            type: HealthMetricType.steps,
            value: 2000,
            at: DateTime(2025, 10, 1, 12),
          ),
        ],
      ).last;
      final hardDay = useCase(
        metrics: [
          sample(
            type: HealthMetricType.activeEnergyBurned,
            value: 900,
            at: DateTime(2025, 10, 1, 18),
          ),
          sample(
            type: HealthMetricType.exerciseTime,
            value: 120,
            at: DateTime(2025, 10, 1, 18),
          ),
          sample(
            type: HealthMetricType.steps,
            value: 15000,
            at: DateTime(2025, 10, 1, 20),
          ),
        ],
      ).last;
      expect(lightDay.strainScore, inInclusiveRange(0, 21));
      expect(hardDay.strainScore, inInclusiveRange(0, 21));
      expect(lightDay.strainScore!, lessThan(hardDay.strainScore!));
      // The light day stays well off full scale (meter is not pinned).
      expect(lightDay.strainScore!, lessThan(9));
    });
  });

  group('typical strain baseline', () {
    // A day carrying `energy` kcal of active energy (and nothing else), whose
    // training load is `energy * 0.08` per _computeTrainingLoad.
    HealthMetricSample energyDay(double energy, DateTime day) => sample(
      type: HealthMetricType.activeEnergyBurned,
      value: energy,
      at: DateTime(day.year, day.month, day.day, 18),
    );

    test('is the strain of the MEDIAN prior training load', () {
      // 10 prior days at a steady ~250 AU load (energy 3125 * 0.08 = 250) then a
      // hard final day. The typical on the final day maps the median prior load
      // (250) through the same strain formula: strainScoreForLoad(250) = 13.
      final metrics = <HealthMetricSample>[
        for (var i = 0; i < 10; i++)
          energyDay(3125, DateTime(2025, 11, 1).add(Duration(days: i))),
        energyDay(7000, DateTime(2025, 11, 11)),
      ];
      final snapshots = useCase(metrics: metrics);
      final last = snapshots.last;
      expect(
        last.typicalStrainScore,
        BuildDailyRecoverySnapshotsUseCase.strainScoreForLoad(250),
      );
      // And that typical reflects the priors, NOT the hard final day's strain.
      expect(last.typicalStrainScore, lessThan(last.strainScore!));
    });

    test('is null with fewer than 7 qualifying prior days', () {
      // 6 prior reading-days + the final day => only 6 priors, below the floor.
      final metrics = <HealthMetricSample>[
        for (var i = 0; i < 6; i++)
          energyDay(3125, DateTime(2025, 11, 1).add(Duration(days: i))),
        energyDay(3125, DateTime(2025, 11, 7)),
      ];
      final snapshots = useCase(metrics: metrics);
      expect(snapshots.last.typicalStrainScore, isNull);
      // The 8th reading-day (7 priors) is the first to earn a typical.
      final withSeventh = useCase(
        metrics: [...metrics, energyDay(3125, DateTime(2025, 11, 8))],
      );
      expect(withSeventh.last.typicalStrainScore, isNotNull);
    });

    test("excludes today's own load from its typical", () {
      // 7 priors whose loads are 100,100,100,300,900,900,900 AU (median 300),
      // then a hard final day at 900 AU. If the final day leaked into its own
      // typical the 8-value median would be 600 (a different strain); because it
      // is excluded, the typical is the priors' median-300 strain.
      final loads = <double>[100, 100, 100, 300, 900, 900, 900, 900];
      final metrics = <HealthMetricSample>[
        for (var i = 0; i < loads.length; i++)
          // energy * 0.08 = load  =>  energy = load / 0.08.
          energyDay(
            loads[i] / 0.08,
            DateTime(2025, 11, 1).add(Duration(days: i)),
          ),
      ];
      final last = useCase(metrics: metrics).last;
      expect(
        last.typicalStrainScore,
        BuildDailyRecoverySnapshotsUseCase.strainScoreForLoad(300),
      );
      expect(
        last.typicalStrainScore,
        isNot(BuildDailyRecoverySnapshotsUseCase.strainScoreForLoad(600)),
      );
    });

    test('skips zero-filled gap days rather than counting them as rest', () {
      // 8 real reading-days spread across a 2-week span with calendar GAPS in
      // between (the aggregator zero-fills those). Zero-filled days must NOT
      // count toward the typical — if they did, the median would collapse to ~0.
      // Every other day carries a ~250 AU reading; the between-days are gaps.
      final metrics = <HealthMetricSample>[
        for (var i = 0; i < 9; i++)
          energyDay(3125, DateTime(2025, 11, 1).add(Duration(days: i * 2))),
      ];
      final snapshots = useCase(metrics: metrics);
      // Many zero-filled gap days exist between the readings...
      expect(snapshots.where((s) => s.trainingLoad == 0), isNotEmpty);
      final last = snapshots.last;
      // ...but the typical is the strain of the 250-AU median reading, not ~0.
      expect(
        last.typicalStrainScore,
        BuildDailyRecoverySnapshotsUseCase.strainScoreForLoad(250),
      );
      expect(last.typicalStrainScore, greaterThan(5));
    });

    test('a single outlier day does not drag the typical (median property)', () {
      // 9 steady ~250 AU prior days plus one wild 20k-AU spike, then the final
      // day. The median ignores the spike, so the typical equals the steady
      // strain — a mean would be pulled far higher.
      final steady = [
        for (var i = 0; i < 9; i++)
          energyDay(3125, DateTime(2025, 12, 1).add(Duration(days: i))),
      ];
      final withOutlier = <HealthMetricSample>[
        ...steady,
        energyDay(20000, DateTime(2025, 12, 10)), // outlier prior
        energyDay(3125, DateTime(2025, 12, 11)), // final day
      ];
      final last = useCase(metrics: withOutlier).last;
      expect(
        last.typicalStrainScore,
        BuildDailyRecoverySnapshotsUseCase.strainScoreForLoad(250),
      );
    });
  });

  test('does not double-count steps/energy across overlapping sources', () {
    HealthMetricSample s(
      HealthMetricType type,
      double value,
      String src, {
      required DateTime start,
      required DateTime end,
    }) => HealthMetricSample(
      type: type,
      value: value,
      unit: type.preferredUnit,
      startTime: start,
      endTime: end,
      source: src,
    );

    // Two providers (phone + watch) each report the SAME window. The interval
    // union counts the window once (the first-seen total), not the ~2x sum.
    final start = DateTime(2025, 1, 1, 12);
    final end = DateTime(2025, 1, 1, 13);
    final snapshot = useCase(
      metrics: [
        s(HealthMetricType.steps, 9000, 'Pixel', start: start, end: end),
        s(HealthMetricType.steps, 8800, 'Google Fit', start: start, end: end),
        s(
          HealthMetricType.activeEnergyBurned,
          500,
          'Pixel',
          start: start,
          end: end,
        ),
        s(
          HealthMetricType.activeEnergyBurned,
          480,
          'Google Fit',
          start: start,
          end: end,
        ),
      ],
    ).single;

    // Counted once (not summed to ~17.8k / ~980).
    expect(snapshot.steps, 9000);
    expect(snapshot.activeEnergyKilocalories, 500);
  });

  test('sums non-overlapping sources instead of dropping disjoint periods', () {
    HealthMetricSample s(
      HealthMetricType type,
      double value,
      String src, {
      required DateTime start,
      required DateTime end,
    }) => HealthMetricSample(
      type: type,
      value: value,
      unit: type.preferredUnit,
      startTime: start,
      endTime: end,
      source: src,
    );

    // Two sources cover DISJOINT windows on the same day: 09:00-10:00 and
    // 14:00-15:00. The old dominant-source logic would have kept only the
    // larger source and dropped the other; the interval union must SUM them
    // because the windows never overlap (no undercount for multi-device users).
    final morningStart = DateTime(2025, 1, 1, 9);
    final morningEnd = DateTime(2025, 1, 1, 10);
    final afternoonStart = DateTime(2025, 1, 1, 14);
    final afternoonEnd = DateTime(2025, 1, 1, 15);
    final snapshot = useCase(
      metrics: [
        s(
          HealthMetricType.steps,
          6000,
          'Pixel',
          start: morningStart,
          end: morningEnd,
        ),
        s(
          HealthMetricType.steps,
          4000,
          'Watch',
          start: afternoonStart,
          end: afternoonEnd,
        ),
        s(
          HealthMetricType.activeEnergyBurned,
          300,
          'Pixel',
          start: morningStart,
          end: morningEnd,
        ),
        s(
          HealthMetricType.activeEnergyBurned,
          200,
          'Watch',
          start: afternoonStart,
          end: afternoonEnd,
        ),
      ],
    ).single;

    expect(snapshot.steps, 10000);
    expect(snapshot.activeEnergyKilocalories, 500);
  });

  group('sleep window (sleepStart / sleepEnd)', () {
    HealthMetricSample segment(
      HealthMetricType type,
      DateTime start,
      DateTime end,
    ) => HealthMetricSample(
      type: type,
      value: end.difference(start).inMinutes.toDouble(),
      unit: type.preferredUnit,
      startTime: start,
      endTime: end,
      source: 'watch',
    );

    test(
      'derives the window from earliest start to latest end, across midnight',
      () {
        // A night's staged-sleep samples all attributed to the wake day (Jan 2)
        // by the aggregator's existing end-time bucketing, even though the
        // session itself started the night before.
        final metrics = <HealthMetricSample>[
          segment(
            HealthMetricType.sleepDeep,
            DateTime(2025, 1, 1, 23, 4),
            DateTime(2025, 1, 2, 0, 4),
          ),
          segment(
            HealthMetricType.sleepRem,
            DateTime(2025, 1, 2, 0, 4),
            DateTime(2025, 1, 2, 1, 0),
          ),
          segment(
            HealthMetricType.sleepAwake,
            DateTime(2025, 1, 2, 2, 0),
            DateTime(2025, 1, 2, 2, 10),
          ),
          segment(
            HealthMetricType.sleepLight,
            DateTime(2025, 1, 2, 2, 10),
            DateTime(2025, 1, 2, 6, 16),
          ),
        ];

        final snapshots = useCase(metrics: metrics);
        final night = snapshots.last;
        expect(night.date, DateTime(2025, 1, 2));
        expect(night.sleepStart, DateTime(2025, 1, 1, 23, 4).toUtc());
        expect(night.sleepEnd, DateTime(2025, 1, 2, 6, 16).toUtc());
      },
    );

    test('ignores time-in-bed padding — only sleep-segment types count', () {
      final metrics = <HealthMetricSample>[
        // Time in bed starts earlier than the first sleep segment; it must
        // NOT stretch the derived window.
        segment(
          HealthMetricType.sleepInBed,
          DateTime(2025, 1, 1, 22, 0),
          DateTime(2025, 1, 2, 6, 45),
        ),
        segment(
          HealthMetricType.sleepAsleep,
          DateTime(2025, 1, 1, 23, 10),
          DateTime(2025, 1, 2, 6, 20),
        ),
      ];

      final snapshots = useCase(metrics: metrics);
      final night = snapshots.last;
      expect(night.sleepStart, DateTime(2025, 1, 1, 23, 10).toUtc());
      expect(night.sleepEnd, DateTime(2025, 1, 2, 6, 20).toUtc());
    });

    test('is absent when no timestamped sleep points exist for the night', () {
      final metrics = <HealthMetricSample>[
        segment(
          HealthMetricType.activeEnergyBurned,
          DateTime(2025, 1, 1, 18, 0),
          DateTime(2025, 1, 1, 18, 30),
        ),
      ];

      final snapshots = useCase(metrics: metrics);
      final day = snapshots.single;
      expect(day.sleepStart, isNull);
      expect(day.sleepEnd, isNull);
    });
  });
}
