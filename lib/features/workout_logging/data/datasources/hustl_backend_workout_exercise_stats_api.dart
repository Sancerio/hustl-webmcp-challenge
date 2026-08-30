import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/services/token_storage.dart';
import '../../domain/models/workout_set.dart';
import '../../domain/repositories/workout_repository.dart';

class HustlBackendWorkoutExerciseStatsApiException implements Exception {
  HustlBackendWorkoutExerciseStatsApiException({
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

class HustlBackendWorkoutExerciseStatsApi {
  HustlBackendWorkoutExerciseStatsApi({
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
    HustlBackendWorkoutExerciseStatsApiException? parsed;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        final success = decoded['success'];
        final error = decoded['error'];
        if (success == false && error is Map) {
          final code = error['code']?.toString() ?? fallbackCode;
          final message = error['message']?.toString() ?? fallbackMessage;
          final details = error['details'];
          parsed = HustlBackendWorkoutExerciseStatsApiException(
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
    throw HustlBackendWorkoutExerciseStatsApiException(
      statusCode: res.statusCode,
      code: fallbackCode,
      message: fallbackMessage,
    );
  }

  Future<ExercisePr?> fetchExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    final uri = Uri.parse('$_base/api/workouts/exercises/pr').replace(
      queryParameters: {
        'exercise_name': exerciseName,
        if (exerciseSlug != null && exerciseSlug.isNotEmpty)
          'exercise_slug': exerciseSlug,
      },
    );
    final res = await _client.get(uri, headers: await _authHeaders());
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'fetch_failed',
        fallbackMessage: 'Failed to fetch PR',
      );
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw HustlBackendWorkoutExerciseStatsApiException(
        statusCode: res.statusCode,
        code: 'invalid_response',
        message: 'Invalid response from server',
      );
    }
    final data = decoded['data'];
    if (data is! Map) {
      throw HustlBackendWorkoutExerciseStatsApiException(
        statusCode: res.statusCode,
        code: 'invalid_response',
        message: 'Invalid response from server',
      );
    }
    final pr = data['pr'];
    if (pr is! Map) return null;
    final weight = pr['weight'];
    final reps = pr['reps'];
    if (weight is! num || reps is! num) return null;
    return ExercisePr(weight: weight.toDouble(), reps: reps.toInt());
  }

  Future<List<WorkoutSet>> fetchPreviousExerciseSets(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    final uri = Uri.parse('$_base/api/workouts/exercises/previous').replace(
      queryParameters: {
        'exercise_name': exerciseName,
        if (exerciseSlug != null && exerciseSlug.isNotEmpty)
          'exercise_slug': exerciseSlug,
      },
    );
    final res = await _client.get(uri, headers: await _authHeaders());
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwApiError(
        res,
        fallbackCode: 'fetch_failed',
        fallbackMessage: 'Failed to fetch previous sets',
      );
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw HustlBackendWorkoutExerciseStatsApiException(
        statusCode: res.statusCode,
        code: 'invalid_response',
        message: 'Invalid response from server',
      );
    }
    final data = decoded['data'];
    if (data is! Map) {
      throw HustlBackendWorkoutExerciseStatsApiException(
        statusCode: res.statusCode,
        code: 'invalid_response',
        message: 'Invalid response from server',
      );
    }
    final rawSets = data['sets'];
    if (rawSets is! List) return const <WorkoutSet>[];
    final sets = <WorkoutSet>[];
    for (final item in rawSets) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final id = m['id'];
      if (id is! String || id.isEmpty) continue;

      final weight = (m['weight'] as num?)?.toDouble();
      final reps = (m['reps'] as num?)?.toInt();
      final duration = (m['duration'] as num?)?.toInt();
      final distance = (m['distance'] as num?)?.toDouble();

      final hasCardioFields =
          (distance != null && distance != 0) ||
          (duration != null && duration != 0);
      // `exercise_sets.distance` is METRES per the backend/MCP contract; the app
      // models cardio distance as km (WorkoutSet.weight), so convert here. Falls
      // back to `weight` (already km) for legacy rows that omitted the column.
      final resolvedWeight = hasCardioFields
          ? ((distance ?? 0.0) / 1000.0)
          : (weight ?? 0.0);
      final resolvedReps = hasCardioFields ? (duration ?? 0) : (reps ?? 0);

      sets.add(
        WorkoutSet(
          id: id,
          weight: resolvedWeight,
          reps: resolvedReps,
          rpe: (m['rpe'] as num?)?.toInt(),
          setType: WorkoutSet.parseSetType(m['set_type']),
          isCompleted: (m['is_completed'] as bool?) ?? true,
          // Dropset linkage so drops round-trip from the previous session
          // (cross-device / after local cache loss). Null = standalone/legacy.
          parentSetId: m['parent_set_id'] as String?,
          dropIndex: (m['drop_index'] as num?)?.toInt(),
        ),
      );
    }
    return sets;
  }
}
