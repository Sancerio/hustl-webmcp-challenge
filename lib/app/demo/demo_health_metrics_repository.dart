import 'dart:math' as math;

import '../../features/health_sync/domain/models/daily_health_summary.dart';
import '../../features/health_sync/domain/models/daily_recovery_snapshot.dart';
import '../../features/health_sync/domain/models/health_metric_sample.dart';
import '../../features/health_sync/domain/models/recovery_signal_availability.dart';
import '../../features/health_sync/domain/repositories/health_metrics_repository.dart';
import '../../features/health_sync/presentation/preview/health_overview_preview_repository.dart';
import 'demo_persona.dart';

/// Deterministic [HealthMetricsRepository] for demo mode.
///
/// Reuses the existing [PreviewHealthMetricsRepository] (which already produces
/// reproducible sleep / readiness / recovery / strain curves) and then rewrites
/// the body-weight track to Alex's 84.2 -> 81.6 kg journey, pins sleep to the
/// persona's 7h12m, and injects a steps sample so the health overview reads a
/// complete picture offline (spec §10).
class DemoHealthMetricsRepository implements HealthMetricsRepository {
  const DemoHealthMetricsRepository({this.poorRecovery = false});

  final bool poorRecovery;

  static const PreviewHealthMetricsRepository _preview =
      PreviewHealthMetricsRepository();

  /// Persona sleep duration: 7h12m.
  static const double sleepMinutes = 432;

  /// Evaluator baseline: 5h18m supports a lighter-day conversation without
  /// presenting a medical conclusion.
  static const double challengeSleepMinutes = 318;
  static const double challengeReadiness = 42;

  @override
  Future<HealthPermissionsStatus> getPermissionsStatus() =>
      _preview.getPermissionsStatus();

  @override
  Future<HealthPermissionsStatus> requestPermissions() =>
      _preview.requestPermissions();

  @override
  Future<void> clearCache() => _preview.clearCache();

  @override
  Future<void> resetPermissionDenialFlag() =>
      _preview.resetPermissionDenialFlag();

  @override
  Future<HealthProviderAvailability> getProviderAvailability() =>
      _preview.getProviderAvailability();

  @override
  Future<void> installHealthConnect() => _preview.installHealthConnect();

  @override
  Future<HealthSnapshot> loadSnapshot({
    required DateTime start,
    required DateTime end,
    bool forceRefresh = false,
  }) async {
    final base = await _preview.loadSnapshot(
      start: start,
      end: end,
      forceRefresh: forceRefresh,
    );
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEnd = DateTime(end.year, end.month, end.day);
    final dayCount = normalizedEnd.difference(normalizedStart).inDays + 1;

    double weightFor(int index) {
      final progress = dayCount <= 1 ? 1.0 : index / (dayCount - 1);
      final trend =
          DemoPersona.weightStartKg +
          (DemoPersona.weightEndKg - DemoPersona.weightStartKg) * progress;
      final noise = math.sin(index * 0.7) * 0.28 + math.cos(index * 1.9) * 0.18;
      return double.parse((trend + noise).toStringAsFixed(2));
    }

    int stepsFor(int index) => 9200 + (math.sin(index * 0.5) * 2400).round();

    const heightM = DemoPersona.heightCm / 100;

    // Rewrite the daily summaries with Alex's weight/BMI.
    final summaries = <DailyHealthSummary>[];
    for (var i = 0; i < base.dailySummaries.length; i++) {
      final s = base.dailySummaries[i];
      final weight = weightFor(i);
      summaries.add(
        DailyHealthSummary(
          date: s.date,
          latestWeightKg: weight,
          latestHeightCm: DemoPersona.heightCm,
          bodyMassIndex: double.parse(
            (weight / (heightM * heightM)).toStringAsFixed(1),
          ),
          bodyFatPercentage: s.bodyFatPercentage,
          basalMetabolicRate: s.basalMetabolicRate,
          metrics: s.metrics,
          nutritionLogs: s.nutritionLogs,
          macros: s.macros,
        ),
      );
    }

    // Pin sleep duration on the latest recovery snapshot to 7h12m.
    final recovery = <DailyRecoverySnapshot>[];
    for (var i = 0; i < base.recoverySnapshots.length; i++) {
      final r = base.recoverySnapshots[i];
      final isLatest = i == base.recoverySnapshots.length - 1;
      recovery.add(
        isLatest
            ? _withSleep(r, poorRecovery ? challengeSleepMinutes : sleepMinutes)
            : r,
      );
    }

    // Replace weight samples and add steps samples per day.
    final metrics = <HealthMetricSample>[
      for (final m in base.metrics)
        if (m.type != HealthMetricType.weight) m,
    ];
    for (var i = 0; i < dayCount; i++) {
      final date = normalizedStart.add(Duration(days: i));
      metrics.add(
        HealthMetricSample(
          type: HealthMetricType.weight,
          value: weightFor(i),
          unit: 'kg',
          startTime: date.add(const Duration(hours: 7)),
          endTime: date.add(const Duration(hours: 7, minutes: 5)),
          source: 'demo',
        ),
      );
      metrics.add(
        HealthMetricSample(
          type: HealthMetricType.steps,
          value: stepsFor(i).toDouble(),
          unit: 'count',
          startTime: date,
          endTime: date.add(const Duration(hours: 23, minutes: 59)),
          source: 'demo',
        ),
      );
    }

    return HealthSnapshot(
      rangeStart: base.rangeStart,
      rangeEnd: base.rangeEnd,
      metrics: metrics,
      nutritionEntries: base.nutritionEntries,
      dailySummaries: summaries,
      recoverySnapshots: recovery,
      lastSyncedAt: base.lastSyncedAt,
      warnings: base.warnings,
      rawPermissionResult: true,
      signalAvailability: base.signalAvailability,
    );
  }

