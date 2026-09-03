import 'dart:math' as math;

import '../../domain/models/daily_health_summary.dart';
import '../../domain/models/daily_recovery_snapshot.dart';
import '../../domain/models/health_metric_sample.dart';
import '../../domain/models/nutrition_log_entry.dart';
import '../../domain/models/recovery_signal_availability.dart';
import '../../domain/repositories/health_metrics_repository.dart';

class PreviewHealthMetricsRepository implements HealthMetricsRepository {
  const PreviewHealthMetricsRepository();

  @override
  Future<HealthPermissionsStatus> getPermissionsStatus() async {
    return const HealthPermissionsStatus(
      hasPermissions: true,
      isServiceAvailable: true,
      rawPermissionResult: true,
    );
  }

  @override
  Future<HealthPermissionsStatus> requestPermissions() async {
    return const HealthPermissionsStatus(
      hasPermissions: true,
      isServiceAvailable: true,
      rawPermissionResult: true,
    );
  }

  @override
  Future<HealthSnapshot> loadSnapshot({
    required DateTime start,
    required DateTime end,
    bool forceRefresh = false,
  }) async {
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEnd = DateTime(end.year, end.month, end.day);
    final dayCount = normalizedEnd.difference(normalizedStart).inDays + 1;

    final summaries = <DailyHealthSummary>[];
    final recovery = <DailyRecoverySnapshot>[];
    final metrics = <HealthMetricSample>[];

    for (var index = 0; index < dayCount; index++) {
      final date = normalizedStart.add(Duration(days: index));
      final progress = index / math.max(1, dayCount - 1);
      final hrv = 34 + (progress * 8) + math.sin(index / 3.1) * 3.8;
      final restingHr = 61 - (progress * 4.2) + math.cos(index / 4.6) * 1.1;
      final sleepMinutes = 425 + math.sin(index / 2.4) * 38 + progress * 18;
      final sleepNeedMinutes = 470 + math.cos(index / 5.0) * 12;
      final sleepPerformance = (((sleepMinutes / sleepNeedMinutes) * 100).clamp(
        58,
        94,
      )).toDouble();
      final readiness = ((64 + progress * 18 + math.sin(index / 5.2) * 8).clamp(
        49,
        91,
      )).toDouble();
      final recoveryScore = ((readiness - 5 + math.sin(index / 4.8) * 4).clamp(
        46,
        88,
      )).toDouble();
      final strain = (7 + progress * 4 + math.cos(index / 2.7) * 2)
          .round()
          .clamp(4, 16);
      final loadRatio = (0.94 + math.sin(index / 5.7) * 0.14 + progress * 0.08)
          .clamp(0.72, 1.28);
      final weight = 81.2 - progress * 1.4 + math.sin(index / 3.8) * 0.28;
      final bmi = weight / math.pow(1.82, 2);
      final bodyFat = 18.6 - progress * 0.9 + math.cos(index / 4.3) * 0.22;
      final water = 2.0 + math.sin(index / 2.9) * 0.35;

      // Coverage matures over the seeded window: calibrating early, then a
      // confident >=14-day baseline once enough history exists.
      final baselineCoverageDays = math.min(index, 28);
      final flowBand = _previewFlowBand(readiness);
      final confidence = baselineCoverageDays >= 14
          ? RecoveryConfidence.high
          : baselineCoverageDays >= 7
          ? RecoveryConfidence.medium
          : RecoveryConfidence.low;

      final snapshot = DailyRecoverySnapshot(
        date: date,
        sleepDurationMinutes: sleepMinutes,
        sleepNeedMinutes: sleepNeedMinutes,
        sleepPerformanceScore: sleepPerformance,
        sleepConsistencyScore: ((76 + math.cos(index / 4.5) * 8).clamp(
          62,
          90,
        )).toDouble(),
        hrvValue: hrv,
        hrvKind: HrvKind.sdnn,
        restingHeartRateBpm: restingHr,
        respiratoryRate: 15.6 + math.cos(index / 6.0) * 0.8,
        bloodOxygenPercent: 97.3 + math.sin(index / 6.2) * 0.5,
        temperatureDeltaCelsius:
            math.sin(index / 7.4) * 0.18 + (index == dayCount - 1 ? 0.06 : 0),
        activeEnergyKilocalories:
            520 + math.sin(index / 2.1) * 140 + progress * 110,
        exerciseMinutes: 42 + math.cos(index / 2.4) * 14 + progress * 9,
        trainingLoad: 76 + math.sin(index / 3.2) * 18 + progress * 12,
        acuteLoad7: 81 + math.cos(index / 5.0) * 10 + progress * 8,
        chronicLoad42: 72 + progress * 6,
        loadRatio: loadRatio,
        recoveryScore: recoveryScore,
        readinessScore: readiness,
        strainScore: strain,
        baselineCoverageDays: baselineCoverageDays,
        band: flowBand.legacyBand,
        flowBand: flowBand,
        confidence: confidence,
        isCalibrating:
            baselineCoverageDays < DailyRecoverySnapshot.calibrationTargetDays,
        anomalyFlags: index == dayCount - 2
            ? const ['short_sleep', 'elevated_load']
            : const [],
      );

      recovery.add(snapshot);
      summaries.add(
        DailyHealthSummary(
          date: date,
          latestWeightKg: weight,
          latestHeightCm: 182,
          bodyMassIndex: bmi,
          bodyFatPercentage: bodyFat,
          metrics: const [],
          nutritionLogs: const <NutritionLogEntry>[],
          macros: DailyMacroBreakdown(
            calories: 2280 + math.sin(index / 2.5) * 160,
            proteinGrams: 154 + math.cos(index / 3.6) * 12,
            carbsGrams: 218 + math.sin(index / 3.1) * 22,
            fatGrams: 76 + math.cos(index / 2.8) * 8,
            waterLiters: water,
          ),
        ),
      );

      metrics.addAll([
        HealthMetricSample(
          type: HealthMetricType.weight,
          value: weight,
          unit: 'kg',
          startTime: date.add(const Duration(hours: 7)),
          endTime: date.add(const Duration(hours: 7, minutes: 5)),
          source: 'preview',
        ),
        HealthMetricSample(
          type: HealthMetricType.heartRateVariabilitySdnn,
          value: hrv,
          unit: 'ms',
          startTime: date.add(const Duration(hours: 6, minutes: 40)),
          endTime: date.add(const Duration(hours: 6, minutes: 45)),
          source: 'preview',
        ),
        HealthMetricSample(
          type: HealthMetricType.restingHeartRate,
          value: restingHr,
          unit: 'bpm',
          startTime: date.add(const Duration(hours: 6, minutes: 50)),
          endTime: date.add(const Duration(hours: 6, minutes: 55)),
          source: 'preview',
        ),
        HealthMetricSample(
          type: HealthMetricType.sleepAsleep,
          value: sleepMinutes,
          unit: 'min',
          startTime: date.subtract(const Duration(hours: 8)),
          endTime: date,
          source: 'preview',
        ),
      ]);
    }

    return HealthSnapshot(
      rangeStart: normalizedStart,
      rangeEnd: normalizedEnd,
      metrics: metrics,
      nutritionEntries: const [],
      dailySummaries: summaries,
      recoverySnapshots: recovery,
      lastSyncedAt: normalizedEnd.add(const Duration(hours: 7, minutes: 12)),
      warnings: const [],
      rawPermissionResult: true,
      signalAvailability: const RecoverySignalAvailability(
        providerAvailability: HealthProviderAvailability.available,
        hrv: true,
        restingHeartRate: true,
        sleep: true,
        respiratoryRate: true,
      ),
    );
  }

  static RecoveryFlowBand _previewFlowBand(double readiness) {
    if (readiness >= 80) return RecoveryFlowBand.charged;
    if (readiness >= 60) return RecoveryFlowBand.ready;
    if (readiness >= 40) return RecoveryFlowBand.steady;
    return RecoveryFlowBand.recharge;
  }

  @override
  Future<void> clearCache() async {}

  @override
  Future<void> resetPermissionDenialFlag() async {}

  @override
  Future<HealthProviderAvailability> getProviderAvailability() async =>
      HealthProviderAvailability.available;

  @override
  Future<void> installHealthConnect() async {}
}
