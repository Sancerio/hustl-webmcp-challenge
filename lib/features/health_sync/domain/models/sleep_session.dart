import 'package:equatable/equatable.dart';

import 'health_metric_sample.dart';

class SleepSession extends Equatable {
  const SleepSession({
    required this.sessionKey,
    required this.localDate,
    required this.startTime,
    required this.endTime,
    required this.source,
    required this.durationMinutes,
    required this.timeInBedMinutes,
    required this.remMinutes,
    required this.deepMinutes,
    required this.lightMinutes,
    required this.awakeMinutes,
    required this.completeness,
    required this.sampleCount,
    required this.observations,
    this.timezoneName,
    this.timezoneOffsetMinutes,
    this.sourceId,
    this.sourceDeviceId,
    this.deviceModel,
  });

  final String sessionKey;
  final DateTime localDate;
  final DateTime startTime;
  final DateTime endTime;
  final String source;
  final String? timezoneName;
  final int? timezoneOffsetMinutes;
  final String? sourceId;
  final String? sourceDeviceId;
  final String? deviceModel;
  final double? durationMinutes;
  final double? timeInBedMinutes;
  final double? remMinutes;
  final double? deepMinutes;
  final double? lightMinutes;
  final double? awakeMinutes;
  final HealthDataCompleteness completeness;
  final int sampleCount;
  final List<HealthMetricSample> observations;

  bool get isComplete => completeness == HealthDataCompleteness.complete;

  Map<String, dynamic> toPayload({required String provider}) => {
    'sessionKey': sessionKey,
    'sessionType': 'sleep',
    'localDate': _dateKey(localDate),
    'startTime': startTime.toUtc().toIso8601String(),
    'endTime': endTime.toUtc().toIso8601String(),
    'timezoneName': timezoneName,
    'timezoneOffsetMinutes': timezoneOffsetMinutes,
    'sourceName': source,
    'sourceId': sourceId,
    'sourceDeviceId': sourceDeviceId,
    'deviceModel': deviceModel,
    'durationMinutes': durationMinutes,
    'timeInBedMinutes': timeInBedMinutes,
    'remMinutes': remMinutes,
    'deepMinutes': deepMinutes,
    'lightMinutes': lightMinutes,
    'awakeMinutes': awakeMinutes,
    'quality': 'derived',
    'completeness': completeness.name,
    'sampleCount': sampleCount,
    'provider': provider,
  };

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  List<Object?> get props => [
    sessionKey,
    localDate,
    startTime,
    endTime,
    source,
    timezoneName,
    timezoneOffsetMinutes,
    sourceId,
    sourceDeviceId,
    deviceModel,
    durationMinutes,
    timeInBedMinutes,
    remMinutes,
    deepMinutes,
    lightMinutes,
    awakeMinutes,
    completeness,
    sampleCount,
    observations,
  ];
}
