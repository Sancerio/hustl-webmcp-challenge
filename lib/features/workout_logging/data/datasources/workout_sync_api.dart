import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/network/http_client.dart';

class WorkoutSyncApi {
  final http.Client _client;
  final String _base;
  WorkoutSyncApi({http.Client? client, String? baseUrl})
    : _client = client ?? createHttpClient(),
      _base = baseUrl ?? ApiConfig.baseUrl;

  Future<
    ({
      List<Map<String, dynamic>> serverWorkouts,
      List<String> deletedWorkoutIds,
      int newSyncVersion,
    })
  >
  sync({
    required String accessToken,
    required int lastSyncVersion,
    required List<Map<String, dynamic>> clientWorkouts,
    List<String>? deletedIds,
    int? limit,
  }) async {
    final uri = Uri.parse('$_base/api/workouts/sync');
    final res = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'last_sync_version': lastSyncVersion,
        'client_workouts': clientWorkouts,
        if (deletedIds != null && deletedIds.isNotEmpty)
          'deleted_ids': deletedIds,
        if (limit != null) 'limit': limit,
      }),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final d = data['data'] as Map<String, dynamic>;
      final list = (d['server_workouts'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final deletions =
          (d['deleted_workout_ids'] as List<dynamic>? ?? <dynamic>[])
              .cast<String>();
      return (
        serverWorkouts: list,
        deletedWorkoutIds: deletions,
        newSyncVersion:
            (d['new_sync_version'] as num?)?.toInt() ?? lastSyncVersion,
      );
    }
    throw Exception('Sync failed: ${res.statusCode} ${res.body}');
  }
}
