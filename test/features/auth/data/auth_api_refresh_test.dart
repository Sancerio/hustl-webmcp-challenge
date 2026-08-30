import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hustl_app/features/auth/data/datasources/auth_api.dart';

void main() {
  group('AuthApi.refreshToken', () {
    test('uses cookie (no body) when refreshToken param is null', () async {
      String? capturedMethod;
      Uri? capturedUrl;
      String? capturedBody;
      final client = MockClient((req) async {
        capturedMethod = req.method;
        capturedUrl = req.url;
        capturedBody = req.body;
        final body = jsonEncode({
          'data': {
            'accessToken': 'a1',
            'refreshToken': null,
            'expiresIn': 3600,
          },
        });
        return http.Response(
          body,
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = AuthApi(client: client, baseUrl: 'http://localhost');
      final result = await api.refreshToken();
      expect(result.accessToken, 'a1');
      // Verify POST and empty body
      expect(capturedMethod, 'POST');
      expect(capturedUrl.toString(), 'http://localhost/api/auth/refresh');
      expect(capturedBody, isEmpty);
    });

    test('sends body with refreshToken when provided', () async {
      String? capturedMethod;
      String? capturedBody;
      final client = MockClient((req) async {
        capturedMethod = req.method;
        capturedBody = req.body;
        final body = jsonEncode({
          'data': {
            'accessToken': 'a2',
            'refreshToken': 'r2',
            'expiresIn': 3600,
          },
        });
        return http.Response(
          body,
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = AuthApi(client: client, baseUrl: 'http://localhost');
      final result = await api.refreshToken('r2');
      expect(result.accessToken, 'a2');
      expect(capturedMethod, 'POST');
      expect(capturedBody, jsonEncode({'refreshToken': 'r2'}));
    });
  });
}
