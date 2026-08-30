import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/webmcp/workout_history_web_mcp_service.dart';
import 'package:hustl_app/features/workout_logging/data/datasources/hustl_backend_exercise_history_api.dart';
import 'package:hustl_app/features/workout_logging/data/datasources/hustl_backend_workout_history_api.dart';
import 'package:mocktail/mocktail.dart';

class _MockHistoryApi extends Mock implements HustlBackendWorkoutHistoryApi {}

class _MockExerciseHistoryApi extends Mock
    implements HustlBackendExerciseHistoryApi {}

void main() {
  late _MockHistoryApi api;
  late _MockExerciseHistoryApi exerciseApi;
  late WorkoutHistoryWebMcpService service;

  setUp(() {
    api = _MockHistoryApi();
    exerciseApi = _MockExerciseHistoryApi();
    service = WorkoutHistoryWebMcpService(
      historyApi: api,
      exerciseApi: exerciseApi,
    );
  });

  test(
    'workout history caps rows and strips notes and nested detail',
    () async {
      final rows = List.generate(
        21,
        (index) => <String, dynamic>{
          'id': 'workout-$index',
          'name': 'Workout $index',
          'start_time': '2026-08-28T00:00:00.000Z',
          'end_time': null,
          'duration': index == 0 ? 0 : null,
          'status': 'completed',
          'notes': 'private note',
          'exercises': [
            {'secret': 'raw set detail'},
          ],
        },
      );
      when(
        () => api.listHistory(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
          status: any(named: 'status'),
        ),
      ).thenAnswer((_) async => (items: rows, nextCursor: 'next-page'));

      final result = await service.loadWorkoutHistory(
        limit: 99,
        cursor: 'current-page',
      );

      expect(result['workoutCount'], 20);
      expect(result['hasMore'], isTrue);
      expect(result['nextCursor'], 'next-page');
      final workouts = result['workouts']! as List<Object?>;
      expect(workouts, hasLength(20));
      expect(workouts.first, {
        'id': 'workout-0',
        'name': 'Workout 0',
        'startAt': '2026-08-28T00:00:00.000Z',
        'endAt': null,
        'durationSeconds': 0,
        'status': 'completed',
      });
      expect(result.toString(), isNot(contains('private note')));
      expect(result.toString(), isNot(contains('raw set detail')));
      verify(
        () => api.listHistory(
          limit: 20,
          cursor: 'current-page',
          status: 'completed',
        ),
      ).called(1);
    },
  );

  test('exercise history caps and keeps null, zero, and assistance', () async {
    final items = <Map<String, Object?>>[
      {
        'exerciseId': 'must-not-escape',
        'ownerUserId': 'must-not-escape',
        'name': 'Assisted Pull-up',
        'slug': 'assisted-pull-up',
        'kind': 'strength',
        'loggingMode': 'weight_reps',
        'source': 'custom',
        'primaryMuscles': ['Back'],
        'frequency': 0,
        'lastUsedAt': null,
        'typicalSets': null,
        'typicalReps': 0,
        'typicalWeight': -25,
      },
      ...List.generate(
        20,
        (index) => <String, Object?>{
          'name': 'Run $index',
          'slug': 'run-$index',
          'kind': 'cardio',
          'loggingMode': 'distance_duration',
          'source': 'catalog',
          'primaryMuscles': const <String>[],
          'frequency': index + 1,
          'lastUsedAt': '2026-08-28T00:00:00.000Z',
          'typicalSets': 1,
          'typicalDistance': 0,
          'typicalDurationSeconds': null,
        },
      ),
    ];
    when(
      () => exerciseApi.getExerciseHistory(
        limit: any(named: 'limit'),
        sinceDays: any(named: 'sinceDays'),
      ),
    ).thenAnswer(
      (_) async => {
        'range': {'sinceDays': 3650, 'since': '2016-09-01'},
        'exerciseCount': items.length,
        'items': items,
      },
    );

    final result = await service.loadExerciseHistory(
      limit: 99,
      sinceDays: 9999,
    );

    expect(result['exerciseCount'], 20);
    final exercises = result['exercises']! as List<Object?>;
    expect(exercises, hasLength(20));
    expect(exercises.first, {
      'name': 'Assisted Pull-up',
      'slug': 'assisted-pull-up',
      'kind': 'strength',
      'loggingMode': 'weight_reps',
      'source': 'custom',
      'primaryMuscles': ['Back'],
      'frequency': 0,
      'lastUsedAt': null,
      'typicalSets': null,
      'typicalReps': 0,
      'typicalWeight': -25.0,
    });
    expect(result.toString(), isNot(contains('must-not-escape')));
    verify(
      () => exerciseApi.getExerciseHistory(limit: 20, sinceDays: 3650),
    ).called(1);
  });
}
