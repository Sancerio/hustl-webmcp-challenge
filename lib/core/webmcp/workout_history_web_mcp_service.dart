import '../../features/workout_logging/data/datasources/hustl_backend_exercise_history_api.dart';
import '../../features/workout_logging/data/datasources/hustl_backend_workout_history_api.dart';

abstract interface class WorkoutHistoryWebMcpReader {
  Future<Map<String, Object?>> loadWorkoutHistory({
    required int limit,
    String? cursor,
  });

  Future<Map<String, Object?>> loadExerciseHistory({
    required int limit,
    required int sinceDays,
  });
}

class WorkoutHistoryWebMcpService implements WorkoutHistoryWebMcpReader {
  const WorkoutHistoryWebMcpService({
    required HustlBackendWorkoutHistoryApi historyApi,
    required HustlBackendExerciseHistoryApi exerciseApi,
  }) : _historyApi = historyApi,
       _exerciseApi = exerciseApi;

  final HustlBackendWorkoutHistoryApi _historyApi;
  final HustlBackendExerciseHistoryApi _exerciseApi;

  @override
  Future<Map<String, Object?>> loadWorkoutHistory({
    required int limit,
    String? cursor,
  }) async {
    final boundedLimit = limit.clamp(1, 20).toInt();
    final response = await _historyApi.listHistory(
      limit: boundedLimit,
      cursor: cursor,
      status: 'completed',
    );
    final bounded = response.items
        .take(boundedLimit)
        .map(_workoutSummaryJson)
        .toList(growable: false);
    final nextCursor = _boundedString(response.nextCursor, 1024);
    return {
      'status': 'ready',
      'workoutCount': bounded.length,
      'hasMore': nextCursor != null,
      'nextCursor': nextCursor,
      'workouts': bounded,
    };
  }

  @override
  Future<Map<String, Object?>> loadExerciseHistory({
    required int limit,
    required int sinceDays,
  }) async {
    final boundedLimit = limit.clamp(1, 20).toInt();
    final response = await _exerciseApi.getExerciseHistory(
      limit: boundedLimit,
      sinceDays: sinceDays.clamp(1, 3650).toInt(),
    );
    final rawItems = response['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .take(boundedLimit)
              .map(_exerciseHistoryJson)
              .toList(growable: false)
        : const <Map<String, Object?>>[];
    final rawRange = response['range'];
    final range = rawRange is Map
        ? <String, Object?>{
            'sinceDays': _integer(rawRange['sinceDays']),
            'since': _boundedString(rawRange['since'], 10),
          }
        : <String, Object?>{'sinceDays': sinceDays, 'since': null};
    return {
      'status': 'ready',
      'range': range,
      'exerciseCount': items.length,
      'exercises': items,
    };
  }

  static Map<String, Object?> _workoutSummaryJson(Map<String, dynamic> row) => {
    'id': _boundedString(row['id'], 128),
    'name': _boundedString(row['name'], 120),
    'startAt': _boundedString(row['start_time'], 40),
    'endAt': _boundedString(row['end_time'], 40),
    'durationSeconds': _integer(row['duration']),
    'status': _boundedString(row['status'], 24),
  };

  static Map<String, Object?> _exerciseHistoryJson(Map row) {
    final primaryMuscles = row['primaryMuscles'];
    final loggingMode = _boundedString(row['loggingMode'], 50);
    final isCardio =
        loggingMode == 'distance_duration' || loggingMode == 'duration_only';
    return {
      'name': _boundedString(row['name'], 120),
      'slug': _boundedString(row['slug'], 120),
      'kind': _boundedString(row['kind'], 50),
      'loggingMode': loggingMode,
      'source': _boundedString(row['source'], 16),
      'primaryMuscles': primaryMuscles is List
          ? primaryMuscles
                .map((value) => _boundedString(value, 80))
                .whereType<String>()
                .take(20)
                .toList(growable: false)
          : const <String>[],
      'frequency': _integer(row['frequency']),
      'lastUsedAt': _boundedString(row['lastUsedAt'], 40),
      'typicalSets': _integer(row['typicalSets']),
      if (isCardio) ...{
        'typicalDistance': _number(row['typicalDistance']),
        'typicalDurationSeconds': _integer(row['typicalDurationSeconds']),
      } else ...{
        'typicalReps': _integer(row['typicalReps']),
        'typicalWeight': _number(row['typicalWeight']),
      },
    };
  }

  static String? _boundedString(Object? raw, int maximum) {
    if (raw is! String) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;
    return value.length <= maximum ? value : value.substring(0, maximum);
  }

  static int? _integer(Object? raw) {
    if (raw is! num || !raw.isFinite) return null;
    return raw.round();
  }

  static double? _number(Object? raw) {
    if (raw is! num || !raw.isFinite) return null;
    return raw.toDouble();
  }
}
