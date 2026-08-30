import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/services/watch_bridge/watch_bridge_health.dart';

void main() {
  test('parses canonical health summary payload', () {
    final parsed = WatchHealthSummary.tryParse({
      'type': 'health_summary',
      'id': 'health-1',
      'sessionId': 'session-1',
      'recordingStartMs': 10,
      'recordingEndMs': 20,
      'metrics': {
        'durationSec': 1800,
        'avgHr': 128,
        'maxHr': 162,
        'activeEnergyKcal': 240.5,
      },
      'platformRecord': {'hkWorkoutUUID': 'uuid-1'},
    });

    expect(parsed, isNotNull);
    expect(parsed!.durationSeconds, 1800);
    expect(parsed.averageHeartRateBpm, 128);
    expect(parsed.maxHeartRateBpm, 162);
    expect(parsed.activeEnergyKilocalories, 240.5);
    expect(parsed.hkWorkoutUuid, 'uuid-1');
  });

  test('parses fallback health summary metric keys', () {
    final parsed = WatchHealthSummary.tryParse({
      'type': 'health_summary',
      'id': 'health-2',
      'sessionId': 'session-2',
      'metrics': {
        'durationSeconds': 1200,
        'avgBpm': 130,
        'maxBpm': 170,
        'activeEnergyKilocalories': 199.2,
      },
      'platformRecord': {'hkWorkoutUuid': 'uuid-2'},
    });

    expect(parsed, isNotNull);
    expect(parsed!.durationSeconds, 1200);
    expect(parsed.averageHeartRateBpm, 130);
    expect(parsed.maxHeartRateBpm, 170);
    expect(parsed.activeEnergyKilocalories, 199.2);
    expect(parsed.hkWorkoutUuid, 'uuid-2');
  });

  test('returns null for invalid health summary payload', () {
    expect(WatchHealthSummary.tryParse({'type': 'health_summary'}), isNull);
    expect(WatchHealthSummary.tryParse({'type': 'other', 'id': 'x'}), isNull);
  });

  test('parses recording failure error payload', () {
    final parsed = WatchHealthRecordingState.tryParse({
      'type': 'health_recording_stop',
      'id': 'rec-error-1',
      'sessionId': 'session-1',
      'error': 'Health permissions denied',
    });

    expect(parsed, isNotNull);
    expect(parsed!.isRecording, isFalse);
    expect(parsed.sessionId, 'session-1');
    expect(parsed.error, 'Health permissions denied');
    expect(parsed.hasError, isTrue);
  });
}
