import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/workout_logging/data/services/workout_sync_service.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/token_storage.dart';
import 'package:hustl_app/features/workout_logging/data/datasources/workout_sync_api.dart';
import 'package:http/http.dart' as http;

class _FakeWorkoutRepo implements WorkoutRepository {
  final Map<String, WorkoutSession> store = {};

  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession session) async {
    store[session.id] = session;
    return session;
  }

  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async => store[id];

  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession session, {
    bool markDirty = true,
  }) async {
    store[session.id] = session;
    return session;
  }

  // Unused methods
  @override
  Future<WorkoutSession> addExerciseToSession(
    String sessionId,
    WorkoutExercise exercise,
  ) => throw UnimplementedError();
  @override
  Future<WorkoutExercise> addSetToExercise(
    String sessionId,
    String exerciseId,
    WorkoutSet set,
  ) => throw UnimplementedError();
  @override
  Future<void> deleteWorkoutSession(String id) => throw UnimplementedError();
  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) => throw UnimplementedError();
  @override
  Future<WorkoutSession?> getLatestActiveSession() =>
      throw UnimplementedError();
  @override
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  }) => throw UnimplementedError();
  @override
  Future<WorkoutSession> completeWorkoutSession(String sessionId) =>
      throw UnimplementedError();
  @override
  Future<List<WorkoutSet>?> getPreviousExerciseSets(
    String exerciseName, {
    String? exerciseSlug,
  }) => throw UnimplementedError();
  @override
  Future<void> recomputeAllPrFlags() => throw UnimplementedError();
  @override
  Future<WorkoutSession> removeExerciseFromSession(
    String sessionId,
    String exerciseId,
  ) => throw UnimplementedError();
  @override
  Future<WorkoutSession> updateExerciseInSession(
    String sessionId,
    String exerciseId,
    WorkoutExercise exercise,
  ) => throw UnimplementedError();
  @override
  Future<WorkoutExercise> updateSetInExercise(
    String sessionId,
    String exerciseId,
    int setIndex,
    WorkoutSet set,
  ) => throw UnimplementedError();

  @override
  Future<DateTime?> getLastPerformedDate(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    return null;
  }

  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;
}

class _FakeSyncApi extends WorkoutSyncApi {
  _FakeSyncApi() : super(client: http.Client(), baseUrl: '');
}

