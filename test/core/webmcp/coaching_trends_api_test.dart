import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hustl_app/core/services/token_storage.dart' as token;
import 'package:hustl_app/core/webmcp/coaching_trends_api.dart';

class _FakeTokenStorage implements token.TokenStorage {
  _FakeTokenStorage(this._accessToken);

  String? _accessToken;

  @override
  Future<String?> getAccessToken() async => _accessToken;

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<void> saveTokenPair({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
  }) async => _accessToken = accessToken;

  @override
  Future<void> clearAccessToken() async => _accessToken = null;

  @override
  Future<void> clearAll() async => _accessToken = null;
}

void main() {
  test('sends bounded local-window query and parses the envelope', () async {
    late http.Request captured;
    final api = HustlBackendCoachingTrendsApi(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'range': {'windowDays': 30},
            },
          }),
          200,
        );
      }),
      baseUrl: 'https://example.com',
      tokens: _FakeTokenStorage('secret-token'),
    );

    final result = await api.load(
      windowDays: 30,
      endDate: '2026-08-29',
      utcOffsetMinutes: 480,
    );

    expect(captured.url.path, '/api/coach/trends');
    expect(captured.url.queryParameters, {
      'windowDays': '30',
      'endDate': '2026-08-29',
      'utcOffsetMinutes': '480',
    });
    expect(captured.headers['authorization'], 'Bearer secret-token');
    expect(result['range'], {'windowDays': 30});
  });

  test('preserves a typed API error without reflecting raw fallback text', () {
    final api = HustlBackendCoachingTrendsApi(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': false,
            'error': {'code': 'invalid_request', 'message': 'Invalid window'},
          }),
          400,
        ),
      ),
      baseUrl: 'https://example.com',
      tokens: _FakeTokenStorage(null),
    );

    expect(
      () =>
          api.load(windowDays: 8, endDate: '2026-08-29', utcOffsetMinutes: 480),
      throwsA(
        isA<CoachingTrendsApiException>()
            .having((error) => error.code, 'code', 'invalid_request')
            .having((error) => error.message, 'message', 'Invalid window'),
      ),
    );
  });

  test('rejects malformed success responses with a fixed error', () {
    final api = HustlBackendCoachingTrendsApi(
      client: MockClient(
        (_) async => http.Response('private malformed payload', 200),
      ),
      baseUrl: 'https://example.com',
      tokens: _FakeTokenStorage(null),
    );

    expect(
      () =>
          api.load(windowDays: 7, endDate: '2026-08-29', utcOffsetMinutes: 480),
      throwsA(
        isA<CoachingTrendsApiException>()
            .having((error) => error.code, 'code', 'invalid_response')
            .having(
              (error) => error.message,
              'message',
              isNot(contains('private malformed payload')),
            ),
      ),
    );
  });
}
