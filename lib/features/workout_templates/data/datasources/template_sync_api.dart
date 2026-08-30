import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/network/http_client.dart';

class TemplateSyncApi {
  final http.Client _client;
  final String _base;
  TemplateSyncApi({http.Client? client, String? baseUrl})
    : _client = client ?? createHttpClient(),
      _base = baseUrl ?? ApiConfig.baseUrl;

  Future<({List<Map<String, dynamic>> items, int cursor})> delta({
    required String accessToken,
    required int since,
  }) async {
    final uri = Uri.parse('$_base/api/templates/delta?since=$since');
    final res = await _client.get(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final d = data['data'] as Map<String, dynamic>;
      final items = (d['items'] as List<dynamic>).cast<Map<String, dynamic>>();
      final cursor = (d['cursor'] as num?)?.toInt() ?? since;
      return (items: items, cursor: cursor);
    }
    throw Exception('Template delta failed: ${res.statusCode} ${res.body}');
  }

  Future<int> batch({
    required String accessToken,
    required List<Map<String, dynamic>> upserts,
    required List<String> deletes,
  }) async {
    final uri = Uri.parse('$_base/api/templates/batch');
    final res = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'upserts': upserts, 'deletes': deletes}),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final d = data['data'] as Map<String, dynamic>;
      return (d['cursor'] as num?)?.toInt() ?? 0;
    }
    throw Exception('Template batch failed: ${res.statusCode} ${res.body}');
  }
}
