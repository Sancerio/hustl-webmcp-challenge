import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/services/token_storage.dart';
import 'package:hustl_app/features/health_sync/data/datasources/hustl_backend_health_api.dart';
import 'package:hustl_app/features/health_sync/data/models/backend_weekly_health_projection.dart';
import 'package:hustl_app/features/health_sync/data/repositories/backend_health_metrics_repository.dart';
import 'package:hustl_app/features/health_sync/domain/models/recovery_signal_availability.dart';

void main() {
  test(
    'reports backend health as available without a mobile provider',
    () async {
      final repository = BackendHealthMetricsRepository(api: _FakeApi());

      final status = await repository.getPermissionsStatus();

      expect(status.isServiceAvailable, isTrue);
      expect(status.hasPermissions, isTrue);
      expect(status.rawPermissionResult, isTrue);
      expect(
        await repository.getProviderAvailability(),
        HealthProviderAvailability.available,
      );
    },
  );

  test(
    'covers a wide range with weekly requests and filters exact dates',
    () async {
      final api = _FakeApi();
      final repository = BackendHealthMetricsRepository(api: api);

      final snapshot = await repository.loadSnapshot(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 8, 26),
      );

      expect(api.requests, [
        (start: DateTime(2026, 7, 15), end: DateTime(2026, 7, 21)),
        (start: DateTime(2026, 8, 5), end: DateTime(2026, 8, 11)),
        (start: DateTime(2026, 8, 26), end: DateTime(2026, 9, 1)),
      ]);
      expect(snapshot.metrics.map((metric) => metric.externalId), [
        '2026-07-01|steps',
        '2026-07-21|steps',
        '2026-07-22|steps',
        '2026-08-11|steps',
        '2026-08-12|steps',
        '2026-08-26|hrv_sdnn',
      ]);
      expect(snapshot.dailySummaries.length, 6);
      expect(snapshot.signalAvailability.hrv, isTrue);
      expect(snapshot.signalAvailability.sleep, isFalse);
      expect(snapshot.lastSyncedAt, DateTime.parse('2026-08-26T02:00:00Z'));
    },
  );
}

class _FakeApi extends HustlBackendHealthApi {
  _FakeApi() : super(tokens: _Tokens());

  final requests = <({DateTime start, DateTime end})>[];

  @override
  Future<BackendWeeklyHealthProjection> fetchWeeklyProjection({
    required DateTime start,
    required DateTime end,
  }) async {
    requests.add((start: start, end: end));
    final coverageStart = end.subtract(const Duration(days: 20));
    final metrics = <Map<String, dynamic>>[
      _metric(coverageStart, 'steps', 7000, 'count'),
      _metric(end, 'steps', 8000, 'count'),
      if (end == DateTime(2026, 9, 1))
        _metric(DateTime(2026, 8, 26), 'hrv_sdnn', 42, 'ms'),
    ];
    return BackendWeeklyHealthProjection.fromApiData({
      'range': {
        'start': _key(start),
        'end': _key(end),
        'baselineStart': _key(coverageStart),
      },
      'preferredProvider': 'apple_health',
      'metrics': metrics,
      'activities': const [],
      'sources': [
        {'provider': 'apple_health', 'lastSyncedAt': '2026-08-26T02:00:00Z'},
      ],
    });
  }
}

Map<String, dynamic> _metric(
  DateTime date,
  String type,
  num value,
  String unit,
) => {
  'date': _key(date),
  'metricType': type,
  'value': value,
  'unit': unit,
  'source': 'apple_health',
  'quality': 'derived',
  'completeness': 'complete',
  'timezoneName': 'Asia/Singapore',
  'timezoneOffsetMinutes': 480,
  'updatedAt': '2026-08-26T01:00:00Z',
};

String _key(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

class _Tokens implements TokenStorage {
  @override
  Future<String?> getAccessToken() async => 'token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
