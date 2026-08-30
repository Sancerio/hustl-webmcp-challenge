import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/services/token_storage.dart';

class HustlBackendWorkoutHistoryApiException implements Exception {
  HustlBackendWorkoutHistoryApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details,
  });

  final int statusCode;
  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => message;
}

class HustlBackendWorkoutHistoryApi {
  HustlBackendWorkoutHistoryApi({
    http.Client? client,
    String? baseUrl,
    required this.tokens,
  }) : _client = client ?? createHttpClient(),
       _base = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _base;
  final TokenStorage tokens;

  Future<Map<String, String>> _authHeaders() async {
    final token = await tokens.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Never _throwApiError(
    http.Response res, {
    required String fallbackCode,
    required String fallbackMessage,
  }) {
    HustlBackendWorkoutHistoryApiException? parsed;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        final success = decoded['success'];
        final error = decoded['error'];
        if (success == false && error is Map) {
          final code = error['code']?.toString() ?? fallbackCode;
          final message = error['message']?.toString() ?? fallbackMessage;
          final details = error['details'];
          parsed = HustlBackendWorkoutHistoryApiException(
            statusCode: res.statusCode,
            code: code,
            message: message,
            details: details,
          );
        }
      }
    } catch (_) {
      // Fall through.
    }

    if (parsed != null) throw parsed;
    throw HustlBackendWorkoutHistoryApiException(
      statusCode: res.statusCode,
      code: fallbackCode,
      message: fallbackMessage,
    );
  }

  Future<({List<Map<String, dynamic>> items, String? nextCursor})> listHistory({
    int limit = 50,
    String? cursor,
    String status = 'completed',
  }) async {
    final uri = Uri.parse('$_base/api/workouts/history').replace(
      queryParameters: {
        'limit': '$limit',
        'status': status,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    final res = await _client.get(uri, headers: await _authHeaders());
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'list_failed',
        fallbackMessage: 'Failed to list workout history',
      );
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw HustlBackendWorkoutHistoryApiException(
        statusCode: res.statusCode,
        code: 'invalid_response',
        message: 'Invalid response from server',
      );
    }
    final data = decoded['data'];
    if (data is! Map) {
      throw HustlBackendWorkoutHistoryApiException(
        statusCode: res.statusCode,
        code: 'invalid_response',
        message: 'Invalid response from server',
      );
    }
    final items = (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((m) {
          return Map<String, dynamic>.from(m);
        })
        .toList(growable: false);
    final next = data['next_cursor'];
    return (
      items: items,
      nextCursor: next is String && next.isNotEmpty ? next : null,
    );
  }

  Future<Map<String, dynamic>> fetchWorkoutDetail(String workoutId) async {
    final uri = Uri.parse('$_base/api/workouts/history/$workoutId');
    final res = await _client.get(uri, headers: await _authHeaders());
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'fetch_failed',
        fallbackMessage: 'Failed to fetch workout',
      );
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw HustlBackendWorkoutHistoryApiException(
        statusCode: res.statusCode,
        code: 'invalid_response',
        message: 'Invalid response from server',
      );
    }
    final data = decoded['data'];
    if (data is! Map) {
      throw HustlBackendWorkoutHistoryApiException(
        statusCode: res.statusCode,
        code: 'invalid_response',
        message: 'Invalid response from server',
      );
    }
    return Map<String, dynamic>.from(data);
  }
}
