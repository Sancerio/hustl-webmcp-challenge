import '../../domain/models/health_metric_sample.dart';
import '../../domain/models/recovery_signal_availability.dart';
import '../../domain/repositories/health_metrics_repository.dart';
import '../../domain/usecases/build_daily_health_summaries.dart';
import '../../domain/usecases/build_daily_recovery_snapshots.dart';
import '../datasources/hustl_backend_health_api.dart';
import '../models/backend_weekly_health_projection.dart';

/// Read-only health repository for authenticated web clients.
///
/// Browsers cannot query Apple Health or Health Connect directly, so the web
/// app reads the latest mobile-synced projection from Hustl's backend instead.
class BackendHealthMetricsRepository implements HealthMetricsRepository {
  BackendHealthMetricsRepository({required HustlBackendHealthApi api})
    : _api = api;

  final HustlBackendHealthApi _api;

  @override
  Future<HealthPermissionsStatus> getPermissionsStatus() async =>
      const HealthPermissionsStatus(
        hasPermissions: true,
        isServiceAvailable: true,
        rawPermissionResult: true,
      );

  @override
  Future<HealthPermissionsStatus> requestPermissions() =>
      getPermissionsStatus();

  @override
  Future<HealthSnapshot> loadSnapshot({
    required DateTime start,
    required DateTime end,
    bool forceRefresh = false,
  }) async {
    final normalizedStart = _day(start);
    final normalizedEnd = _day(end);
    if (normalizedEnd.isBefore(normalizedStart)) {
      throw ArgumentError.value(end, 'end', 'must not be before start');
    }

    // Each weekly endpoint response includes its requested seven days plus a
    // 14-day baseline lead. Cover the requested span in 21-day windows rather
    // than issuing one request per week. The final request may extend into the
    // future; results are filtered back to the exact requested range below.
    final projections = <BackendWeeklyHealthProjection>[];
    for (
      var coverageStart = normalizedStart;
      !coverageStart.isAfter(normalizedEnd);
      coverageStart = coverageStart.add(const Duration(days: 21))
    ) {
      final requestEnd = coverageStart.add(const Duration(days: 20));
      final requestStart = requestEnd.subtract(const Duration(days: 6));
      projections.add(
        await _api.fetchWeeklyProjection(start: requestStart, end: requestEnd),
      );
    }

    final metricsByKey = <String, HealthMetricSample>{};
    for (final projection in projections) {
      for (final metric in projection.snapshot.metrics) {
        final localDay = _day(metric.localEndTime);
        if (localDay.isBefore(normalizedStart) ||
            localDay.isAfter(normalizedEnd)) {
          continue;
        }
        final key =
            metric.externalId ??
            '${metric.type.name}|${metric.startTime.toIso8601String()}|'
                '${metric.endTime.toIso8601String()}|${metric.source}';
        metricsByKey[key] = metric;
      }
    }
    final metrics = metricsByKey.values.toList()
      ..sort((a, b) => a.endTime.compareTo(b.endTime));

    final sourceTimes =
        projections
            .map((projection) => projection.lastSyncedAt)
            .whereType<DateTime>()
            .toList()
          ..sort();
    final warnings = projections
        .expand((projection) => projection.snapshot.warnings)
        .toSet()
        .toList();

    return HealthSnapshot(
      rangeStart: normalizedStart,
      rangeEnd: normalizedEnd,
      metrics: metrics,
      nutritionEntries: const [],
      dailySummaries: BuildDailyHealthSummariesUseCase()(
        metrics: metrics,
        nutritionEntries: const [],
      ),
      recoverySnapshots: BuildDailyRecoverySnapshotsUseCase()(
        metrics: metrics,
        now: normalizedEnd.add(const Duration(days: 1)),
      ),
      lastSyncedAt:
          sourceTimes.lastOrNull ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      warnings: warnings,
      rawPermissionResult: true,
      signalAvailability: _signalAvailability(metrics),
    );
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

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

RecoverySignalAvailability _signalAvailability(
  List<HealthMetricSample> metrics,
) {
  bool has(HealthMetricType type) =>
      metrics.any((metric) => metric.type == type);

  return RecoverySignalAvailability(
    hrv:
        has(HealthMetricType.heartRateVariabilitySdnn) ||
        has(HealthMetricType.heartRateVariabilityRmssd),
    restingHeartRate: has(HealthMetricType.restingHeartRate),
    sleep: has(HealthMetricType.sleepAsleep),
    respiratoryRate: has(HealthMetricType.respiratoryRate),
  );
}

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
