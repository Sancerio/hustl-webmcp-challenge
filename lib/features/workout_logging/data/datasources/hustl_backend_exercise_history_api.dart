import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/services/token_storage.dart';

class HustlBackendExerciseHistoryApiException implements Exception {
  HustlBackendExerciseHistoryApiException({
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

class HustlBackendExerciseHistoryApi {
  HustlBackendExerciseHistoryApi({
    http.Client? client,
    String? baseUrl,
    required this.tokens,
  }) : _client = client ?? createHttpClient(),
       _base = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _base;
  final TokenStorage tokens;

  Future<Map<String, dynamic>> getExerciseHistory({
    int limit = 10,
    int sinceDays = 365,
  }) async {
    final uri = Uri.parse(
      '$_base/api/workouts/exercise-history',
    ).replace(queryParameters: {'limit': '$limit', 'sinceDays': '$sinceDays'});
    final token = await tokens.getAccessToken();
    final res = await _client.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      var code = 'fetch_failed';
      var message = 'Failed to fetch exercise history';
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['error'] is Map) {
          final error = decoded['error']! as Map;
          code = error['code']?.toString() ?? code;
          message = error['message']?.toString() ?? message;
        }
      } catch (_) {
        // Use the bounded fallback below.
      }
      throw HustlBackendExerciseHistoryApiException(
        statusCode: res.statusCode,
        code: code,
        message: message,
      );
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map || decoded['data'] is! Map) {
      throw HustlBackendExerciseHistoryApiException(
        statusCode: res.statusCode,
        code: 'invalid_response',
        message: 'Invalid response from server',
      );
    }
    return Map<String, dynamic>.from(decoded['data']! as Map);
  }
}
