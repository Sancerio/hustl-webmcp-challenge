import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../network/http_client.dart';
import '../services/token_storage.dart';

abstract interface class CoachingTrendsApi {
  Future<Map<String, dynamic>> load({
    required int windowDays,
    required String endDate,
    required int utcOffsetMinutes,
  });
}

class CoachingTrendsApiException implements Exception {
  const CoachingTrendsApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => message;
}

class HustlBackendCoachingTrendsApi implements CoachingTrendsApi {
  HustlBackendCoachingTrendsApi({
    http.Client? client,
    String? baseUrl,
    required this.tokens,
  }) : _client = client ?? createHttpClient(),
       _base = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _base;
  final TokenStorage tokens;

  @override
  Future<Map<String, dynamic>> load({
    required int windowDays,
    required String endDate,
    required int utcOffsetMinutes,
  }) async {
    final uri = Uri.parse('$_base/api/coach/trends').replace(
      queryParameters: {
        'windowDays': '$windowDays',
        'endDate': endDate,
        'utcOffsetMinutes': '$utcOffsetMinutes',
      },
    );
    final token = await tokens.getAccessToken();
    final response = await _client.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiError(response);
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['success'] == true) {
        final data = decoded['data'];
        if (data is Map) return Map<String, dynamic>.from(data);
      }
    } catch (_) {
      // Fall through to the fixed malformed-response error below.
    }
    throw CoachingTrendsApiException(
      statusCode: response.statusCode,
      code: 'invalid_response',
      message: 'Invalid response from server',
    );
  }

  CoachingTrendsApiException _apiError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['success'] == false) {
        final error = decoded['error'];
        if (error is Map) {
          return CoachingTrendsApiException(
            statusCode: response.statusCode,
            code: error['code'] is String
                ? error['code'] as String
                : 'coaching_trends_failed',
            message: error['message'] is String
                ? error['message'] as String
                : 'Failed to load coaching trends',
          );
        }
      }
    } catch (_) {
      // Return a fixed fallback without reflecting response text.
    }
    return CoachingTrendsApiException(
      statusCode: response.statusCode,
      code: 'coaching_trends_failed',
      message: 'Failed to load coaching trends',
    );
  }
}
