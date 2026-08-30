import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';

import '../../../../core/services/preferences_service.dart';
import '../../domain/writeback/workout_record.dart';
import '../../domain/writeback/workout_write_service.dart';

const _lookupWindowPadding = Duration(minutes: 10);
const _timestampTolerance = Duration(seconds: 90);
const _defaultCaptureRetryDelays = <Duration>[
  Duration(milliseconds: 0),
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 10),
];
const _defaultPreDeleteVerificationDelays = <Duration>[
  Duration(milliseconds: 0),
  Duration(milliseconds: 500),
  Duration(seconds: 1),
];
const _heartRateMarkerStorageKey = 'workout_writeback_hr_markers_v1';

class HealthWorkoutWriteService implements WorkoutWriteService {
  HealthWorkoutWriteService({
    Health? health,
    PreferencesService? preferences,
    WorkoutWritePlatform? platformOverride,
    List<Duration>? captureRetryDelays,
    List<Duration>? preDeleteVerificationDelays,
  }) : _health = health ?? Health(),
       _preferences = preferences ?? PreferencesService(),
       _platformOverride = platformOverride,
       _captureRetryDelays = captureRetryDelays ?? _defaultCaptureRetryDelays,
       _preDeleteVerificationDelays =
           preDeleteVerificationDelays ?? _defaultPreDeleteVerificationDelays;

  final Health _health;
  final PreferencesService _preferences;
  final StreamController<WorkoutWriteEvent> _events =
      StreamController<WorkoutWriteEvent>.broadcast();
  WorkoutWriteCapability? _cachedCapability;
  final WorkoutWritePlatform? _platformOverride;
  final List<Duration> _captureRetryDelays;
  final List<Duration> _preDeleteVerificationDelays;

  @override
  Stream<WorkoutWriteEvent> get events => _events.stream;

  @override
  Future<WorkoutWriteCapability> getCapabilities() async {
    if (kIsWeb) {
      _cachedCapability = const WorkoutWriteCapability(
        platform: WorkoutWritePlatform.unsupported,
        supported: false,
      );
      return _cachedCapability!;
    }

    await _ensureConfigured();

    WorkoutWritePlatform platform = WorkoutWritePlatform.unsupported;
    bool supported = false;

    final override = _platformOverride;
    if (override != null) {
      platform = override;
      supported = platform != WorkoutWritePlatform.unsupported;
    } else if (Platform.isIOS) {
      platform = WorkoutWritePlatform.iosHealthKit;
      supported = true;
    } else if (Platform.isAndroid) {
      platform = WorkoutWritePlatform.androidHealthConnect;
      try {
        supported = await _health.isHealthConnectAvailable();
      } catch (_) {
        supported = false;
      }
    }

    if (!supported) {
      final capability = WorkoutWriteCapability(
        platform: platform,
        supported: false,
      );
      _cachedCapability = capability;
      return capability;
    }

    // Check permissions per-scope so workouts can be considered granted
    // even if optional energy/distance are declined by the user.
    Future<bool> hasPermission(
      List<HealthDataType> types,
      List<HealthDataAccess> permissions,
    ) async {
      try {
        return await _health.hasPermissions(types, permissions: permissions) ??
            false;
      } catch (_) {
        return false;
      }
    }

    // Workouts (required for writeback) — WRITE is sufficient to create
    // workouts. Some users grant write but not read; treat that as granted
    // for writeback.
    final hasWorkouts = await hasPermission(
      const [HealthDataType.WORKOUT],
      const [HealthDataAccess.WRITE],
    );

    // Active energy (optional)
    final hasEnergy = await hasPermission(
      const [HealthDataType.ACTIVE_ENERGY_BURNED],
      const [HealthDataAccess.READ_WRITE],
    );

    // Distance (optional) – treat as granted only if both main types granted.
    final hasDistance = await hasPermission(
      const [
        HealthDataType.DISTANCE_CYCLING,
        HealthDataType.DISTANCE_WALKING_RUNNING,
      ],
      const [HealthDataAccess.READ_WRITE, HealthDataAccess.READ_WRITE],
    );

    // Heart rate (optional)
    final hasHeartRate = await hasPermission(
      const [HealthDataType.HEART_RATE],
      const [HealthDataAccess.WRITE],
    );

    final granted = <WorkoutPermissionScope>{};
    if (hasWorkouts) {
      granted.add(WorkoutPermissionScope.workouts);
    }
    if (hasEnergy) {
      granted.add(WorkoutPermissionScope.energy);
    }
    if (hasDistance) {
      granted.add(WorkoutPermissionScope.distance);
    }
    if (hasHeartRate) {
      granted.add(WorkoutPermissionScope.heartRate);
    }

    if (kDebugMode) {
      debugPrint(
        '[WorkoutWrite] capability probe platform=${platform.name} '
        'supported=$supported hasWorkouts=$hasWorkouts '
        'hasEnergy=$hasEnergy hasDistance=$hasDistance hasHeartRate=$hasHeartRate',
      );
    }

    final capability = WorkoutWriteCapability(
      platform: platform,
      supported: true,
      grantedScopes: granted,
    );
    _cachedCapability = capability;
    return capability;
  }

