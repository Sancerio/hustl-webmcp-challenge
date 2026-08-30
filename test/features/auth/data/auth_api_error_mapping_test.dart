import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hustl_app/features/auth/data/datasources/auth_api.dart';

void main() {
  group('AuthApi error mapping', () {
    test(
      '429 surfaces a rate_limited AuthApiException with Retry-After',
      () async {
        final client = MockClient(
          (req) async => http.Response(
            jsonEncode({
              'error': {'code': 'rate_limited', 'message': 'Slow down'},
            }),
            429,
            headers: {'content-type': 'application/json', 'retry-after': '30'},
          ),
        );
        final api = AuthApi(client: client, baseUrl: 'http://localhost');
        await expectLater(
          api.getMe('token'),
          throwsA(
            isA<AuthApiException>()
                .having((e) => e.code, 'code', 'rate_limited')
                .having((e) => e.status, 'status', 429)
                .having(
                  (e) => e.retryAfter,
                  'retryAfter',
                  const Duration(seconds: 30),
                ),
          ),
        );
      },
    );

    test(
      'a 429 with a non-JSON body still classifies as rate_limited',
      () async {
        final client = MockClient(
          (req) async => http.Response(
            'rate limited',
            429,
            headers: {'retry-after': '12'},
          ),
        );
        final api = AuthApi(client: client, baseUrl: 'http://localhost');
        await expectLater(
          api.getMe('token'),
          throwsA(
            isA<AuthApiException>()
                .having((e) => e.code, 'code', 'rate_limited')
                .having(
                  (e) => e.retryAfter,
                  'retryAfter',
                  const Duration(seconds: 12),
                ),
          ),
        );
      },
    );

    test(
      'structured backend error preserves its code (email_not_verified)',
      () async {
        final client = MockClient(
          (req) async => http.Response(
            jsonEncode({
              'error': {'code': 'email_not_verified', 'message': 'nope'},
            }),
            409,
            headers: {'content-type': 'application/json'},
          ),
        );
        final api = AuthApi(client: client, baseUrl: 'http://localhost');
        await expectLater(
          api.getMe('token'),
          throwsA(
            isA<AuthApiException>().having(
              (e) => e.code,
              'code',
              'email_not_verified',
            ),
          ),
        );
      },
    );
  });
}
