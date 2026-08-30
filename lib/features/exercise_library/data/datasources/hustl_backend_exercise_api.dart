import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/network/http_client.dart';
import '../../domain/models/exercise.dart';
import 'exercise_api_mapper.dart';

/// Backend API client for Hustl exercises
class HustlBackendExerciseApi {
  final http.Client _client;
  final String _base;
  final String _debugToken;

  HustlBackendExerciseApi({
    http.Client? client,
    String? baseUrl,
    String? debugToken,
  }) : _client = client ?? createHttpClient(),
       _base = baseUrl ?? ApiConfig.baseUrl,
       _debugToken = debugToken ?? ApiConfig.exerciseGenerationDebugToken;

  Map<String, String> _debugHeaders(String accessToken) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $accessToken',
    if (_debugToken.isNotEmpty) 'x-debug-token': _debugToken,
  };

  String _apiErrorDetail(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        final raw = decoded['error'];
        if (raw is Map) {
          final err = Map<String, dynamic>.from(raw);
          final code = err['code']?.toString();
          final message = err['message']?.toString();
          final parts = <String>[
            if (code != null && code.isNotEmpty) code,
            if (message != null && message.isNotEmpty) message,
          ];
          if (parts.isNotEmpty) return parts.join(': ');
        }
      }
    } catch (_) {}
    return res.body.trim().isNotEmpty ? res.body.trim() : 'Request failed';
  }

  Future<http.Response> _getWithRetry(
    Uri uri, {
    Map<String, String>? headers,
    int retries = 2,
  }) async {
    int attempt = 0;
    Object? lastErr;
    while (attempt <= retries) {
      try {
        final res = await _client.get(uri, headers: headers);
        if (res.statusCode >= 500 &&
            res.statusCode < 600 &&
            attempt < retries) {
          // transient server error, backoff and retry
          await Future.delayed(Duration(milliseconds: 200 * (1 << attempt)));
          attempt++;
          continue;
        }
        return res;
      } catch (e) {
        lastErr = e;
        if (attempt >= retries) rethrow;
        await Future.delayed(Duration(milliseconds: 200 * (1 << attempt)));
        attempt++;
      }
    }
    // Should not be reached
    throw lastErr ?? Exception('Request failed');
  }

  Future<List<Exercise>> listExercises({
    int limit = 500,
    int offset = 0,
    String? search,
    String? muscle,
  }) async {
    final uri = Uri.parse('$_base/api/exercises').replace(
      queryParameters: {
        'limit': '$limit',
        'offset': '$offset',
        if (search != null && search.isNotEmpty) 'search': search,
        if (muscle != null && muscle.isNotEmpty) 'muscle': muscle,
      },
    );
    final res = await _getWithRetry(
      uri,
      headers: const {'Content-Type': 'application/json'},
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Exercises request failed: ${res.statusCode}');
    }
    final Map<String, dynamic> body =
        jsonDecode(res.body) as Map<String, dynamic>;
    final List<dynamic> items = (body['data']?['items'] as List?) ?? const [];
    return items
        .map((e) => mapExerciseFromBackend(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
  }

  Future<String?> regenerateThumbnail({
    String? id,
    String? slug,
    required String accessToken,
    String? steerImageUrl,
    String? steerImageDataUrl,
  }) async {
    if ((id == null || id.isEmpty) && (slug == null || slug.isEmpty)) {
      throw ArgumentError('Provide id or slug');
    }
    final uri = Uri.parse('$_base/api/exercises/images');
    final res = await _client.post(
      uri,
      headers: _debugHeaders(accessToken),
      body: jsonEncode({
        if (id != null && id.isNotEmpty) 'id': id else 'slug': slug,
        'variants': ['thumb'],
        if (steerImageUrl != null && steerImageUrl.trim().isNotEmpty)
          'steer_image_url': steerImageUrl.trim(),
        if (steerImageDataUrl != null && steerImageDataUrl.trim().isNotEmpty)
          'steer_image_data_url': steerImageDataUrl.trim(),
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        'Thumbnail regeneration failed (${res.statusCode}): ${_apiErrorDetail(res)}',
      );
    }
    final Map<String, dynamic> body =
        jsonDecode(res.body) as Map<String, dynamic>;
    final uploads = body['data']?['uploads'] as List?;
    if (uploads == null) return null;
    for (final u in uploads) {
      final m = Map<String, dynamic>.from(u as Map);
      if (m['variant'] == 'thumb' && m['url'] is String) {
        return m['url'] as String;
      }
    }
    return null;
  }

  Future<Exercise> generateExerciseText({
    String? id,
    String? slug,
    required String mode,
    required String accessToken,
  }) async {
    if ((id == null || id.isEmpty) && (slug == null || slug.isEmpty)) {
      throw ArgumentError('Provide id or slug');
    }
    if (mode != 'overview' && mode != 'how_to') {
      throw ArgumentError('Provide mode=overview|how_to');
    }
    final uri = Uri.parse('$_base/api/exercises/text');
    final res = await _client.post(
      uri,
      headers: _debugHeaders(accessToken),
      body: jsonEncode({
        if (id != null && id.isNotEmpty) 'id': id else 'slug': slug,
        'mode': mode,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        'Text generation failed (${res.statusCode}): ${_apiErrorDetail(res)}',
      );
    }

    final Map<String, dynamic> body =
        jsonDecode(res.body) as Map<String, dynamic>;
    final data = body['data'];
    if (data is! Map) {
      throw Exception('Text generation failed: Invalid response');
    }
    return mapExerciseFromBackend(Map<String, dynamic>.from(data));
  }
}