  @override
  Future<bool> requestPermissions(Set<WorkoutPermissionScope> scopes) async {
    if (kIsWeb) return false;
    final capability = await getCapabilities();
    if (!capability.supported) return false;

    final types = _permissionTypes(scopes);
    if (types.isEmpty) return false;
    try {
      await _ensureConfigured();
      // Request READ_WRITE for workouts so HealthKit/HConnect allow both share & readback.
      final permissions = types
          .map((t) => HealthDataAccess.READ_WRITE)
          .toList(growable: false);
      final granted = await _health.requestAuthorization(
        types,
        permissions: permissions,
      );
      if (kDebugMode) {
        debugPrint(
          '[WorkoutWrite] requestAuthorization scopes=${scopes.map((s) => s.name).join(',')} '
          'types=${types.map((t) => t.name).join(',')} '
          'granted=$granted',
        );
      }
      await getCapabilities();
      _events.add(
        const WorkoutWriteEvent(WorkoutWriteEventType.permissionsUpdated, ''),
      );
      return granted;
    } catch (error, stackTrace) {
      debugPrint('requestPermissions failed: $error\n$stackTrace');
      return false;
    }
  }

  @override
  Future<WorkoutWriteResult> upsertWorkout(WorkoutRecord record) async {
    final capability = await getCapabilities();
    if (!capability.supported) {
      return const WorkoutWriteResult.failure(
        errorCode: 'unsupported_platform',
        retryable: false,
      );
    }

    if (!capability.hasWorkoutPermission) {
      return const WorkoutWriteResult.failure(
        errorCode: 'missing_permissions',
        retryable: false,
      );
    }

    final platform = capability.platform;
    final activityType = _mapActivity(record.activityType, platform);
    if (activityType == null) {
      return const WorkoutWriteResult.failure(
        errorCode: 'unsupported_activity',
        retryable: false,
      );
    }

    try {
      await _ensureConfigured();
      final deletedExisting = await _preEmptiveDelete(record, platform);
      if (!deletedExisting) {
        // Best-effort deletion to avoid duplicates; don't block writes if Health
        // propagation is slow or deletions are flaky.
        if (kDebugMode) {
          debugPrint(
            '[WorkoutWrite] pre-delete could not be fully verified; proceeding with write',
          );
        }
      }
      final success = await _health.writeWorkoutData(
        activityType: activityType,
        start: record.startedAt,
        end: record.endedAt,
        totalEnergyBurned: record.energyKilocalories?.round(),
        totalDistance: record.distanceMeters?.round(),
        title: _buildTitle(record),
      );
      if (!success) {
        return const WorkoutWriteResult.failure(
          errorCode: 'write_failed',
          retryable: true,
        );
      }
      await _deleteStoredHeartRateSamples(externalId: record.externalId);
      await _writeHeartRateSamples(record, capability);
      final uuid = await _captureUuid(record, platform);
      if (uuid != null && uuid.isNotEmpty) {
        await _preferences.upsertWorkoutWritebackMapping(
          record.externalId,
          uuid,
        );
      } else if (kDebugMode) {
        debugPrint(
          '[WorkoutWrite] uuid capture failed for ${record.externalId}; treating write as success',
        );
      }
      return const WorkoutWriteResult.success();
    } catch (error, stackTrace) {
      debugPrint(
        'HealthWorkoutWriteService upsert failed: $error\n$stackTrace',
      );
      return WorkoutWriteResult.failure(
        errorCode: _mapErrorCode(error),
        retryable: true,
        message: error.toString(),
      );
    }
  }

