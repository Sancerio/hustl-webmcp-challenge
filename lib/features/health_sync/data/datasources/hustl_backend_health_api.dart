import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/services/token_storage.dart';
import '../models/backend_weekly_health_projection.dart';

class HustlBackendHealthApi {
  HustlBackendHealthApi({
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

  Future<void> upsertDailyMetrics({
    required String provider,
    required String lastSyncedAt,
    required List<Map<String, dynamic>> items,
  }) async {
    await upsertHealthData(
      provider: provider,
      lastSyncedAt: lastSyncedAt,
      items: items,
    );
  }

  Future<void> upsertHealthData({
    required String provider,
    required String lastSyncedAt,
    List<Map<String, dynamic>> items = const [],
    List<Map<String, dynamic>> observations = const [],
    List<Map<String, dynamic>> sessions = const [],
  }) async {
    final token = await tokens.getAccessToken();
    if (token == null) return;

    final uri = Uri.parse('$_base/api/health/metrics');
    final headers = await _authHeaders();
    final payload = {
      'provider': provider,
      'lastSyncedAt': lastSyncedAt,
      'items': items,
      'observations': observations,
      'sessions': sessions,
    };
    final res = await _client.post(
      uri,
      headers: headers,
      body: jsonEncode(payload),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Failed to sync health metrics (${res.statusCode})');
    }
  }

  Future<BackendWeeklyHealthProjection> fetchWeeklyProjection({
    required DateTime start,
    required DateTime end,
  }) async {
    final token = await tokens.getAccessToken();
    if (token == null || token.isEmpty) {
      throw StateError('Authentication is required to load weekly health data');
    }
    final uri = Uri.parse(
      '$_base/api/health/weekly',
    ).replace(queryParameters: {'start': _dayKey(start), 'end': _dayKey(end)});
    final response = await _client.get(uri, headers: await _authHeaders());
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to load weekly health data (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      throw const FormatException('Invalid weekly health response');
    }
    final data = decoded['data'];
    if (data is! Map) {
      throw const FormatException('Weekly health response is missing data');
    }
    return BackendWeeklyHealthProjection.fromApiData(
      Map<String, dynamic>.from(data),
    );
  }
}

String _dayKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
