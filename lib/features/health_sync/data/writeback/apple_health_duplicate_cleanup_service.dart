import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:health/health.dart';

import '../../../../core/services/preferences_service.dart';
import 'hustl_workout_authorship.dart';

const Duration _timestampTolerance = Duration(seconds: 90);
final RegExp _nonAlphaNumeric = RegExp(r'[^a-z0-9]');

class AppleHealthDuplicateCleanupResult {
  const AppleHealthDuplicateCleanupResult({
    required this.supported,
    required this.permissionsGranted,
    required this.scannedCount,
    required this.hustlWorkoutCount,
    required this.duplicateGroupCount,
    required this.deletedCount,
    required this.errors,
  });

  final bool supported;
  final bool permissionsGranted;
  final int scannedCount;
  final int hustlWorkoutCount;
  final int duplicateGroupCount;
  final int deletedCount;
  final List<String> errors;
}

class AppleHealthDuplicateCleanupService {
  AppleHealthDuplicateCleanupService({
    Health? health,
    PreferencesService? preferences,
    bool? iosOverride,
  }) : _health = health ?? Health(),
       _preferences = preferences ?? PreferencesService(),
       _iosOverride = iosOverride;

  final Health _health;
  final PreferencesService _preferences;
  final bool? _iosOverride;

  Future<AppleHealthDuplicateCleanupResult> cleanupDuplicates({
    required DateTime start,
    required DateTime end,
    bool dryRun = false,
  }) async {
    if (!_isSupported) {
      return const AppleHealthDuplicateCleanupResult(
        supported: false,
        permissionsGranted: false,
        scannedCount: 0,
        hustlWorkoutCount: 0,
        duplicateGroupCount: 0,
        deletedCount: 0,
        errors: [],
      );
    }

    final errors = <String>[];

    try {
      await _health.configure();
    } catch (_) {
      // Configure failures are non-fatal; plugin can still work.
    }

    bool permissionsGranted = false;
    try {
      permissionsGranted = await _health.requestAuthorization(
        const [HealthDataType.WORKOUT],
        permissions: const [HealthDataAccess.READ_WRITE],
      );
    } catch (e) {
      errors.add('requestAuthorization failed: $e');
      permissionsGranted = false;
    }

    if (!permissionsGranted) {
      return AppleHealthDuplicateCleanupResult(
        supported: true,
        permissionsGranted: false,
        scannedCount: 0,
        hustlWorkoutCount: 0,
        duplicateGroupCount: 0,
        deletedCount: 0,
        errors: errors,
      );
    }

    List<HealthDataPoint> points = const [];
    try {
      points = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.WORKOUT],
        startTime: start,
        endTime: end,
      );
    } catch (e) {
      errors.add('getHealthDataFromTypes failed: $e');
      points = const [];
    }

    final workouts = points
        .where((point) => point.type == HealthDataType.WORKOUT)
        .where((point) => point.uuid.isNotEmpty)
        .where(isLikelyHustlWorkout)
        .toList();

    workouts.sort((a, b) => a.dateFrom.toUtc().compareTo(b.dateFrom.toUtc()));

    final mappings = await _preferences.getWorkoutWritebackMappings();
    final mappedUuids = mappings.values.where((v) => v.isNotEmpty).toSet();

    final clusters = _clusterDuplicates(workouts);

    int deletedCount = 0;
    int duplicateGroups = 0;

    for (final cluster in clusters) {
      if (cluster.length <= 1) continue;
      duplicateGroups += 1;

      final keepUuids = <String>{
        ...cluster
            .where((point) => mappedUuids.contains(point.uuid))
            .map((point) => point.uuid),
      };
      if (keepUuids.isEmpty) {
        keepUuids.add(cluster.first.uuid);
      }
      for (final point in cluster) {
        if (keepUuids.contains(point.uuid)) continue;

        if (dryRun) {
          deletedCount += 1;
          continue;
        }

        try {
          final deleted = await _health.deleteByUUID(
            uuid: point.uuid,
            type: HealthDataType.WORKOUT,
          );
          if (deleted) {
            deletedCount += 1;
          } else {
            errors.add('deleteByUUID returned false for uuid=${point.uuid}');
          }
        } catch (e) {
          errors.add('deleteByUUID failed for uuid=${point.uuid}: $e');
        }
      }
    }

    return AppleHealthDuplicateCleanupResult(
      supported: true,
      permissionsGranted: permissionsGranted,
      scannedCount: points.length,
      hustlWorkoutCount: workouts.length,
      duplicateGroupCount: duplicateGroups,
      deletedCount: deletedCount,
      errors: errors,
    );
  }

  List<List<HealthDataPoint>> _clusterDuplicates(
    List<HealthDataPoint> workouts,
  ) {
    if (workouts.isEmpty) return const [];

    final clusters = <List<HealthDataPoint>>[];
    var current = <HealthDataPoint>[workouts.first];

    for (var i = 1; i < workouts.length; i++) {
      final point = workouts[i];
      if (_isDuplicateOf(current.first, point)) {
        current.add(point);
        continue;
      }
      clusters.add(current);
      current = <HealthDataPoint>[point];
    }
    clusters.add(current);
    return clusters;
  }

  bool _isDuplicateOf(HealthDataPoint a, HealthDataPoint b) {
    final aTypeKey = _workoutTypeKey(a);
    final bTypeKey = _workoutTypeKey(b);
    if (aTypeKey != null && bTypeKey != null && aTypeKey != bTypeKey) {
      return false;
    }

    final aValue = a.value;
    final bValue = b.value;
    if (aValue is WorkoutHealthValue && bValue is WorkoutHealthValue) {
      if (aValue.workoutActivityType != bValue.workoutActivityType) {
        return false;
      }
    }

    final startDiff = a.dateFrom.toUtc().difference(b.dateFrom.toUtc()).abs();
    final endDiff = a.dateTo.toUtc().difference(b.dateTo.toUtc()).abs();
    return startDiff <= _timestampTolerance && endDiff <= _timestampTolerance;
  }

  String? _workoutTypeKey(HealthDataPoint point) {
    final value = point.value;
    final raw = value is WorkoutHealthValue
        ? value.workoutActivityType.name
        : (point.workoutSummary?.workoutType ?? '');
    if (raw.isEmpty) return null;
    return raw.toLowerCase().replaceAll(_nonAlphaNumeric, '');
  }

  bool get _isSupported {
    if (kIsWeb) return false;
    final override = _iosOverride;
    if (override != null) return override;
    return defaultTargetPlatform == TargetPlatform.iOS;
  }
}
