import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hustl_app/core/services/token_storage.dart' as token;
import 'package:hustl_app/features/nutrition_tracker/data/datasources/hustl_backend_nutrition_api.dart';

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

/// Builds a non-2xx meal-scan error body for the given backend [code], then
/// captures the [HustlBackendNutritionApiException] the API maps it to. The
/// scan endpoint is the public surface that exercises the private error mapper.
Future<HustlBackendNutritionApiException> _scanError({
  required int statusCode,
  required String code,
}) async {
  final client = MockClient((req) async {
    return http.Response(
      jsonEncode({
        'success': false,
        'error': {'code': code, 'message': 'raw backend message'},
      }),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  });
  final api = HustlBackendNutritionApi(
    client: client,
    baseUrl: 'https://example.com',
    tokens: _FakeTokenStorage(),
  );

  try {
    await api.scanMealPhoto(imageBase64: 'AAAA', mimeType: 'image/jpeg');
    fail('Expected scanMealPhoto to throw');
  } on HustlBackendNutritionApiException catch (e) {
    return e;
  }
}

/// Same as [_scanError] but exercises the NL "describe a meal" endpoint, whose
/// cannot_estimate copy must be text-specific rather than photo-specific.
Future<HustlBackendNutritionApiException> _describeError({
  required int statusCode,
  required String code,
}) async {
  final client = MockClient((req) async {
    return http.Response(
      jsonEncode({
        'success': false,
        'error': {'code': code, 'message': 'raw backend message'},
      }),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  });
  final api = HustlBackendNutritionApi(
    client: client,
    baseUrl: 'https://example.com',
    tokens: _FakeTokenStorage(),
  );

  try {
    await api.describeMeal(text: 'two eggs and toast');
    fail('Expected describeMeal to throw');
  } on HustlBackendNutritionApiException catch (e) {
    return e;
  }
}

void main() {
  group('HustlBackendNutritionApi error mapping', () {
    test('ai_scan_daily_cap maps to the dedicated cap message', () async {
      final error = await _scanError(
        statusCode: 429,
        code: 'ai_scan_daily_cap',
      );

      expect(error.code, 'ai_scan_daily_cap');
      expect(error.message, contains('AI scan limit'));
      // The cap copy points users at the manual / try-tomorrow recovery path.
      expect(error.message, contains('Log manually'));
    });

    test('rate_limited maps to the generic throttling message', () async {
      final error = await _scanError(statusCode: 429, code: 'rate_limited');

      expect(error.code, 'rate_limited');
      expect(error.message, contains('Too many requests'));
    });

    test(
      'the cap message is distinct from the generic rate-limited message',
      () async {
        final cap = await _scanError(
          statusCode: 429,
          code: 'ai_scan_daily_cap',
        );
        final rateLimited = await _scanError(
          statusCode: 429,
          code: 'rate_limited',
        );

        // Same HTTP status, but the daily-cap copy must not collapse into the
        // generic throttle copy — they describe different recovery paths.
        expect(cap.message, isNot(equals(rateLimited.message)));
      },
    );

    test('photo cannot_estimate uses photo-specific recovery copy', () async {
      final error = await _scanError(statusCode: 422, code: 'cannot_estimate');
      expect(error.message.toLowerCase(), contains('photo'));
    });

    test(
      'describe cannot_estimate uses text-specific copy, not photo copy',
      () async {
        final error = await _describeError(
          statusCode: 422,
          code: 'cannot_estimate',
        );
        // A user who typed/dictated a meal must not get "take a clearer photo".
        expect(error.message.toLowerCase(), isNot(contains('photo')));
        expect(error.message.toLowerCase(), contains('description'));
      },
    );
  });
}
