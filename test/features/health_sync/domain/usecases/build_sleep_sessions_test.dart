import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/health_sync/domain/models/health_metric_sample.dart';
import 'package:hustl_app/features/health_sync/domain/usecases/build_sleep_sessions.dart';

void main() {
  const build = BuildSleepSessionsUseCase();
  final now = DateTime.utc(2026, 8, 15, 12);

  HealthMetricSample sleep({
    required HealthMetricType type,
    required DateTime start,
    required DateTime end,
    String source = 'Health',
    String? sourceId = 'com.apple.Health',
    String? deviceId = 'watch-1',
    String? deviceModel = 'Apple Watch',
    int offsetMinutes = 480,
  }) => HealthMetricSample(
    type: type,
    value: end.difference(start).inMinutes.toDouble(),
    unit: 'min',
    startTime: start,
    endTime: end,
    source: source,
    sourceId: sourceId,
    sourceDeviceId: deviceId,
    deviceModel: deviceModel,
    timezoneName: 'Asia/Singapore',
    timezoneOffsetMinutes: offsetMinutes,
  );

  test('marks a ten-minute fragment partial instead of reporting a night', () {
    final sessions = build([
      sleep(
        type: HealthMetricType.sleepAsleep,
        start: DateTime.utc(2026, 8, 14, 22),
        end: DateTime.utc(2026, 8, 14, 22, 10),
      ),
    ], now: now);

    expect(sessions, hasLength(1));
    expect(sessions.single.durationMinutes, 10);
    expect(sessions.single.completeness, HealthDataCompleteness.partial);
    expect(sessions.single.isComplete, isFalse);
  });

  test(
    'merges staged sleep across midnight and attributes it to wake date',
    () {
      final sessions = build([
        sleep(
          type: HealthMetricType.sleepLight,
          start: DateTime.utc(2026, 8, 14, 15),
          end: DateTime.utc(2026, 8, 14, 17),
        ),
        sleep(
          type: HealthMetricType.sleepDeep,
          start: DateTime.utc(2026, 8, 14, 17),
          end: DateTime.utc(2026, 8, 14, 19),
        ),
        sleep(
          type: HealthMetricType.sleepRem,
          start: DateTime.utc(2026, 8, 14, 19),
          end: DateTime.utc(2026, 8, 14, 22),
        ),
      ], now: now);

      expect(sessions.single.localDate, DateTime(2026, 8, 15));
      expect(sessions.single.durationMinutes, 420);
      expect(sessions.single.completeness, HealthDataCompleteness.complete);
      expect(
        sessions.single.observations.every(
          (sample) => sample.sessionKey == sessions.single.sessionKey,
        ),
        isTrue,
      );
    },
  );

  test('does not double-count a coarse asleep total over staged records', () {
    final start = DateTime.utc(2026, 8, 14, 15);
    final sessions = build([
      sleep(
        type: HealthMetricType.sleepAsleep,
        start: start,
        end: start.add(const Duration(hours: 7)),
      ),
      sleep(
        type: HealthMetricType.sleepLight,
        start: start,
        end: start.add(const Duration(hours: 3)),
      ),
      sleep(
        type: HealthMetricType.sleepDeep,
        start: start.add(const Duration(hours: 3)),
        end: start.add(const Duration(hours: 5)),
      ),
      sleep(
        type: HealthMetricType.sleepRem,
        start: start.add(const Duration(hours: 5)),
        end: start.add(const Duration(hours: 7)),
      ),
    ], now: now);

    expect(sessions.single.durationMinutes, 420);
  });

  test('uses interval union for overlapping same-source sleep records', () {
    final start = DateTime.utc(2026, 8, 14, 15);
    final sessions = build([
      sleep(
        type: HealthMetricType.sleepAsleep,
        start: start,
        end: start.add(const Duration(hours: 7)),
      ),
      sleep(
        type: HealthMetricType.sleepAsleep,
        start: start.add(const Duration(hours: 2)),
        end: start.add(const Duration(hours: 3)),
      ),
    ], now: now);

    expect(sessions.single.durationMinutes, 420);
  });

  test('prefers a staged wearable session over a duplicate phone summary', () {
    final start = DateTime.utc(2026, 8, 14, 15);
    final sessions = build([
      sleep(
        type: HealthMetricType.sleepAsleep,
        start: start,
        end: start.add(const Duration(hours: 7)),
        deviceId: 'phone-1',
        deviceModel: 'iPhone',
      ),
      sleep(
        type: HealthMetricType.sleepLight,
        start: start,
        end: start.add(const Duration(hours: 3)),
      ),
      sleep(
        type: HealthMetricType.sleepDeep,
        start: start.add(const Duration(hours: 3)),
        end: start.add(const Duration(hours: 5)),
      ),
      sleep(
        type: HealthMetricType.sleepRem,
        start: start.add(const Duration(hours: 5)),
        end: start.add(const Duration(hours: 7)),
      ),
    ], now: now);

    expect(sessions, hasLength(1));
    expect(sessions.single.deviceModel, 'Apple Watch');
    expect(sessions.single.sampleCount, 3);
  });

  test('returns no session when sleep data is missing', () {
    expect(build(const [], now: now), isEmpty);
  });
}
