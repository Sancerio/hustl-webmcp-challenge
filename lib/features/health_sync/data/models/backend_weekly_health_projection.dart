import '../../domain/models/external_activity.dart';
import '../../domain/models/health_metric_sample.dart';
import '../../domain/repositories/health_metrics_repository.dart';
import '../../domain/usecases/build_daily_health_summaries.dart';
import '../../domain/usecases/build_daily_recovery_snapshots.dart';

class BackendWeeklyHealthProjection {
  const BackendWeeklyHealthProjection({
    required this.snapshot,
    required this.activities,
    required this.preferredProvider,
    required this.lastSyncedAt,
  });

  final HealthSnapshot snapshot;
  final List<ExternalActivity> activities;
  final String? preferredProvider;
  final DateTime? lastSyncedAt;

  factory BackendWeeklyHealthProjection.fromApiData(Map<String, dynamic> data) {
    final range = _map(data['range']);
    _date(range['start']);
    final end = _date(range['end']);
    final baselineStart = _date(range['baselineStart']);
    final preferredProvider = _text(data['preferredProvider']);
    final rawMetrics = _maps(data['metrics']);
    final metricRows = _preferProvider(rawMetrics, preferredProvider);
    final deduped = <String, Map<String, dynamic>>{};
    for (final row in metricRows) {
      final date = _text(row['date']);
      final type = _text(row['metricType']);
      if (date == null || type == null) continue;
      final key = '$date|$type';
      final existing = deduped[key];
      if (existing == null ||
          _instant(row['updatedAt']).isAfter(_instant(existing['updatedAt']))) {
        deduped[key] = row;
      }
    }

    final metrics =
        deduped.values
            .map(_metricFromRow)
            .whereType<HealthMetricSample>()
            .toList()
          ..sort((a, b) => a.endTime.compareTo(b.endTime));
    final dailySummaries = BuildDailyHealthSummariesUseCase()(
      metrics: metrics,
      nutritionEntries: const [],
    );
    final recoverySnapshots = BuildDailyRecoverySnapshotsUseCase()(
      metrics: metrics,
      now: end.add(const Duration(days: 1)),
    );

    final sources = _maps(data['sources']);
    final sourceTimes =
        sources
            .map(
              (source) =>
                  DateTime.tryParse(_text(source['lastSyncedAt']) ?? ''),
            )
            .whereType<DateTime>()
            .toList()
          ..sort();
    final lastSyncedAt = sourceTimes.lastOrNull;
    final activityRows = _preferProvider(
      _maps(data['activities']),
      preferredProvider,
      providerField: 'provider',
    );
    final activities =
        activityRows
            .map(_activityFromRow)
            .whereType<ExternalActivity>()
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));

    return BackendWeeklyHealthProjection(
      snapshot: HealthSnapshot(
        rangeStart: baselineStart,
        rangeEnd: end,
        metrics: metrics,
        nutritionEntries: const [],
        dailySummaries: dailySummaries,
        recoverySnapshots: recoverySnapshots,
        lastSyncedAt:
            lastSyncedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        warnings: sources.isEmpty
            ? const ['No mobile health sync has reached Hustl yet.']
            : const [],
      ),
      activities: activities,
      preferredProvider: preferredProvider,
      lastSyncedAt: lastSyncedAt,
    );
  }
}

List<Map<String, dynamic>> _preferProvider(
  List<Map<String, dynamic>> rows,
  String? provider, {
  String providerField = 'source',
}) {
  if (provider == null) return rows;
  final matching = rows
      .where((row) => _text(row[providerField]) == provider)
      .toList();
  return matching.isEmpty ? rows : matching;
}

