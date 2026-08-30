import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/network/http_client.dart';
import '../../domain/models/exercise.dart';
import 'exercise_api_mapper.dart';

class ExerciseCustomApi {
  final http.Client _client;
  final String _base;

  ExerciseCustomApi({http.Client? client, String? baseUrl})
    : _client = client ?? createHttpClient(),
      _base = baseUrl ?? ApiConfig.baseUrl;

  Future<List<Exercise>> listMine({required String accessToken}) async {
    final uri = Uri.parse('$_base/api/exercises/custom');
    final res = await _client.get(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final d = data['data'] as Map<String, dynamic>;
      final items = (d['items'] as List<dynamic>? ?? const [])
          .map(
            (e) => mapExerciseFromBackend(
              Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
            ),
          )
          .toList(growable: false);
      return items;
    }
    throw Exception(
      'List custom exercises failed: ${res.statusCode} ${res.body}',
    );
  }

  Future<Exercise> createOrUpdate({
    required String accessToken,
    required Map<String, dynamic> payload,
  }) async {
    final uri = Uri.parse('$_base/api/exercises/custom');
    final res = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(payload),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return mapExerciseFromBackend(
        Map<String, dynamic>.from(data['data'] as Map),
      );
    }
    throw Exception(
      'Create custom exercise failed: ${res.statusCode} ${res.body}',
    );
  }

  Future<Exercise> update({
    required String accessToken,
    required String id,
    required Map<String, dynamic> updates,
  }) async {
    final uri = Uri.parse('$_base/api/exercises/custom/$id');
    final res = await _client.patch(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(updates),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return mapExerciseFromBackend(
        Map<String, dynamic>.from(data['data'] as Map),
      );
    }
    throw Exception(
      'Update custom exercise failed: ${res.statusCode} ${res.body}',
    );
  }

  Future<void> delete({required String accessToken, required String id}) async {
    final uri = Uri.parse('$_base/api/exercises/custom/$id');
    final res = await _client.delete(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw Exception(
      'Delete custom exercise failed: ${res.statusCode} ${res.body}',
    );
  }

  Future<List<Exercise>> listShared({
    required String accessToken,
    String? search,
  }) async {
    final uri = Uri.parse('$_base/api/exercises/shared').replace(
      queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    final res = await _client.get(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final d = data['data'] as Map<String, dynamic>;
      final items = (d['items'] as List<dynamic>? ?? const [])
          .map(
            (e) => mapExerciseFromBackend(
              Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
            ),
          )
          .toList(growable: false);
      return items;
    }
    throw Exception(
      'List shared exercises failed: ${res.statusCode} ${res.body}',
    );
  }
}