  DailyRecoverySnapshot _withSleep(DailyRecoverySnapshot r, double minutes) {
    // Pin Alex to a believable, CONFIDENT readiness so R1/R2/R3 surfaces render
    // richly: a strong "Ready" band, a matured >=14-day baseline, plausible
    // HRV/RHR/sleep, and no anomaly flags on the latest day.
    final readiness = poorRecovery ? challengeReadiness : 74.0;
    final recovery = poorRecovery ? 44.0 : 71.0;
    final flowBand = poorRecovery
        ? RecoveryFlowBand.recharge
        : RecoveryFlowBand.ready;
    return DailyRecoverySnapshot(
      date: r.date,
      sleepDurationMinutes: minutes,
      timeInBedMinutes: minutes + 26,
      remSleepMinutes: minutes * 0.22,
      deepSleepMinutes: minutes * 0.18,
      lightSleepMinutes: minutes * 0.55,
      awakeMinutes: minutes * 0.05,
      sleepNeedMinutes: r.sleepNeedMinutes,
      sleepPerformanceScore: poorRecovery
          ? 61
          : (r.sleepPerformanceScore ?? 82),
      sleepConsistencyScore: poorRecovery
          ? 76
          : (r.sleepConsistencyScore ?? 84),
      sleepEfficiency: poorRecovery ? 0.88 : (r.sleepEfficiency ?? 0.94),
      hrvValue: poorRecovery ? 47 : (r.hrvValue ?? 58),
      hrvKind: r.hrvKind ?? HrvKind.sdnn,
      restingHeartRateBpm: poorRecovery ? 61 : (r.restingHeartRateBpm ?? 54),
      respiratoryRate: r.respiratoryRate ?? 14.6,
      bloodOxygenPercent: r.bloodOxygenPercent ?? 97.4,
      temperatureCelsius: r.temperatureCelsius,
      temperatureDeltaCelsius: 0.04,
      steps: poorRecovery ? 4200 : 9800,
      activeEnergyKilocalories: r.activeEnergyKilocalories,
      exerciseMinutes: r.exerciseMinutes,
      trainingLoad: r.trainingLoad,
      acuteLoad7: r.acuteLoad7,
      chronicLoad42: r.chronicLoad42,
      loadRatio: r.loadRatio,
      recoveryScore: recovery,
      readinessScore: readiness,
      strainScore: r.strainScore,
      baselineCoverageDays: 21,
      band: flowBand.legacyBand,
      flowBand: flowBand,
      confidence: RecoveryConfidence.high,
      isCalibrating: false,
      anomalyFlags: poorRecovery ? const ['sleep_below_baseline'] : const [],
    );
  }
}
