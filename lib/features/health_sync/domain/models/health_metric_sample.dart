import 'package:equatable/equatable.dart';

enum HealthMetricType {
  weight,
  height,
  bodyMassIndex,
  bodyFatPercentage,
  basalMetabolicRate,
  waterIntake,
  steps,
  activeEnergyBurned,
  exerciseTime,
  heartRate,
  walkingHeartRate,
  heartRateVariabilitySdnn,
  heartRateVariabilityRmssd,
  restingHeartRate,
  respiratoryRate,
  bloodOxygen,
  bodyTemperature,
  sleepAsleep,
  sleepInBed,
  sleepRem,
  sleepDeep,
  sleepLight,
  sleepAwake,
  workoutEnergy,
  workoutDistance,
  workoutDuration,
  distanceWalkingRunning,
  distanceCycling,
  distanceSwimming,
}

enum HealthDataQuality { measured, userEntered, derived, unknown }

enum HealthDataCompleteness { complete, partial, ongoing, unknown }

extension HealthDataQualityWire on HealthDataQuality {
  String get wireName => switch (this) {
    HealthDataQuality.measured => 'measured',
    HealthDataQuality.userEntered => 'user_entered',
    HealthDataQuality.derived => 'derived',
    HealthDataQuality.unknown => 'unknown',
  };
}

extension HealthMetricTypeLabel on HealthMetricType {
  String get label {
    switch (this) {
      case HealthMetricType.weight:
        return 'Weight';
      case HealthMetricType.height:
        return 'Height';
      case HealthMetricType.bodyMassIndex:
        return 'BMI';
      case HealthMetricType.bodyFatPercentage:
        return 'Body Fat %';
      case HealthMetricType.basalMetabolicRate:
        return 'BMR';
      case HealthMetricType.waterIntake:
        return 'Water Intake';
      case HealthMetricType.steps:
        return 'Steps';
      case HealthMetricType.activeEnergyBurned:
        return 'Active Energy';
      case HealthMetricType.exerciseTime:
        return 'Exercise Time';
      case HealthMetricType.heartRate:
        return 'Heart Rate';
      case HealthMetricType.walkingHeartRate:
        return 'Walking Heart Rate';
      case HealthMetricType.heartRateVariabilitySdnn:
        return 'HRV (SDNN)';
      case HealthMetricType.heartRateVariabilityRmssd:
        return 'HRV (RMSSD)';
      case HealthMetricType.restingHeartRate:
        return 'Resting HR';
      case HealthMetricType.respiratoryRate:
        return 'Respiratory Rate';
      case HealthMetricType.bloodOxygen:
        return 'Blood Oxygen';
      case HealthMetricType.bodyTemperature:
        return 'Body Temperature';
      case HealthMetricType.sleepAsleep:
        return 'Sleep';
      case HealthMetricType.sleepInBed:
        return 'Time In Bed';
      case HealthMetricType.sleepRem:
        return 'REM Sleep';
      case HealthMetricType.sleepDeep:
        return 'Deep Sleep';
      case HealthMetricType.sleepLight:
        return 'Light Sleep';
      case HealthMetricType.sleepAwake:
        return 'Awake';
      case HealthMetricType.workoutEnergy:
        return 'Workout Energy';
      case HealthMetricType.workoutDistance:
        return 'Workout Distance';
      case HealthMetricType.workoutDuration:
        return 'Workout Duration';
      case HealthMetricType.distanceWalkingRunning:
        return 'Walking + Running Distance';
      case HealthMetricType.distanceCycling:
        return 'Cycling Distance';
      case HealthMetricType.distanceSwimming:
        return 'Swimming Distance';
    }
  }

