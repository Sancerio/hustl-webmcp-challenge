import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/health_sync/domain/models/external_activity.dart';
import 'package:hustl_app/features/health_sync/domain/services/external_activity_filter.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';

ExternalActivity _activity({
  required String uuid,
  String sourceName = 'Strava',
  ExternalActivityKind kind = ExternalActivityKind.run,
  DateTime? start,
  DateTime? end,
  double? energy,
  double? distance,
  double? hr,
}) {
  final s = start ?? DateTime.utc(2025, 1, 1, 8);
  final e = end ?? DateTime.utc(2025, 1, 1, 9);
  return ExternalActivity(
    platformUuid: uuid,
    sourceName: sourceName,
    kind: kind,
    start: s,
    end: e,
    activeEnergyKcal: energy,
    distanceMeters: distance,
    averageHeartRateBpm: hr,
  );
}

WorkoutSession _session({
  required String id,
  required DateTime start,
  required DateTime end,
  bool capturedOnWatch = false,
  String? watchUuid,
}) {
  return WorkoutSession(
    id: id,
    name: 'S',
    startTime: start,
    endTime: end,
    exercises: const [],
    capturedOnWatch: capturedOnWatch,
    watchWorkoutUuid: watchUuid,
  );
}

void main() {
  const filter = ExternalActivityFilter();

  group('stage 1: Hustl echoes', () {
    test('drops activities whose UUID is a known writeback UUID', () {
      final result = filter.filter(
        activities: [
          _activity(uuid: 'echo'),
          _activity(
            uuid: 'external',
            start: DateTime.utc(2025, 1, 1, 12),
            end: DateTime.utc(2025, 1, 1, 13),
          ),
        ],
        hustlWritebackUuids: {'echo'},
        hustlSessions: const [],
      );
      expect(result.map((a) => a.platformUuid), ['external']);
    });

    test('writeback-mapped UUID never survives (roundtrip regression)', () {
      final result = filter.filter(
        activities: [_activity(uuid: 'mapped-uuid', sourceName: 'Apple')],
        hustlWritebackUuids: {'mapped-uuid'},
        hustlSessions: const [],
      );
      expect(result, isEmpty);
    });

    test('drops activities whose source name mentions hustl', () {
      final result = filter.filter(
        activities: [_activity(uuid: 'x', sourceName: 'Hustl')],
        hustlWritebackUuids: const {},
        hustlSessions: const [],
      );
      expect(result, isEmpty);
    });
  });

  group('stage 2: watch overlap', () {
    test('drops an activity overlapping a watch-recorded session >50%', () {
      final result = filter.filter(
        activities: [
          _activity(
            uuid: 'x',
            start: DateTime.utc(2025, 1, 1, 8),
            end: DateTime.utc(2025, 1, 1, 9),
          ),
        ],
        hustlWritebackUuids: const {},
        hustlSessions: [
          _session(
            id: 's1',
            start: DateTime.utc(2025, 1, 1, 8, 5),
            end: DateTime.utc(2025, 1, 1, 8, 55),
            capturedOnWatch: true,
          ),
        ],
      );
      expect(result, isEmpty);
    });

    test('keeps an activity overlapping a watch session <=50%', () {
      final result = filter.filter(
        activities: [
          _activity(
            uuid: 'x',
            start: DateTime.utc(2025, 1, 1, 8),
            end: DateTime.utc(2025, 1, 1, 9),
          ),
        ],
        hustlWritebackUuids: const {},
        hustlSessions: [
          _session(
            id: 's1',
            start: DateTime.utc(2025, 1, 1, 8, 50),
            end: DateTime.utc(2025, 1, 1, 9, 40),
            capturedOnWatch: true,
          ),
        ],
      );
      expect(result.map((a) => a.platformUuid), ['x']);
    });

    test('ignores non-watch Hustl sessions', () {
      final result = filter.filter(
        activities: [_activity(uuid: 'x')],
        hustlWritebackUuids: const {},
        hustlSessions: [
          _session(
            id: 's1',
            start: DateTime.utc(2025, 1, 1, 8),
            end: DateTime.utc(2025, 1, 1, 9),
          ),
        ],
      );
      expect(result.map((a) => a.platformUuid), ['x']);
    });

    test(
      'zero-duration external inside a watch session window is excluded',
      () {
        final instant = DateTime.utc(2025, 1, 1, 8, 30);
        final result = filter.filter(
          activities: [_activity(uuid: 'z', start: instant, end: instant)],
          hustlWritebackUuids: const {},
          hustlSessions: [
            _session(
              id: 's1',
              start: DateTime.utc(2025, 1, 1, 8),
              end: DateTime.utc(2025, 1, 1, 9),
              capturedOnWatch: true,
            ),
          ],
        );
        expect(result, isEmpty);
      },
    );

    test('zero-duration external outside the watch session survives', () {
      final instant = DateTime.utc(2025, 1, 1, 11);
      final result = filter.filter(
        activities: [_activity(uuid: 'z', start: instant, end: instant)],
        hustlWritebackUuids: const {},
        hustlSessions: [
          _session(
            id: 's1',
            start: DateTime.utc(2025, 1, 1, 8),
            end: DateTime.utc(2025, 1, 1, 9),
            capturedOnWatch: true,
          ),
        ],
      );
      expect(result.map((a) => a.platformUuid), ['z']);
    });

    test(
      'malformed external (end before start) is treated as zero-length at '
      'start',
      () {
        // Malformed intervals normalize to a zero-length instant at START.
        // 'm-in': start 08:30 (inside watch window), end 08:00 -> excluded.
        // 'm-out': start 11:00 (outside), end 08:30 (inside) -> anchored at
        // its start, so it survives — proving the start anchoring.
        final result = filter.filter(
          activities: [
            _activity(
              uuid: 'm-in',
              start: DateTime.utc(2025, 1, 1, 8, 30),
              end: DateTime.utc(2025, 1, 1, 8),
            ),
            _activity(
              uuid: 'm-out',
              start: DateTime.utc(2025, 1, 1, 11),
              end: DateTime.utc(2025, 1, 1, 8, 30),
            ),
          ],
          hustlWritebackUuids: const {},
          hustlSessions: [
            _session(
              id: 's1',
              start: DateTime.utc(2025, 1, 1, 8),
              end: DateTime.utc(2025, 1, 1, 9),
              capturedOnWatch: true,
            ),
          ],
        );
        expect(result.map((a) => a.platformUuid), ['m-out']);
      },
    );

    test('watch session recognized via watchWorkoutUuid', () {
      final result = filter.filter(
        activities: [_activity(uuid: 'x')],
        hustlWritebackUuids: const {},
        hustlSessions: [
          _session(
            id: 's1',
            start: DateTime.utc(2025, 1, 1, 8),
            end: DateTime.utc(2025, 1, 1, 9),
            watchUuid: 'watch-1',
          ),
        ],
      );
      expect(result, isEmpty);
    });
  });

  group('stage 3: cross-app duplicate clusters', () {
    test('keeps the richest of two overlapping same-kind records', () {
      final poor = _activity(uuid: 'poor', sourceName: 'AppleFit');
      final rich = _activity(
        uuid: 'rich',
        sourceName: 'Strava',
        start: DateTime.utc(2025, 1, 1, 8, 2),
        end: DateTime.utc(2025, 1, 1, 8, 58),
        energy: 400,
        distance: 8000,
        hr: 150,
      );
      final result = filter.filter(
        activities: [poor, rich],
        hustlWritebackUuids: const {},
        hustlSessions: const [],
      );
      expect(result.map((a) => a.platformUuid), ['rich']);
    });

    test('does not merge different kinds even when overlapping', () {
      final run = _activity(uuid: 'run', kind: ExternalActivityKind.run);
      final ride = _activity(uuid: 'ride', kind: ExternalActivityKind.ride);
      final result = filter.filter(
        activities: [run, ride],
        hustlWritebackUuids: const {},
        hustlSessions: const [],
      );
      expect(result.map((a) => a.platformUuid).toSet(), {'run', 'ride'});
    });

    test('does not merge same-kind records that barely overlap', () {
      final a = _activity(
        uuid: 'a',
        start: DateTime.utc(2025, 1, 1, 8),
        end: DateTime.utc(2025, 1, 1, 9),
      );
      final b = _activity(
        uuid: 'b',
        start: DateTime.utc(2025, 1, 1, 8, 50),
        end: DateTime.utc(2025, 1, 1, 9, 50),
      );
      final result = filter.filter(
        activities: [a, b],
        hustlWritebackUuids: const {},
        hustlSessions: const [],
      );
      expect(result.map((a) => a.platformUuid).toSet(), {'a', 'b'});
    });

    test('tie on richness breaks to alphabetically-earliest source name', () {
      final zebra = _activity(uuid: 'z', sourceName: 'Zebra', energy: 100);
      final alpha = _activity(
        uuid: 'a',
        sourceName: 'Alpha',
        energy: 100,
        start: DateTime.utc(2025, 1, 1, 8, 1),
        end: DateTime.utc(2025, 1, 1, 8, 59),
      );
      final result = filter.filter(
        activities: [zebra, alpha],
        hustlWritebackUuids: const {},
        hustlSessions: const [],
      );
      expect(result.map((a) => a.platformUuid), ['a']);
    });
  });

  test('empty input yields empty output', () {
    expect(
      filter.filter(
        activities: const [],
        hustlWritebackUuids: const {},
        hustlSessions: const [],
      ),
      isEmpty,
    );
  });
}