void main() {
  test('set type round trip through sync maps', () {
    const set = WorkoutSet(
      id: '1',
      weight: 0,
      reps: 0,
      setType: SetType.superset,
    );
    final map = WorkoutSyncService.setToServerMap(set, 1);
    expect(map['set_type'], 'superset');
    final from = WorkoutSyncService.setFromServer(map);
    expect(from.setType, SetType.superset);
  });

  test('setToServerMap mirrors duration/distance into dedicated columns', () {
    // Duration-only (e.g. Plank): seconds live in `reps` in the app model and
    // must also be written to the `duration` column so server-side consumers
    // (exercise history stats, AI proposals) see a real value.
    const plank = WorkoutSet(id: 'p', weight: 0, reps: 30, isCompleted: true);
    final plankMap = WorkoutSyncService.setToServerMap(
      plank,
      1,
      loggingMode: ExerciseLoggingMode.durationOnly,
    );
    expect(plankMap['duration'], 30);
    expect(plankMap['distance'], isNull);
    // weight/reps still written unchanged for back-compat.
    expect(plankMap['reps'], 30);

    // Distance+duration (e.g. Treadmill): distance in `weight` (km) is converted
    // to metres for the `distance` column (backend contract); duration mirrors
    // seconds. weight/reps still written (km/seconds) for back-compat.
    const run = WorkoutSet(id: 'r', weight: 2.3, reps: 1800, isCompleted: true);
    final runMap = WorkoutSyncService.setToServerMap(
      run,
      1,
      loggingMode: ExerciseLoggingMode.distanceDuration,
    );
    expect(runMap['distance'], closeTo(2300, 0.01)); // 2.3 km -> metres
    expect(runMap['duration'], 1800);
    expect(runMap['weight'], 2.3);

    // Weight/reps: no cardio columns emitted.
    const bench = WorkoutSet(id: 'b', weight: 60, reps: 10, isCompleted: true);
    final benchMap = WorkoutSyncService.setToServerMap(
      bench,
      1,
      loggingMode: ExerciseLoggingMode.weightReps,
    );
    expect(benchMap.containsKey('duration'), isFalse);
    expect(benchMap.containsKey('distance'), isFalse);
  });

  test('setToServerMap omits duration/distance for a skipped (all-zero) set', () {
    // A completed-but-untouched timed set must not write `duration: 0` /
    // `distance: 0`, which would pollute get_exercise_history medians
    // (typicalDurationSeconds / typicalDistance).
    const skipped = WorkoutSet(id: 'z', weight: 0, reps: 0, isCompleted: true);
    final durMap = WorkoutSyncService.setToServerMap(
      skipped,
      1,
      loggingMode: ExerciseLoggingMode.durationOnly,
    );
    expect(durMap.containsKey('duration'), isFalse);
    expect(durMap.containsKey('distance'), isFalse);

    final distMap = WorkoutSyncService.setToServerMap(
      skipped,
      1,
      loggingMode: ExerciseLoggingMode.distanceDuration,
    );
    expect(distMap.containsKey('duration'), isFalse);
    expect(distMap.containsKey('distance'), isFalse);
  });

  test('importServer collects errors for malformed workouts', () async {
    final service = WorkoutSyncService(
      PreferencesService(),
      TokenStorage(),
      _FakeWorkoutRepo(),
      _FakeSyncApi(),
    );
    final result = await service.importServer([
      {'bad': 'data'},
    ]);
    expect(result.errors, isNotEmpty);
    // A page where nothing parsed is a whole-page failure: don't advance.
    expect(result.persistFailed, isTrue);
  });

  test('importServer hydrates exercise muscles and slug', () async {
    final repo = _FakeWorkoutRepo();
    final service = WorkoutSyncService(
      PreferencesService(),
      TokenStorage(),
      repo,
      _FakeSyncApi(),
    );
    final start = DateTime.now().toUtc().toIso8601String();
    await service.importServer([
      {
        'id': 'srv1',
        'name': 'Server Session',
        'start_time': start,
        'status': 'completed',
        'exercises': [
          {
            'id': 'we1',
            'exercise_name': 'Bench Press',
            'exercise_kind': 'strength',
            'primary_muscles': ['Chest', ' chest '],
            'secondary_muscles': ['Triceps'],
            'exercise_slug': 'bench-press',
            'sets': [
              {
                'id': 'set1',
                'set_number': 1,
                'weight': 20,
                'reps': 10,
                'is_completed': true,
              },
            ],
          },
        ],
      },
    ]);
    final stored = repo.store['srv1'];
    expect(stored, isNotNull);
    final exercise = stored!.exercises.first.exercise;
    expect(exercise.muscles, ['Chest', 'Triceps']);
    expect(exercise.slug, 'bench-press');
  });

  test('importServer resolves a duration-only set from the duration column',
      () async {
    // MCP / server-native shape: the value lives in the `duration` column with
    // reps null. The sync-pull path must recover it (reps=seconds, mode=
    // durationOnly) instead of dropping to 0 — otherwise "Previous"/history read
    // 00:00 for AI-logged planks.
    final repo = _FakeWorkoutRepo();
    final service = WorkoutSyncService(
      PreferencesService(),
      TokenStorage(),
      repo,
      _FakeSyncApi(),
    );
    final start = DateTime.now().toUtc().toIso8601String();
    await service.importServer([
      {
        'id': 'srvDur',
        'name': 'Core',
        'start_time': start,
        'status': 'completed',
        'exercises': [
          {
            'id': 'weDur',
            'exercise_name': 'Plank',
            'exercise_kind': 'cardio',
            'exercise_slug': 'plank',
            'sets': [
              {
                'id': 'setDur',
                'set_number': 1,
                'weight': null,
                'reps': null,
                'duration': 30,
                'distance': null,
                'is_completed': true,
              },
            ],
          },
        ],
      },
    ]);
    final stored = repo.store['srvDur'];
    expect(stored, isNotNull);
    final ex = stored!.exercises.first;
    expect(ex.exercise.loggingMode, ExerciseLoggingMode.durationOnly);
    expect(ex.sets.single.reps, 30);
  });

  test('importServer maps rest timer seconds from server payload', () async {
    final repo = _FakeWorkoutRepo();
    final service = WorkoutSyncService(
      PreferencesService(),
      TokenStorage(),
      repo,
      _FakeSyncApi(),
    );
    final start = DateTime.now().toUtc().toIso8601String();
    await service.importServer([
      {
        'id': 'srv_rest',
        'name': 'Server Session',
        'start_time': start,
        'status': 'completed',
        'exercises': [
          {
            'id': 'we_rest_1',
            'exercise_name': 'Deadlift',
            'rest_time': 120,
            'sets': const [],
          },
          {
            'id': 'we_rest_2',
            'exercise_name': 'Row',
            // Back-compat: some payloads may send camelCase.
            'restTimerSeconds': 75,
            'sets': const [],
          },
          {
            'id': 'we_rest_3',
            'exercise_name': 'Press',
            // Ensure we fall back when the first key is present but invalid.
            'rest_time': 0,
            'restTimerSeconds': 45,
            'sets': const [],
          },
        ],
      },
    ]);

    final stored = repo.store['srv_rest'];
    expect(stored, isNotNull);
    expect(stored!.exercises[0].restTimerSeconds, 120);
    expect(stored.exercises[1].restTimerSeconds, 75);
    expect(stored.exercises[2].restTimerSeconds, 45);
  });
}
