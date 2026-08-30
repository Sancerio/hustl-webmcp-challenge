import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;

import '../../../../core/services/preferences_service.dart';
import '../../domain/models/health_metric_sample.dart';
import '../../domain/models/nutrition_log_entry.dart';

class CachedHealthSnapshot {
  const CachedHealthSnapshot({
    required this.rangeStart,
    required this.rangeEnd,
    required this.metrics,
    required this.nutritionEntries,
    required this.lastSyncedAt,
    this.warnings = const [],
  });

  final DateTime rangeStart;
  final DateTime rangeEnd;
  final List<HealthMetricSample> metrics;
  final List<NutritionLogEntry> nutritionEntries;
  final DateTime lastSyncedAt;
  final List<String> warnings;
}

class HealthCacheService {
  HealthCacheService(this._preferences);

  static const _storageKey = 'health_sync_snapshot_v1';
  final PreferencesService _preferences;

  Future<void> saveSnapshot({
    required DateTime start,
    required DateTime end,
    required List<HealthMetricSample> metrics,
    required List<NutritionLogEntry> nutrition,
    required DateTime fetchedAt,
    List<String> warnings = const [],
  }) async {
    // Encoding a real HealthKit snapshot can walk thousands of observations.
    // Keep both DTO projection and jsonEncode off the UI isolate so a cache
    // write cannot interrupt a Train scroll immediately after readiness loads.
    final payload = await compute(
      _encodeSnapshot,
      _HealthCacheEncodingInput(
        start: start,
        end: end,
        metrics: metrics,
        nutrition: nutrition,
        fetchedAt: fetchedAt,
        warnings: warnings,
      ),
    );

    await _preferences.setRawString(_storageKey, payload);
  }

  Future<CachedHealthSnapshot?> loadSnapshot() async {
    final raw = await _preferences.getRawString(_storageKey);
    if (raw == null || raw.isEmpty) return null;

    // A real Apple Health cache can contain thousands of raw observations.
    // JSON decoding plus object hydration is synchronous work; doing it on the
    // UI isolate competes directly with the first Train-tab scroll after a
    // cold start. Flutter's compute keeps native platforms off the UI isolate
    // and safely falls back to the current event loop on web.
    return compute(_decodeSnapshot, raw);
  }

  static CachedHealthSnapshot? _decodeSnapshot(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final warnings =
          (decoded['warnings'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .toList() ??
          const [];
      final metrics = (decoded['metrics'] as List<dynamic>)
          .map(
            (item) => HealthMetricSample(
              type: HealthMetricType.values.firstWhere(
                (t) => t.name == item['type'],
              ),
              value: (item['value'] as num).toDouble(),
              unit: item['unit'] as String,
              startTime: DateTime.parse(item['startTime'] as String),
              endTime: DateTime.parse(item['endTime'] as String),
              source: item['source'] as String,
              isUserEntered: item['isUserEntered'] as bool? ?? false,
              externalId: item['externalId'] as String?,
              sourceId: item['sourceId'] as String?,
              sourceDeviceId: item['sourceDeviceId'] as String?,
              deviceModel: item['deviceModel'] as String?,
              platform: item['platform'] as String?,
              recordingMethod: item['recordingMethod'] as String? ?? 'unknown',
              timezoneName: item['timezoneName'] as String?,
              timezoneOffsetMinutes: (item['timezoneOffsetMinutes'] as num?)
                  ?.toInt(),
              quality: HealthDataQuality.values.byName(
                item['quality'] as String? ?? HealthDataQuality.measured.name,
              ),
              completeness: HealthDataCompleteness.values.byName(
                item['completeness'] as String? ??
                    HealthDataCompleteness.complete.name,
              ),
              sessionKey: item['sessionKey'] as String?,
            ),
          )
          .toList();
      final nutrition = (decoded['nutrition'] as List<dynamic>)
          .map(
            (item) => NutritionLogEntry(
              timestamp: DateTime.parse(item['timestamp'] as String),
              calories: (item['calories'] as num).toDouble(),
              proteinGrams: (item['proteinGrams'] as num).toDouble(),
              carbsGrams: (item['carbsGrams'] as num).toDouble(),
              fatGrams: (item['fatGrams'] as num).toDouble(),
              fiberGrams: (item['fiberGrams'] as num?)?.toDouble(),
              sugarGrams: (item['sugarGrams'] as num?)?.toDouble(),
              sodiumMilligrams: (item['sodiumMilligrams'] as num?)?.toDouble(),
              waterMilliliters: (item['waterMilliliters'] as num?)?.toDouble(),
              source: item['source'] as String? ?? 'unknown',
            ),
          )
          .toList();
      return CachedHealthSnapshot(
        rangeStart: DateTime.parse(decoded['rangeStart'] as String),
        rangeEnd: DateTime.parse(decoded['rangeEnd'] as String),
        lastSyncedAt: DateTime.parse(decoded['lastSyncedAt'] as String),
        metrics: metrics,
        nutritionEntries: nutrition,
        warnings: warnings,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    await _preferences.setRawString(_storageKey, null);
  }
}

class _HealthCacheEncodingInput {
  const _HealthCacheEncodingInput({
    required this.start,
    required this.end,
    required this.metrics,
    required this.nutrition,
    required this.fetchedAt,
    required this.warnings,
  });

  final DateTime start;
  final DateTime end;
  final List<HealthMetricSample> metrics;
  final List<NutritionLogEntry> nutrition;
  final DateTime fetchedAt;
  final List<String> warnings;
}

String _encodeSnapshot(_HealthCacheEncodingInput input) {
  return jsonEncode({
    'rangeStart': input.start.toIso8601String(),
    'rangeEnd': input.end.toIso8601String(),
    'lastSyncedAt': input.fetchedAt.toIso8601String(),
    'warnings': input.warnings,
    'metrics': input.metrics
        .map(
          (metric) => {
            'type': metric.type.name,
            'value': metric.value,
            'unit': metric.unit,
            'startTime': metric.startTime.toIso8601String(),
            'endTime': metric.endTime.toIso8601String(),
            'source': metric.source,
            'isUserEntered': metric.isUserEntered,
            'externalId': metric.externalId,
            'sourceId': metric.sourceId,
            'sourceDeviceId': metric.sourceDeviceId,
            'deviceModel': metric.deviceModel,
            'platform': metric.platform,
            'recordingMethod': metric.recordingMethod,
            'timezoneName': metric.timezoneName,
            'timezoneOffsetMinutes': metric.timezoneOffsetMinutes,
            'quality': metric.quality.name,
            'completeness': metric.completeness.name,
            'sessionKey': metric.sessionKey,
          },
        )
        .toList(),
    'nutrition': input.nutrition
        .map(
          (entry) => {
            'timestamp': entry.timestamp.toIso8601String(),
            'calories': entry.calories,
            'proteinGrams': entry.proteinGrams,
            'carbsGrams': entry.carbsGrams,
            'fatGrams': entry.fatGrams,
            'fiberGrams': entry.fiberGrams,
            'sugarGrams': entry.sugarGrams,
            'sodiumMilligrams': entry.sodiumMilligrams,
            'waterMilliliters': entry.waterMilliliters,
            'source': entry.source,
          },
        )
        .toList(),
  });
}
