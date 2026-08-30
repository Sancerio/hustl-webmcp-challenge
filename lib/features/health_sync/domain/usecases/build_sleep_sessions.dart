import '../models/health_metric_sample.dart';
import '../models/sleep_session.dart';

class BuildSleepSessionsUseCase {
  const BuildSleepSessionsUseCase({
    this.minimumNightMinutes = 180,
    this.maximumSegmentGap = const Duration(hours: 3),
    this.ongoingGrace = const Duration(hours: 1),
  });

  final double minimumNightMinutes;
  final Duration maximumSegmentGap;
  final Duration ongoingGrace;

  static const sleepTypes = {
    HealthMetricType.sleepAsleep,
    HealthMetricType.sleepInBed,
    HealthMetricType.sleepRem,
    HealthMetricType.sleepDeep,
    HealthMetricType.sleepLight,
    HealthMetricType.sleepAwake,
  };

  List<SleepSession> call(List<HealthMetricSample> metrics, {DateTime? now}) {
    final sleep = metrics.where((sample) => sleepTypes.contains(sample.type));
    final bySource = <String, List<HealthMetricSample>>{};
    for (final sample in _dedupe(sleep)) {
      bySource.putIfAbsent(_sourceKey(sample), () => []).add(sample);
    }

    final candidates = <SleepSession>[];
    for (final entry in bySource.entries) {
      final samples = entry.value..sort(_compareStart);
      final clusters = <List<HealthMetricSample>>[];
      for (final sample in samples) {
        if (clusters.isEmpty ||
            sample.startTime.difference(clusters.last.last.endTime) >
                maximumSegmentGap) {
          clusters.add([sample]);
        } else {
          clusters.last.add(sample);
        }
      }
      for (var index = 0; index < clusters.length; index++) {
        candidates.add(
          _buildCandidate(
            entry.key,
            index,
            clusters[index],
            now: now ?? DateTime.now(),
          ),
        );
      }
    }

    final preferredByNight = <DateTime, SleepSession>{};
    for (final candidate in candidates) {
      final existing = preferredByNight[candidate.localDate];
      if (existing == null || _precedence(candidate) > _precedence(existing)) {
        preferredByNight[candidate.localDate] = candidate;
      }
    }
    final result = preferredByNight.values.toList()
      ..sort((a, b) => a.localDate.compareTo(b.localDate));
    return result;
  }

  SleepSession _buildCandidate(
    String sourceKey,
    int clusterIndex,
    List<HealthMetricSample> samples, {
    required DateTime now,
  }) {
    final windowSamples = samples
        .where((sample) => sample.type != HealthMetricType.sleepInBed)
        .toList();
    final effectiveWindow = windowSamples.isEmpty ? samples : windowSamples;
    final start = effectiveWindow
        .map((sample) => sample.startTime)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final end = effectiveWindow
        .map((sample) => sample.endTime)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final representative = samples.reduce(
      (a, b) => _samplePrecedence(a) >= _samplePrecedence(b) ? a : b,
    );
    final localEnd = representative._localWallTime(end);
    final localDate = DateTime(localEnd.year, localEnd.month, localEnd.day);
    final rem = _intervalOrReportedMinutes(samples, HealthMetricType.sleepRem);
    final deep = _intervalOrReportedMinutes(
      samples,
      HealthMetricType.sleepDeep,
    );
    final light = _intervalOrReportedMinutes(
      samples,
      HealthMetricType.sleepLight,
    );
    final staged = rem + deep + light;
    final asleep = _intervalOrReportedMinutes(
      samples,
      HealthMetricType.sleepAsleep,
    );
    final duration = staged > 0 ? staged : asleep;
    final inBed = _intervalOrReportedMinutes(
      samples,
      HealthMetricType.sleepInBed,
    );
    final awake = _intervalOrReportedMinutes(
      samples,
      HealthMetricType.sleepAwake,
    );
    final isOngoing = now.toUtc().difference(end.toUtc()) < ongoingGrace;
    final completeness = isOngoing
        ? HealthDataCompleteness.ongoing
        : duration >= minimumNightMinutes
        ? HealthDataCompleteness.complete
        : HealthDataCompleteness.partial;
    final sessionKey = 'sleep|$sourceKey|${_dateKey(localDate)}|$clusterIndex';
    final tagged = samples
        .map(
          (sample) => sample.copyWith(
            sessionKey: sessionKey,
            completeness: completeness,
          ),
        )
        .toList();

    return SleepSession(
      sessionKey: sessionKey,
      localDate: localDate,
      startTime: start.toUtc(),
      endTime: end.toUtc(),
      source: representative.source,
      timezoneName: representative.timezoneName,
      timezoneOffsetMinutes: representative.timezoneOffsetMinutes,
      sourceId: representative.sourceId,
      sourceDeviceId: representative.sourceDeviceId,
      deviceModel: representative.deviceModel,
      durationMinutes: duration > 0 ? duration : null,
      timeInBedMinutes: inBed > 0 ? inBed : null,
      remMinutes: rem > 0 ? rem : null,
      deepMinutes: deep > 0 ? deep : null,
      lightMinutes: light > 0 ? light : null,
      awakeMinutes: awake > 0 ? awake : null,
      completeness: completeness,
      sampleCount: samples.length,
      observations: tagged,
    );
  }

