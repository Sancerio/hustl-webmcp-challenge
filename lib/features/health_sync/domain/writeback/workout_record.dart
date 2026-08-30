import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Supported workout activity categories for health writeback.
enum WorkoutActivityType {
  strength,
  hiit,
  cardio,
  cycling,
  running,
  yoga,
  mobility,
  other,
}

/// Canonical representation of a Hustl workout session ready for platform writeback.
class WorkoutRecord {
  WorkoutRecord({
    required this.sessionId,
    required this.activityType,
    required this.startedAt,
    required this.endedAt,
    required this.duration,
    this.energyKilocalories,
    this.distanceMeters,
    this.averageHeartRateBpm,
    this.maxHeartRateBpm,
    this.steps,
    Map<String, String>? metadata,
  }) : metadata = Map.unmodifiable(metadata ?? const {});

  /// Hustl workout/session identifier.
  final String sessionId;

  /// Activity category mapped to HealthKit / Health Connect.
  final WorkoutActivityType activityType;

  /// Workout start time in UTC.
  final DateTime startedAt;

  /// Workout end time in UTC.
  final DateTime endedAt;

  /// Workout duration in seconds.
  final int duration;

  /// Total active energy burned if available.
  final double? energyKilocalories;

  /// Total distance covered in meters.
  final double? distanceMeters;

  /// Average heart rate in BPM.
  final double? averageHeartRateBpm;

  /// Maximum heart rate in BPM.
  final double? maxHeartRateBpm;

  /// Total counted steps when provided.
  final int? steps;

  /// Supplemental metadata that should be mirrored on the health platform.
  final Map<String, String> metadata;

  /// Stable external identifier used for idempotent writes.
  String get externalId => 'hustl:$sessionId';

  /// Prepare a stable canonical payload for hashing/idempotency comparisons.
  ///
  /// Keys are sorted to guarantee deterministic output across runs.
  Map<String, Object?> toCanonicalMap() {
    final map = SplayTreeMap<String, Object?>();
    map['sessionId'] = sessionId;
    map['activityType'] = activityType.name;
    map['startedAt'] = startedAt.toUtc().toIso8601String();
    map['endedAt'] = endedAt.toUtc().toIso8601String();
    map['duration'] = duration;
    map['energyKilocalories'] = energyKilocalories;
    map['distanceMeters'] = distanceMeters;
    map['averageHeartRateBpm'] = averageHeartRateBpm;
    map['maxHeartRateBpm'] = maxHeartRateBpm;
    map['steps'] = steps;
    if (metadata.isNotEmpty) {
      map['metadata'] = SplayTreeMap<String, String>.from(metadata);
    }
    return map;
  }

  /// Derive a deterministic hash of the canonical payload for change detection.
  String payloadHash() {
    final canonical = toCanonicalMap();
    // Metadata is not currently written by the `health` plugin for workouts.
    // Treat it as non-material for idempotency so background sync updates
    // (e.g., `lastUpdatedAt`) do not cause duplicate workout writes.
    canonical.remove('metadata');
    final encoded = utf8.encode(jsonEncode(canonical));
    final digest = sha1.convert(encoded);
    return digest.toString();
  }

  WorkoutRecord copyWith({
    String? sessionId,
    WorkoutActivityType? activityType,
    DateTime? startedAt,
    DateTime? endedAt,
    int? duration,
    double? energyKilocalories,
    double? distanceMeters,
    double? averageHeartRateBpm,
    double? maxHeartRateBpm,
    int? steps,
    Map<String, String>? metadata,
  }) {
    return WorkoutRecord(
      sessionId: sessionId ?? this.sessionId,
      activityType: activityType ?? this.activityType,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      duration: duration ?? this.duration,
      energyKilocalories: energyKilocalories ?? this.energyKilocalories,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      averageHeartRateBpm: averageHeartRateBpm ?? this.averageHeartRateBpm,
      maxHeartRateBpm: maxHeartRateBpm ?? this.maxHeartRateBpm,
      steps: steps ?? this.steps,
      metadata: metadata ?? this.metadata,
    );
  }
}