HealthMetricSample? _metricFromRow(Map<String, dynamic> row) {
  final day = DateTime.tryParse(_text(row['date']) ?? '');
  final value = _number(row['value']);
  final wireType = _text(row['metricType']);
  if (day == null || value == null || wireType == null) return null;
  final type = switch (wireType) {
    'weight' => HealthMetricType.weight,
    'body_fat_percentage' => HealthMetricType.bodyFatPercentage,
    'steps' => HealthMetricType.steps,
    'exercise_minutes' => HealthMetricType.exerciseTime,
    'active_energy_kcal' => HealthMetricType.activeEnergyBurned,
    'hrv_sdnn' => HealthMetricType.heartRateVariabilitySdnn,
    'hrv_rmssd' => HealthMetricType.heartRateVariabilityRmssd,
    'resting_heart_rate' => HealthMetricType.restingHeartRate,
    'sleep_duration' => HealthMetricType.sleepAsleep,
    _ => null,
  };
  if (type == null) return null;

  final offset = _integer(row['timezoneOffsetMinutes']);
  final localNoon = _localInstant(day, 12, offset);
  final start = switch (type) {
    HealthMetricType.sleepAsleep => localNoon.subtract(
      Duration(milliseconds: (value * 60000).round()),
    ),
    HealthMetricType.steps ||
    HealthMetricType.exerciseTime ||
    HealthMetricType.activeEnergyBurned => _localInstant(day, 0, offset),
    _ => localNoon,
  };
  final end = switch (type) {
    HealthMetricType.steps ||
    HealthMetricType.exerciseTime ||
    HealthMetricType.activeEnergyBurned => _localInstant(
      day,
      23,
      offset,
    ).add(const Duration(minutes: 59)),
    _ => localNoon,
  };
  return HealthMetricSample(
    type: type,
    value: value,
    unit: _text(row['unit']) ?? type.preferredUnit,
    startTime: start,
    endTime: end,
    source: _text(row['source']) ?? 'Hustl sync',
    externalId: '${_text(row['date'])}|$wireType',
    timezoneName: _text(row['timezoneName']),
    timezoneOffsetMinutes: offset,
    recordingMethod: 'backend_sync',
    quality: _quality(row['quality']),
    completeness: _completeness(row['completeness']),
  );
}

ExternalActivity? _activityFromRow(Map<String, dynamic> row) {
  final uuid = _text(row['platformUuid']);
  final source = _text(row['sourceName']);
  final start = DateTime.tryParse(_text(row['startTime']) ?? '');
  final end = DateTime.tryParse(_text(row['endTime']) ?? '');
  if (uuid == null || source == null || start == null || end == null) {
    return null;
  }
  if (!end.isAfter(start)) return null;
  final kindName = _text(row['kind']);
  final kind = ExternalActivityKind.values.firstWhere(
    (candidate) => candidate.name == kindName,
    orElse: () => ExternalActivityKind.other,
  );
  return ExternalActivity(
    platformUuid: uuid,
    sourceName: source,
    kind: kind,
    activityName: _text(row['activityName']),
    start: start,
    end: end,
    distanceMeters: _positive(row['distanceMeters']),
    activeEnergyKcal: _positive(row['activeEnergyKcal']),
    averageHeartRateBpm: _positive(row['averageHeartRateBpm']),
  );
}

DateTime _localInstant(DateTime day, int hour, int? offsetMinutes) {
  if (offsetMinutes == null) {
    return DateTime(day.year, day.month, day.day, hour);
  }
  return DateTime.utc(
    day.year,
    day.month,
    day.day,
    hour,
  ).subtract(Duration(minutes: offsetMinutes));
}

HealthDataQuality _quality(dynamic value) => switch (_text(value)) {
  'user_entered' => HealthDataQuality.userEntered,
  'derived' => HealthDataQuality.derived,
  'unknown' => HealthDataQuality.unknown,
  _ => HealthDataQuality.measured,
};

HealthDataCompleteness _completeness(dynamic value) => switch (_text(value)) {
  'partial' => HealthDataCompleteness.partial,
  'ongoing' => HealthDataCompleteness.ongoing,
  'unknown' => HealthDataCompleteness.unknown,
  _ => HealthDataCompleteness.complete,
};

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
    : const [];

DateTime _date(dynamic value) {
  final parsed = DateTime.tryParse(_text(value) ?? '');
  if (parsed == null) {
    throw const FormatException('Invalid weekly health range');
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime _instant(dynamic value) =>
    DateTime.tryParse(_text(value) ?? '') ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

String? _text(dynamic value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

double? _number(dynamic value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed?.isFinite == true ? parsed : null;
}

double? _positive(dynamic value) {
  final parsed = _number(value);
  return parsed != null && parsed > 0 ? parsed : null;
}

int? _integer(dynamic value) => value is num
    ? value.toInt()
    : value == null
    ? null
    : int.tryParse('$value');

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