  Iterable<HealthMetricSample> _dedupe(
    Iterable<HealthMetricSample> samples,
  ) sync* {
    final seen = <String>{};
    for (final sample in samples) {
      if (seen.add('${_sourceKey(sample)}|${sample.stableIdentity}')) {
        yield sample;
      }
    }
  }

  double _unionMinutes(
    List<HealthMetricSample> samples,
    HealthMetricType type,
  ) {
    final intervals = samples.where((sample) => sample.type == type).toList()
      ..sort(_compareStart);
    DateTime? coveredUntil;
    var milliseconds = 0;
    for (final sample in intervals) {
      final start = sample.startTime.toUtc();
      final end = sample.endTime.toUtc();
      if (!end.isAfter(start)) continue;
      final uncoveredStart = coveredUntil == null || start.isAfter(coveredUntil)
          ? start
          : coveredUntil;
      if (end.isAfter(uncoveredStart)) {
        milliseconds += end.difference(uncoveredStart).inMilliseconds;
      }
      if (coveredUntil == null || end.isAfter(coveredUntil)) coveredUntil = end;
    }
    return milliseconds / Duration.millisecondsPerMinute;
  }

  double _intervalOrReportedMinutes(
    List<HealthMetricSample> samples,
    HealthMetricType type,
  ) {
    final reported = samples
        .where((sample) => sample.type == type)
        .map((sample) => sample.valueInPreferredUnit)
        .where((value) => value.isFinite && value > 0)
        .fold(0.0, mathMax);
    final intervalMinutes = _unionMinutes(samples, type);
    return mathMax(reported, intervalMinutes);
  }

  int _precedence(SleepSession session) {
    var score = session.completeness == HealthDataCompleteness.complete
        ? 1000
        : 0;
    if (session.remMinutes != null ||
        session.deepMinutes != null ||
        session.lightMinutes != null) {
      score += 300;
    }
    if (session.sourceDeviceId?.isNotEmpty == true) score += 100;
    final wearable = '${session.deviceModel ?? ''} ${session.source}'
        .toLowerCase();
    if (wearable.contains('watch') || wearable.contains('wear')) score += 50;
    score += session.sampleCount.clamp(0, 40).toInt();
    score += ((session.durationMinutes ?? 0) / 10).round().clamp(0, 60).toInt();
    return score;
  }

  int _samplePrecedence(HealthMetricSample sample) {
    var score = sample.isUserEntered ? 0 : 20;
    if (sample.sourceDeviceId?.isNotEmpty == true) score += 10;
    if (sample.deviceModel?.toLowerCase().contains('watch') == true) score += 5;
    return score;
  }

  String _sourceKey(HealthMetricSample sample) => [
    sample.sourceId ?? sample.source,
    sample.sourceDeviceId ?? sample.deviceModel ?? '',
  ].join('|').toLowerCase();

  static int _compareStart(HealthMetricSample a, HealthMetricSample b) =>
      a.startTime.compareTo(b.startTime);

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

double mathMax(double a, double b) => a > b ? a : b;

extension on HealthMetricSample {
  DateTime _localWallTime(DateTime instant) {
    final offset = timezoneOffsetMinutes;
    if (offset == null) return instant.toLocal();
    return instant.toUtc().add(Duration(minutes: offset));
  }
}