  @override
  Future<bool> deleteWorkout(String externalId) async {
    final capability = await getCapabilities();
    if (!capability.supported) return false;
    try {
      final uuidMap = await _preferences.getWorkoutWritebackMappings();
      final uuid = uuidMap[externalId];
      if (uuid == null || uuid.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[WorkoutWrite] delete noop: no mapping for $externalId, treating as success',
          );
        }
        await _preferences.removeWorkoutWritebackMapping(externalId);
        return true;
      }
      await _ensureConfigured();
      final success = await _health.deleteByUUID(
        uuid: uuid,
        type: _workoutDeleteType(capability.platform),
      );
      if (success) {
        await _deleteStoredHeartRateSamples(externalId: externalId);
        await _preferences.removeWorkoutWritebackMapping(externalId);
      }
      if (!success && kDebugMode) {
        debugPrint('[WorkoutWrite] delete failed for $externalId (uuid=$uuid)');
      }
      return success;
    } catch (error, stackTrace) {
      debugPrint('deleteWorkout failed: $error\n$stackTrace');
      return false;
    }
  }

  @override
  Future<bool> deleteWorkoutByRecord(
    WorkoutRecord record, {
    String? keepUuid,
  }) async {
    final capability = await getCapabilities();
    if (!capability.supported) return false;
    try {
      await _ensureConfigured();
      final platform = capability.platform;
      final mappings = await _preferences.getWorkoutWritebackMappings();
      final mappedUuid = mappings[record.externalId];

      var lookupFailed = false;
      List<HealthDataPoint> matches = const [];
      try {
        matches = await _locateMatchingWorkouts(
          record,
          platform,
          allowSameStartFallback: keepUuid != null && keepUuid.isNotEmpty,
          throwOnError: true,
        );
      } catch (error, stackTrace) {
        lookupFailed = true;
        debugPrint('deleteWorkoutByRecord lookup failed: $error\n$stackTrace');
      }

      final hasUnresolvedMatches = matches.any(
        (point) =>
            point.uuid.isEmpty && _hustlMatchStrength(point, record) >= 0,
      );
      final candidateUuids = <String>{
        for (final point in matches)
          if (point.uuid.isNotEmpty &&
              point.uuid != keepUuid &&
              _hustlMatchStrength(point, record) >= 0)
            point.uuid,
      };

      if (mappedUuid != null &&
          mappedUuid.isNotEmpty &&
          mappedUuid != keepUuid) {
        candidateUuids.add(mappedUuid);
      }

      if (candidateUuids.isEmpty) {
        if (lookupFailed) {
          return false;
        }
        // A matching workout can appear before its UUID is queryable.
        // Return false so queue-driven deletes retry after propagation.
        if (hasUnresolvedMatches) {
          return false;
        }
        return await _deleteStoredHeartRateSamples(
          externalId: record.externalId,
        );
      }

      var allDeleted = true;
      final deletedUuids = <String>{};
      for (final uuid in candidateUuids) {
        final deleted = await _health.deleteByUUID(
          uuid: uuid,
          type: _workoutDeleteType(platform),
        );
        if (!deleted) {
          allDeleted = false;
        } else {
          deletedUuids.add(uuid);
        }
      }

      if (mappedUuid != null &&
          mappedUuid.isNotEmpty &&
          mappedUuid != keepUuid &&
          deletedUuids.contains(mappedUuid)) {
        await _preferences.removeWorkoutWritebackMapping(record.externalId);
      }

      if (allDeleted && hasUnresolvedMatches) {
        // Mixed matches can include UUID-resolved and UUID-less entries in the
        // same read window. Retry so unresolved entries can become queryable
        // and be reconciled instead of silently leaving duplicates behind.
        return false;
      }

      if (allDeleted) {
        final cleanedHeartRateSamples = await _deleteStoredHeartRateSamples(
          externalId: record.externalId,
        );
        if (!cleanedHeartRateSamples && kDebugMode) {
          debugPrint(
            '[WorkoutWrite] workout delete succeeded but HR cleanup failed '
            'for ${record.externalId}; treating delete as success',
          );
        }
      }

      return allDeleted;
    } catch (error, stackTrace) {
      debugPrint('deleteWorkoutByRecord failed: $error\n$stackTrace');
      return false;
    }
  }

  String _buildTitle(WorkoutRecord record) {
    final type = record.activityType.name;
    return 'Hustl ${type.toUpperCase()} ${record.sessionId}';
  }

  HealthDataType? _workoutDeleteType(WorkoutWritePlatform platform) {
    return platform == WorkoutWritePlatform.iosHealthKit
        ? HealthDataType.WORKOUT
        : null;
  }

  Future<void> _writeHeartRateSamples(
    WorkoutRecord record,
    WorkoutWriteCapability capability,
  ) async {
    if (!capability.grantedScopes.contains(WorkoutPermissionScope.heartRate)) {
      return;
    }

    final averageBpm = _normalizeHeartRate(record.averageHeartRateBpm);
    final maxBpm = _normalizeHeartRate(record.maxHeartRateBpm);
    if (averageBpm == null && maxBpm == null) {
      return;
    }

    final midpoint = DateTime.fromMillisecondsSinceEpoch(
      (record.startedAt.millisecondsSinceEpoch +
              record.endedAt.millisecondsSinceEpoch) ~/
          2,
      isUtc: true,
    );
    final samples = <({double bpm, DateTime timestamp})>[
      if (averageBpm != null) (bpm: averageBpm, timestamp: midpoint),
      if (maxBpm != null) (bpm: maxBpm, timestamp: record.endedAt.toUtc()),
    ];
    final writtenSampleEpochs = <int>{};

    for (final sample in samples) {
      try {
        final wrote = await _health.writeHealthData(
          value: sample.bpm,
          unit: HealthDataUnit.BEATS_PER_MINUTE,
          type: HealthDataType.HEART_RATE,
          startTime: sample.timestamp,
          endTime: sample.timestamp,
        );
        if (wrote) {
          writtenSampleEpochs.add(
            sample.timestamp.toUtc().millisecondsSinceEpoch,
          );
        }
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint(
            '[WorkoutWrite] heart-rate write failed for ${record.externalId}: '
            '$error\n$stackTrace',
          );
        }
      }
    }

    if (writtenSampleEpochs.isEmpty) {
      return;
    }
    await _storeHeartRateMarkers(
      externalId: record.externalId,
      sampleEpochs: writtenSampleEpochs.toList(growable: false),
    );
  }

  double? _normalizeHeartRate(double? value) {
    if (value == null || value.isNaN || value.isInfinite || value <= 0) {
      return null;
    }
    return double.parse(value.toStringAsFixed(1));
  }

  Future<bool> _deleteStoredHeartRateSamples({
    required String externalId,
  }) async {
    final markerEpochs = await _getHeartRateMarkersFor(externalId);
    if (markerEpochs.isEmpty) {
      // Avoid broad timestamp-based deletes when we do not have exact markers
      // written by this service.
      return true;
    }
    final timestamps = markerEpochs
        .map((epoch) => DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true))
        .toSet()
        .toList(growable: false);

    var hadCleanupFailure = false;
    for (final timestamp in timestamps) {
      try {
        final deleted = await _health.delete(
          type: HealthDataType.HEART_RATE,
          startTime: timestamp,
          endTime: timestamp,
        );
        if (!deleted) {
          hadCleanupFailure = true;
        }
      } catch (error, stackTrace) {
        hadCleanupFailure = true;
        if (kDebugMode) {
          debugPrint(
            '[WorkoutWrite] heart-rate cleanup failed for $externalId at $timestamp: '
            '$error\n$stackTrace',
          );
        }
      }
    }
    if (hadCleanupFailure) {
      return false;
    }
    await _clearHeartRateMarkers(externalId);
    return true;
  }

  Future<Map<String, List<int>>> _getHeartRateMarkerMap() async {
    final raw = await _preferences.getRawString(_heartRateMarkerStorageKey);
    if (raw == null || raw.isEmpty) return <String, List<int>>{};
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) {
        return <String, List<int>>{};
      }
      final parsed = <String, List<int>>{};
      decoded.forEach((key, value) {
        if (value is List) {
          parsed[key] = value
              .whereType<num>()
              .map((v) => v.toInt())
              .toSet()
              .toList(growable: false);
        }
      });
      return parsed;
    } catch (_) {
      return <String, List<int>>{};
    }
  }

  Future<List<int>> _getHeartRateMarkersFor(String externalId) async {
    final map = await _getHeartRateMarkerMap();
    return map[externalId] ?? const <int>[];
  }

  Future<void> _storeHeartRateMarkers({
    required String externalId,
    required List<int> sampleEpochs,
  }) async {
    final map = await _getHeartRateMarkerMap();
    final merged = <int>{
      ...(map[externalId] ?? const <int>[]),
      ...sampleEpochs,
    }.toList(growable: false)..sort();
    map[externalId] = merged;
    await _preferences.setRawString(
      _heartRateMarkerStorageKey,
      json.encode(map),
    );
  }

  Future<void> _clearHeartRateMarkers(String externalId) async {
    final map = await _getHeartRateMarkerMap();
    if (!map.containsKey(externalId)) return;
    map.remove(externalId);
    if (map.isEmpty) {
      await _preferences.setRawString(_heartRateMarkerStorageKey, null);
      return;
    }
    await _preferences.setRawString(
      _heartRateMarkerStorageKey,
      json.encode(map),
    );
  }

  Future<void> _ensureConfigured() async {
    try {
      await _health.configure();
    } catch (_) {
      // ignoring configure errors; plugin handles repeated configure calls
    }
  }

  Future<bool> _preEmptiveDelete(
    WorkoutRecord record,
    WorkoutWritePlatform platform,
  ) async {
    if (kIsWeb) return true;
    try {
      await _ensureConfigured();
      final mappings = await _preferences.getWorkoutWritebackMappings();
      final existingUuid = mappings[record.externalId];
      final located = await _locateMatchingWorkouts(record, platform);
      final stronglyMatchedUuids = <String>{
        for (final point in located)
          if (point.uuid.isNotEmpty && _hustlMatchStrength(point, record) > 0)
            point.uuid,
      };
      // Source-only matches are low-confidence. We only delete them when they
      // are tied to a single non-watch device (phone-authored duplicates) or
      // to the mapped UUID's device.
      final sourceOnlyUuids = _collectSafeSourceOnlyUuids(
        located,
        record,
        preferredUuid: existingUuid,
      );

      final existingIsKnownMatch =
          existingUuid != null &&
          existingUuid.isNotEmpty &&
          located.any(
            (point) =>
                point.uuid == existingUuid &&
                _hustlMatchStrength(point, record) >= 0,
          );

      final candidateUuids = <String>{
        if (existingIsKnownMatch) existingUuid,
        ...stronglyMatchedUuids,
        ...sourceOnlyUuids,
      };

      if (candidateUuids.isEmpty) return true;

      var removedMapping = false;
      for (final uuid in candidateUuids) {
        bool deleted = false;
        try {
          deleted = await _health.deleteByUUID(
            uuid: uuid,
            type: _workoutDeleteType(platform),
          );
        } catch (error, stackTrace) {
          debugPrint(
            'preEmptiveDelete deleteByUUID failed: $error\n$stackTrace',
          );
          deleted = false;
        }
        if (deleted && !removedMapping) {
          removedMapping = true;
          await _preferences.removeWorkoutWritebackMapping(record.externalId);
        }
      }

      // Verify no matching workouts remain in the current timestamp window so
      // retries don't multiply duplicates when deletes are flaky.
      for (final delay in _preDeleteVerificationDelays) {
        if (delay > Duration.zero) {
          await Future.delayed(delay);
        }
        final remaining = await _locateMatchingWorkouts(record, platform);
        if (remaining.isEmpty) {
          return true;
        }
      }
      return false;
    } catch (error, stackTrace) {
      debugPrint('preEmptiveDelete failed: $error\n$stackTrace');
      return false;
    }
  }

  Future<String?> _captureUuid(
    WorkoutRecord record,
    WorkoutWritePlatform platform,
  ) async {
    try {
      for (final delay in _captureRetryDelays) {
        if (delay > Duration.zero) {
          await Future.delayed(delay);
        }
        final matches = await _locateMatchingWorkouts(record, platform);
        if (matches.isEmpty) {
          continue;
        }
        final candidates = <HealthDataPoint>[
          for (final point in matches)
            if (point.uuid.isNotEmpty &&
                _hustlMatchStrength(point, record) >= 0)
              point,
        ];
        if (candidates.isEmpty) {
          continue;
        }
        for (final point in candidates) {
          if (_hustlMatchStrength(point, record) > 0) {
            return point.uuid;
          }
        }
        if (candidates.length == 1) {
          final deviceId = _normalizeSourceDeviceId(
            candidates.first.sourceDeviceId,
          );
          if (deviceId != null && !_isWatchLikeDeviceId(deviceId)) {
            return candidates.first.uuid;
          }
        }
      }
    } catch (error, stackTrace) {
      debugPrint('captureUuid failed: $error\n$stackTrace');
    }
    return null;
  }

  Future<List<HealthDataPoint>> _locateMatchingWorkouts(
    WorkoutRecord record,
    WorkoutWritePlatform platform, {
    bool allowSameStartFallback = false,
    bool throwOnError = false,
  }) async {
    if (kIsWeb) return const [];
    final desiredType = _mapActivity(record.activityType, platform);
    if (desiredType == null) return const [];

    try {
      await _ensureConfigured();
      final windowStart = record.startedAt.subtract(_lookupWindowPadding);
      final windowEnd = record.endedAt.add(_lookupWindowPadding);
      final points = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.WORKOUT],
        startTime: windowStart,
        endTime: windowEnd,
      );
      final matches = <HealthDataPoint>[];
      for (final point in points) {
        if (point.type != HealthDataType.WORKOUT) continue;

        // Use `WorkoutHealthValue.workoutActivityType` for type matching. The
        // `workoutSummary.workoutType` string uses a platform-specific format
        // (e.g. iOS returns lowerCamelCase like `functionalStrengthTraining`)
        // that does not match `HealthWorkoutActivityType.name`.
        final value = point.value;
        if (value is WorkoutHealthValue &&
            value.workoutActivityType != desiredType) {
          continue;
        }

        final startDiff = point.dateFrom
            .toUtc()
            .difference(record.startedAt.toUtc())
            .abs();
        final endDiff = point.dateTo
            .toUtc()
            .difference(record.endedAt.toUtc())
            .abs();
        final sameStartFallback =
            allowSameStartFallback &&
            startDiff <= _timestampTolerance &&
            _isLikelyHustlWorkout(point, record);
        if (startDiff > _timestampTolerance ||
            (endDiff > _timestampTolerance && !sameStartFallback)) {
          continue;
        }
        if (!_isLikelyHustlWorkout(point, record)) {
          continue;
        }
        matches.add(point);
      }
      // Prefer "strong" matches (e.g., those that carry Hustl metadata/title)
      // so UUID capture and deletes don't accidentally target watch-captured
      // workouts that happen to share similar timestamps.
      matches.sort((a, b) {
        final aStrength = _hustlMatchStrength(a, record);
        final bStrength = _hustlMatchStrength(b, record);
        if (aStrength != bStrength) {
          return bStrength.compareTo(aStrength);
        }
        return a.dateFrom.toUtc().compareTo(b.dateFrom.toUtc());
      });
      return matches;
    } catch (error, stackTrace) {
      debugPrint('locateMatchingWorkouts failed: $error\n$stackTrace');
      if (throwOnError) {
        rethrow;
      }
      return const [];
    }
  }

  HealthWorkoutActivityType? _mapActivity(
    WorkoutActivityType type,
    WorkoutWritePlatform platform,
  ) {
    switch (type) {
      case WorkoutActivityType.strength:
        return platform == WorkoutWritePlatform.androidHealthConnect
            ? HealthWorkoutActivityType.STRENGTH_TRAINING
            : HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING;
      case WorkoutActivityType.hiit:
        return HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING;
      case WorkoutActivityType.cardio:
        return platform == WorkoutWritePlatform.androidHealthConnect
            ? HealthWorkoutActivityType.OTHER
            : HealthWorkoutActivityType.MIXED_CARDIO;
      case WorkoutActivityType.cycling:
        return HealthWorkoutActivityType.BIKING;
      case WorkoutActivityType.running:
        return HealthWorkoutActivityType.RUNNING;
      case WorkoutActivityType.yoga:
        return HealthWorkoutActivityType.YOGA;
      case WorkoutActivityType.mobility:
        return HealthWorkoutActivityType.FLEXIBILITY;
      case WorkoutActivityType.other:
        return HealthWorkoutActivityType.OTHER;
    }
  }

  bool _isLikelyHustlWorkout(HealthDataPoint point, WorkoutRecord record) {
    final metadata = point.metadata ?? const <String, dynamic>{};
    final sessionIdLower = record.sessionId.toLowerCase();
    final externalIdLower = record.externalId.toLowerCase();

    final platformTag =
        metadata['platform']?.toString().toLowerCase().trim() ?? '';
    if (platformTag == 'hustl') return true;

    final syncIdentifier = metadata['HKMetadataKeySyncIdentifier']
        ?.toString()
        .trim();
    if (syncIdentifier == record.sessionId) return true;

    final externalUuid = metadata['HKMetadataKeyExternalUUID']
        ?.toString()
        .trim();
    if (externalUuid == record.externalId) return true;

    final titleLikeFields = <String>[
      metadata['name']?.toString() ?? '',
      metadata['title']?.toString() ?? '',
      metadata['HKWorkoutBrandName']?.toString() ?? '',
      metadata['HKMetadataKeyWorkoutBrandName']?.toString() ?? '',
    ];
    for (final field in titleLikeFields) {
      final normalized = field.toLowerCase();
      if (normalized.contains('hustl') ||
          normalized.contains(sessionIdLower) ||
          normalized.contains(externalIdLower)) {
        return true;
      }
    }

    final sourceId = point.sourceId.toLowerCase();
    final sourceName = point.sourceName.toLowerCase();
    if (sourceId.contains('hustl') || sourceName.contains('hustl')) {
      return true;
    }

    final brandName =
        metadata['HKMetadataKeyWorkoutBrandName']?.toString().toLowerCase() ??
        '';
    return brandName.contains('hustl');
  }

  /// Returns a confidence score that the workout was created by Hustl writeback
  /// (phone) rather than merely being sourced from Hustl (e.g., watch capture).
  ///
  /// Higher is more confident. `0` means "only matched by source id/name".
  int _hustlMatchStrength(HealthDataPoint point, WorkoutRecord record) {
    final metadata = point.metadata ?? const <String, dynamic>{};
    final sessionIdLower = record.sessionId.toLowerCase();
    final externalIdLower = record.externalId.toLowerCase();

    final externalUuid = metadata['HKMetadataKeyExternalUUID']
        ?.toString()
        .trim();
    if (externalUuid != null && externalUuid == record.externalId) {
      return 4;
    }

    final syncIdentifier = metadata['HKMetadataKeySyncIdentifier']
        ?.toString()
        .trim();
    if (syncIdentifier != null && syncIdentifier == record.sessionId) {
      return 3;
    }

    final platformTag =
        metadata['platform']?.toString().toLowerCase().trim() ?? '';
    if (platformTag == 'hustl') return 2;

    final titleLikeFields = <String>[
      metadata['name']?.toString() ?? '',
      metadata['title']?.toString() ?? '',
      metadata['HKWorkoutBrandName']?.toString() ?? '',
      metadata['HKMetadataKeyWorkoutBrandName']?.toString() ?? '',
      point.sourceName,
    ];
    for (final field in titleLikeFields) {
      final normalized = field.toLowerCase();
      if (normalized.contains(sessionIdLower) ||
          normalized.contains(externalIdLower)) {
        return 2;
      }
    }

    final brandName =
        metadata['HKMetadataKeyWorkoutBrandName']?.toString().toLowerCase() ??
        '';
    if (brandName.contains(sessionIdLower) ||
        brandName.contains(externalIdLower)) {
      return 2;
    }
    if (brandName.contains('hustl')) return 1;

    final sourceId = point.sourceId.toLowerCase();
    final sourceName = point.sourceName.toLowerCase();
    if (sourceId.contains('hustl') || sourceName.contains('hustl')) {
      return 0;
    }

    return -1;
  }

  Set<String> _collectSafeSourceOnlyUuids(
    List<HealthDataPoint> points,
    WorkoutRecord record, {
    String? preferredUuid,
  }) {
    final sourceOnlyPoints = <HealthDataPoint>[
      for (final point in points)
        if (point.uuid.isNotEmpty && _hustlMatchStrength(point, record) == 0)
          point,
    ];
    if (sourceOnlyPoints.isEmpty) {
      return const <String>{};
    }

    final byUuid = <String, HealthDataPoint>{
      for (final point in sourceOnlyPoints) point.uuid: point,
    };

    final preferredPoint = preferredUuid == null || preferredUuid.isEmpty
        ? null
        : byUuid[preferredUuid];
    if (preferredPoint != null) {
      final preferredDevice = _normalizeSourceDeviceId(
        preferredPoint.sourceDeviceId,
      );
      if (preferredDevice == null || _isWatchLikeDeviceId(preferredDevice)) {
        return const <String>{};
      }
      return {
        for (final point in sourceOnlyPoints)
          if (_normalizeSourceDeviceId(point.sourceDeviceId) == preferredDevice)
            point.uuid,
      };
    }

    final deviceIds = <String>{
      for (final point in sourceOnlyPoints)
        if (_normalizeSourceDeviceId(point.sourceDeviceId) case final id?) id,
    };
    if (deviceIds.length != 1) {
      return const <String>{};
    }

    final soleDevice = deviceIds.first;
    if (_isWatchLikeDeviceId(soleDevice)) {
      return const <String>{};
    }

    return {
      for (final point in sourceOnlyPoints)
        if (_normalizeSourceDeviceId(point.sourceDeviceId) == soleDevice)
          point.uuid,
    };
  }

  String? _normalizeSourceDeviceId(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    return normalized;
  }

  bool _isWatchLikeDeviceId(String deviceId) {
    return deviceId.contains('watch');
  }

  List<HealthDataType> _permissionTypes(Set<WorkoutPermissionScope> scopes) {
    final types = <HealthDataType>[];
    if (scopes.contains(WorkoutPermissionScope.workouts)) {
      types.add(HealthDataType.WORKOUT);
    }
    if (scopes.contains(WorkoutPermissionScope.energy)) {
      types.add(HealthDataType.ACTIVE_ENERGY_BURNED);
    }
    if (scopes.contains(WorkoutPermissionScope.distance)) {
      types.add(HealthDataType.DISTANCE_CYCLING);
      types.add(HealthDataType.DISTANCE_WALKING_RUNNING);
    }
    if (scopes.contains(WorkoutPermissionScope.heartRate)) {
      types.add(HealthDataType.HEART_RATE);
    }
    return types;
  }

  String _mapErrorCode(Object error) {
    if (error is HealthException) {
      return error.cause;
    }
    if (error is PlatformException) {
      return error.code;
    }
    return 'unknown';
  }
}
