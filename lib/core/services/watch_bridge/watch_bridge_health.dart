class WatchHealthSummary {
  const WatchHealthSummary({
    required this.id,
    required this.sessionId,
    this.recordingStartMs,
    this.recordingEndMs,
    this.durationSeconds,
    this.averageHeartRateBpm,
    this.maxHeartRateBpm,
    this.activeEnergyKilocalories,
    this.hkWorkoutUuid,
  });

  final String id;
  final String? sessionId;
  final int? recordingStartMs;
  final int? recordingEndMs;
  final int? durationSeconds;
  final double? averageHeartRateBpm;
  final double? maxHeartRateBpm;
  final double? activeEnergyKilocalories;
  final String? hkWorkoutUuid;

  static WatchHealthSummary? tryParse(Map<String, dynamic> map) {
    final type = map['type'];
    if (type != 'health_summary') return null;
    final id = map['id'];
    if (id is! String) return null;

    final metricsRaw = map['metrics'];
    final metrics = metricsRaw is Map
        ? Map<String, dynamic>.from(metricsRaw)
        : const {};
    final platformRaw = map['platformRecord'];
    final platform = platformRaw is Map
        ? Map<String, dynamic>.from(platformRaw)
        : const {};

    int? metricInt(List<String> keys) {
      for (final key in keys) {
        final value = metrics[key];
        if (value is num) return value.toInt();
      }
      return null;
    }

    double? metricDouble(List<String> keys) {
      for (final key in keys) {
        final value = metrics[key];
        if (value is num) return value.toDouble();
      }
      return null;
    }

    return WatchHealthSummary(
      id: id,
      sessionId: map['sessionId'] as String?,
      recordingStartMs: (map['recordingStartMs'] as num?)?.toInt(),
      recordingEndMs: (map['recordingEndMs'] as num?)?.toInt(),
      durationSeconds: metricInt(const ['durationSec', 'durationSeconds']),
      averageHeartRateBpm: metricDouble(const [
        'avgHr',
        'avgBpm',
        'averageHr',
        'averageHeartRateBpm',
      ]),
      maxHeartRateBpm: metricDouble(const [
        'maxHr',
        'maxBpm',
        'maximumHr',
        'maxHeartRateBpm',
      ]),
      activeEnergyKilocalories: metricDouble(const [
        'activeEnergyKcal',
        'activeEnergyKilocalories',
        'activeEnergy',
      ]),
      hkWorkoutUuid:
          platform['hkWorkoutUUID'] as String? ??
          platform['hkWorkoutUuid'] as String?,
    );
  }
}

class WatchHealthRecordingState {
  const WatchHealthRecordingState({
    required this.id,
    required this.sessionId,
    required this.isRecording,
    this.hkWorkoutUuid,
    this.recordingStartMs,
    this.error,
  });

  final String id;
  final String? sessionId;
  final bool isRecording;
  final String? hkWorkoutUuid;
  final int? recordingStartMs;
  final String? error;

  bool get hasError => error != null && error!.trim().isNotEmpty;

  static WatchHealthRecordingState? tryParse(Map<String, dynamic> map) {
    final type = map['type'];
    if (type != 'health_recording_start' && type != 'health_recording_stop') {
      return null;
    }
    final id = map['id'];
    if (id is! String) return null;

    final platformRaw = map['platformRecord'];
    final platform = platformRaw is Map
        ? Map<String, dynamic>.from(platformRaw)
        : const {};

    return WatchHealthRecordingState(
      id: id,
      sessionId: map['sessionId'] as String?,
      isRecording: type == 'health_recording_start',
      hkWorkoutUuid:
          platform['hkWorkoutUUID'] as String? ??
          platform['hkWorkoutUuid'] as String?,
      recordingStartMs: (map['recordingStartMs'] as num?)?.toInt(),
      error: map['error'] as String? ?? map['recordingError'] as String?,
    );
  }
}
