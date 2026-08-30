import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hustl_app/core/services/token_storage.dart' as token;
import 'package:hustl_app/features/connections/data/datasources/connections_api.dart';

class _FakeTokenStorage implements token.TokenStorage {
  @override
  Future<String?> getAccessToken() async => 'token';

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<void> saveTokenPair({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
  }) async {}

  @override
  Future<void> clearAccessToken() async {}

  @override
  Future<void> clearAll() async {}
}

void main() {
  test('reads the account WebMCP food setting with bearer auth', () async {
    final api = ConnectionsApi(
      baseUrl: 'https://example.com',
      tokens: _FakeTokenStorage(),
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/webmcp/food-auto-log');
        expect(request.headers['Authorization'], 'Bearer token');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'enabled': false},
          }),
          200,
        );
      }),
    );

    expect(await api.getWebMcpFoodAutoLog(), isFalse);
  });

  test(
    'sends only the explicit boolean and trusts the server result',
    () async {
      final api = ConnectionsApi(
        baseUrl: 'https://example.com',
        tokens: _FakeTokenStorage(),
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/webmcp/food-auto-log');
          expect(jsonDecode(request.body), {'enabled': true});
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'enabled': true},
            }),
            200,
          );
        }),
      );

      expect(await api.setWebMcpFoodAutoLog(true), isTrue);
    },
  );

  test(
    'surfaces auth/account transition failure without changing local state',
    () async {
      final api = ConnectionsApi(
        baseUrl: 'https://example.com',
        tokens: _FakeTokenStorage(),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'success': false,
              'error': {'code': 'unauthorized', 'message': 'Sign in again'},
            }),
            401,
          ),
        ),
      );

      await expectLater(
        api.setWebMcpFoodAutoLog(true),
        throwsA(
          isA<ConnectionsApiException>()
              .having((error) => error.statusCode, 'status', 401)
              .having((error) => error.code, 'code', 'unauthorized'),
        ),
      );
    },
  );
}