  String get preferredUnit {
    switch (this) {
      case HealthMetricType.weight:
        return 'kg';
      case HealthMetricType.height:
        return 'cm';
      case HealthMetricType.bodyMassIndex:
        return 'kg/m²';
      case HealthMetricType.bodyFatPercentage:
        return '%';
      case HealthMetricType.basalMetabolicRate:
        return 'kcal/day';
      case HealthMetricType.waterIntake:
        return 'L';
      case HealthMetricType.steps:
        return 'count';
      case HealthMetricType.activeEnergyBurned:
        return 'kcal';
      case HealthMetricType.exerciseTime:
        return 'min';
      case HealthMetricType.heartRate:
      case HealthMetricType.walkingHeartRate:
        return 'bpm';
      case HealthMetricType.heartRateVariabilitySdnn:
      case HealthMetricType.heartRateVariabilityRmssd:
        return 'ms';
      case HealthMetricType.restingHeartRate:
        return 'bpm';
      case HealthMetricType.respiratoryRate:
        return 'breaths/min';
      case HealthMetricType.bloodOxygen:
        return '%';
      case HealthMetricType.bodyTemperature:
        return 'C';
      case HealthMetricType.sleepAsleep:
      case HealthMetricType.sleepInBed:
      case HealthMetricType.sleepRem:
      case HealthMetricType.sleepDeep:
      case HealthMetricType.sleepLight:
      case HealthMetricType.sleepAwake:
        return 'min';
      case HealthMetricType.workoutEnergy:
        return 'kcal';
      case HealthMetricType.workoutDistance:
        return 'km';
      case HealthMetricType.workoutDuration:
        return 'min';
      case HealthMetricType.distanceWalkingRunning:
      case HealthMetricType.distanceCycling:
      case HealthMetricType.distanceSwimming:
        return 'km';
    }
  }
}

class HealthMetricSample extends Equatable {
  const HealthMetricSample({
    required this.type,
    required this.value,
    required this.unit,
    required this.startTime,
    required this.endTime,
    required this.source,
    this.isUserEntered = false,
    this.externalId,
    this.sourceId,
    this.sourceDeviceId,
    this.deviceModel,
    this.platform,
    this.recordingMethod = 'unknown',
    this.timezoneName,
    this.timezoneOffsetMinutes,
    this.quality = HealthDataQuality.measured,
    this.completeness = HealthDataCompleteness.complete,
    this.sessionKey,
  });

  final HealthMetricType type;
  final double value;
  final String unit;
  final DateTime startTime;
  final DateTime endTime;
  final String source;
  final bool isUserEntered;
  final String? externalId;
  final String? sourceId;
  final String? sourceDeviceId;
  final String? deviceModel;
  final String? platform;
  final String recordingMethod;
  final String? timezoneName;
  final int? timezoneOffsetMinutes;
  final HealthDataQuality quality;
  final HealthDataCompleteness completeness;
  final String? sessionKey;

  DateTime get localStartTime => _asLocalWallTime(startTime);
  DateTime get localEndTime => _asLocalWallTime(endTime);

  String get stableIdentity {
    final id = externalId?.trim();
    if (id != null && id.isNotEmpty) return id;
    return [
      type.name,
      startTime.toUtc().toIso8601String(),
      endTime.toUtc().toIso8601String(),
      sourceId ?? source,
      sourceDeviceId ?? '',
      value.toStringAsFixed(6),
      unit,
    ].join('|');
  }

  DateTime _asLocalWallTime(DateTime instant) {
    final offset = timezoneOffsetMinutes;
    if (offset == null) return instant.toLocal();
    return instant.toUtc().add(Duration(minutes: offset));
  }

  Map<String, dynamic> toObservationPayload({required String provider}) => {
    'externalId': stableIdentity,
    'metricType': type.name,
    'value': valueInPreferredUnit,
    'unit': type.preferredUnit,
    'startTime': startTime.toUtc().toIso8601String(),
    'endTime': endTime.toUtc().toIso8601String(),
    'timezoneName': timezoneName,
    'timezoneOffsetMinutes': timezoneOffsetMinutes,
    'sourceName': source,
    'sourceId': sourceId,
    'sourceDeviceId': sourceDeviceId,
    'deviceModel': deviceModel,
    'platform': platform ?? provider,
    'recordingMethod': recordingMethod,
    'quality': quality.wireName,
    'completeness': completeness.name,
    'sessionKey': sessionKey,
  };

