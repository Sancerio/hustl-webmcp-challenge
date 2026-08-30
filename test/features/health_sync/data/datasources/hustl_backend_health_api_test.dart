import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hustl_app/core/services/token_storage.dart';
import 'package:hustl_app/features/health_sync/data/datasources/hustl_backend_health_api.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';

void main() {
  test(
    'fetchWeeklyProjection authenticates and maps the web health projection',
    () async {
      late http.Request request;
      final api = HustlBackendHealthApi(
        baseUrl: 'https://api.hustl.test',
        tokens: _Tokens('access-token'),
        client: MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'range': {
                  'start': '2026-08-17',
                  'end': '2026-08-23',
                  'baselineStart': '2026-08-03',
                },
                'preferredProvider': 'apple_health',
                'metrics': [
                  _metric('2026-08-03', 'hrv_sdnn', 39, 'ms'),
                  _metric('2026-08-17', 'hrv_sdnn', 42, 'ms'),
                  _metric('2026-08-17', 'sleep_duration', 450, 'minutes'),
                  _metric('2026-08-17', 'steps', 9000, 'count'),
                  _metric('2026-08-17', 'weight', 82, 'kg'),
                  _metric('2026-08-17', 'body_fat_percentage', 17.7, '%'),
                  {
                    ..._metric('2026-08-17', 'hrv_rmssd', 99, 'ms'),
                    'source': 'google_fit',
                  },
                ],
                'activities': [
                  {
                    'platformUuid': 'football',
                    'provider': 'apple_health',
                    'sourceName': 'Apple Watch',
                    'kind': 'other',
                    'activityName': 'Football',
                    'startTime': '2026-08-20T11:00:00Z',
                    'endTime': '2026-08-20T12:00:00Z',
                    'durationMinutes': 60,
                    'activeEnergyKcal': 640,
                  },
                  {
                    'platformUuid': 'old-provider',
                    'provider': 'google_fit',
                    'sourceName': 'Health Connect',
                    'kind': 'ride',
                    'startTime': '2026-08-20T01:00:00Z',
                    'endTime': '2026-08-20T02:00:00Z',
                  },
                ],
                'sources': [
                  {
                    'provider': 'apple_health',
                    'lastSyncedAt': '2026-08-24T02:00:00Z',
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await api.fetchWeeklyProjection(
        start: DateTime(2026, 8, 17),
        end: DateTime(2026, 8, 23),
      );

      expect(request.url.path, '/api/health/weekly');
      expect(request.url.queryParameters, {
        'start': '2026-08-17',
        'end': '2026-08-23',
      });
      expect(request.headers['authorization'], 'Bearer access-token');
      expect(result.preferredProvider, 'apple_health');
      expect(result.lastSyncedAt, DateTime.parse('2026-08-24T02:00:00Z'));
      expect(result.activities.map((activity) => activity.platformUuid), [
        'football',
      ]);
      final recovery = result.snapshot.recoverySnapshots.firstWhere(
        (day) => day.date == DateTime(2026, 8, 17),
      );
      expect(recovery.hrvKind, HrvKind.sdnn);
      expect(recovery.hrvValue, 42);
      expect(recovery.sleepDurationMinutes, 450);
      expect(recovery.steps, 9000);
      final body = result.snapshot.dailySummaries.firstWhere(
        (day) => day.date == DateTime(2026, 8, 17),
      );
      expect(body.latestWeightKg, 82);
      expect(body.bodyFatPercentage, 17.7);
    },
  );

  test(
    'fetchWeeklyProjection fails before network access without a token',
    () async {
      var requested = false;
      final api = HustlBackendHealthApi(
        baseUrl: 'https://api.hustl.test',
        tokens: _Tokens(null),
        client: MockClient((_) async {
          requested = true;
          return http.Response('{}', 200);
        }),
      );

      expect(
        () => api.fetchWeeklyProjection(
          start: DateTime(2026, 8, 17),
          end: DateTime(2026, 8, 23),
        ),
        throwsStateError,
      );
      expect(requested, isFalse);
    },
  );
}

Map<String, dynamic> _metric(
  String date,
  String type,
  num value,
  String unit,
) => {
  'date': date,
  'metricType': type,
  'value': value,
  'unit': unit,
  'source': 'apple_health',
  'quality': 'derived',
  'completeness': 'complete',
  'timezoneName': 'Asia/Singapore',
  'timezoneOffsetMinutes': 480,
  'updatedAt': '2026-08-24T01:00:00Z',
};

class _Tokens implements TokenStorage {
  _Tokens(this.token);

  final String? token;

  @override
  Future<String?> getAccessToken() async => token;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
