import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hustl_app/core/services/token_storage.dart' as token;
import 'package:hustl_app/features/workout_logging/data/datasources/hustl_backend_exercise_history_api.dart';

class _FakeTokenStorage implements token.TokenStorage {
  _FakeTokenStorage(this._access);

  String? _access;

  @override
  Future<String?> getAccessToken() async => _access;

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<void> saveTokenPair({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
  }) async {
    _access = accessToken;
  }

  @override
  Future<void> clearAccessToken() async => _access = null;

  @override
  Future<void> clearAll() async => _access = null;
}

void main() {
  test(
    'exercise history sends bounded query and parses the envelope',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'range': {'sinceDays': 90, 'since': '2026-06-01'},
              'exerciseCount': 1,
              'items': [
                {'name': 'Bench Press', 'frequency': 4},
              ],
            },
          }),
          200,
        );
      });
      final api = HustlBackendExerciseHistoryApi(
        client: client,
        baseUrl: 'https://example.com',
        tokens: _FakeTokenStorage('token'),
      );

      final result = await api.getExerciseHistory(limit: 7, sinceDays: 90);

      expect(captured.url.path, '/api/workouts/exercise-history');
      expect(captured.url.queryParameters, {'limit': '7', 'sinceDays': '90'});
      expect(captured.headers['authorization'], 'Bearer token');
      expect(result['exerciseCount'], 1);
    },
  );

  test('exercise history preserves a typed API error without raw fallback', () {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'success': false,
          'error': {'code': 'invalid_request', 'message': 'Invalid bounds'},
        }),
        400,
      ),
    );
    final api = HustlBackendExerciseHistoryApi(
      client: client,
      baseUrl: 'https://example.com',
      tokens: _FakeTokenStorage('token'),
    );

    expect(
      () => api.getExerciseHistory(limit: 99),
      throwsA(
        isA<HustlBackendExerciseHistoryApiException>()
            .having((error) => error.code, 'code', 'invalid_request')
            .having((error) => error.message, 'message', 'Invalid bounds'),
      ),
    );
  });

  test('exercise history rejects a malformed success response', () {
    final api = HustlBackendExerciseHistoryApi(
      client: MockClient((_) async => http.Response('{}', 200)),
      baseUrl: 'https://example.com',
      tokens: _FakeTokenStorage('token'),
    );

    expect(
      () => api.getExerciseHistory(),
      throwsA(
        isA<HustlBackendExerciseHistoryApiException>().having(
          (error) => error.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });
}