  double get valueInPreferredUnit {
    switch (type) {
      case HealthMetricType.weight:
        return unit == 'lb' ? value * 0.45359237 : value;
      case HealthMetricType.height:
        if (unit == 'm') return value * 100.0;
        if (unit == 'in') return value * 2.54;
        return value;
      case HealthMetricType.waterIntake:
        if (unit == 'ml') return value / 1000.0;
        return value;
      case HealthMetricType.activeEnergyBurned:
        if (unit == 'cal') return value / 1000.0;
        return value;
      case HealthMetricType.exerciseTime:
      case HealthMetricType.sleepAsleep:
      case HealthMetricType.sleepInBed:
      case HealthMetricType.sleepRem:
      case HealthMetricType.sleepDeep:
      case HealthMetricType.sleepLight:
      case HealthMetricType.sleepAwake:
        if (unit == 's' || unit == 'sec' || unit == 'seconds') {
          return value / 60.0;
        }
        if (unit == 'h' || unit == 'hr' || unit == 'hours') {
          return value * 60.0;
        }
        return value;
      case HealthMetricType.bodyTemperature:
        if (unit.toLowerCase() == 'f') {
          return (value - 32.0) * 5.0 / 9.0;
        }
        if (unit.toLowerCase() == 'k') {
          return value - 273.15;
        }
        return value;
      case HealthMetricType.workoutDistance:
      case HealthMetricType.distanceWalkingRunning:
      case HealthMetricType.distanceCycling:
      case HealthMetricType.distanceSwimming:
        if (unit == 'm') return value / 1000.0;
        return value;
      case HealthMetricType.workoutDuration:
        if (unit == 's' || unit == 'sec' || unit == 'seconds') {
          return value / 60.0;
        }
        return value;
      default:
        return value;
    }
  }

  HealthMetricSample copyWith({
    double? value,
    String? unit,
    DateTime? startTime,
    DateTime? endTime,
    String? source,
    bool? isUserEntered,
    String? externalId,
    String? sourceId,
    String? sourceDeviceId,
    String? deviceModel,
    String? platform,
    String? recordingMethod,
    String? timezoneName,
    int? timezoneOffsetMinutes,
    HealthDataQuality? quality,
    HealthDataCompleteness? completeness,
    String? sessionKey,
  }) {
    return HealthMetricSample(
      type: type,
      value: value ?? this.value,
      unit: unit ?? this.unit,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      source: source ?? this.source,
      isUserEntered: isUserEntered ?? this.isUserEntered,
      externalId: externalId ?? this.externalId,
      sourceId: sourceId ?? this.sourceId,
      sourceDeviceId: sourceDeviceId ?? this.sourceDeviceId,
      deviceModel: deviceModel ?? this.deviceModel,
      platform: platform ?? this.platform,
      recordingMethod: recordingMethod ?? this.recordingMethod,
      timezoneName: timezoneName ?? this.timezoneName,
      timezoneOffsetMinutes:
          timezoneOffsetMinutes ?? this.timezoneOffsetMinutes,
      quality: quality ?? this.quality,
      completeness: completeness ?? this.completeness,
      sessionKey: sessionKey ?? this.sessionKey,
    );
  }

  @override
  List<Object?> get props => [
    type,
    value,
    unit,
    startTime,
    endTime,
    source,
    isUserEntered,
    externalId,
    sourceId,
    sourceDeviceId,
    deviceModel,
    platform,
    recordingMethod,
    timezoneName,
    timezoneOffsetMinutes,
    quality,
    completeness,
    sessionKey,
  ];
}
