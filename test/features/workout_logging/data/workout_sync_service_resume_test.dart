import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/features/workout_logging/data/services/workout_sync_service.dart';
import 'package:hustl_app/features/workout_logging/data/datasources/workout_sync_api.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/core/services/token_storage.dart' as token;
import 'package:hustl_app/core/services/preferences_service.dart';

class _FakeTokenStorage implements token.TokenStorage {
  String? _access;
  @override
  Future<String?> getAccessToken() async => _access;
  @override
  Future<String?> getRefreshToken() async => null;
  @override
  Future<void> saveTokenPair({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
  }) async {
    _access = accessToken;
  }

  @override
  Future<void> clearAccessToken() async {
    _access = null;
  }

  @override
  Future<void> clearAll() async {
    _access = null;
  }
}

class _FakeRepo implements WorkoutRepository {
  final Map<String, WorkoutSession> store = {};
  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession session) async {
    store[session.id] = session;
    return session;
  }

  @override
  Future<void> deleteWorkoutSession(String id) async {
    store.remove(id);
  }

  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async => store[id];
  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => store.values.toList();
  @override
  Future<WorkoutSession?> getLatestActiveSession() async {
    for (final s in store.values) {
      if (s.endTime == null) return s;
    }
    return null;
  }

  @override
  Future<WorkoutExercise> addSetToExercise(
    String sessionId,
    String exerciseId,
    WorkoutSet set,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<WorkoutSession> addExerciseToSession(
    String sessionId,
    WorkoutExercise exercise,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession session, {
    bool markDirty = true,
  }) async {
    store[session.id] = session;
    return session;
  }

  @override
  Future<WorkoutExercise> updateSetInExercise(
    String sessionId,
    String exerciseId,
    int setIndex,
    WorkoutSet set,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<WorkoutSession> completeWorkoutSession(String sessionId) async {
    final s = store[sessionId]!;
    final completed = s.copyWith(endTime: DateTime.now());
    store[sessionId] = completed;
    return completed;
  }

  @override
  Future<List<WorkoutSet>?> getPreviousExerciseSets(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;
  @override
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  }) async => false;
  @override
  Future<void> recomputeAllPrFlags() async {}
  @override
  Future<WorkoutSession> updateExerciseInSession(
    String sessionId,
    String exerciseId,
    WorkoutExercise exercise,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<WorkoutSession> removeExerciseFromSession(
    String sessionId,
    String exerciseId,
  ) async {
    throw UnimplementedError();
  }

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

// Base fake API that records calls and increments version by 1 each call
class _RecordingApi implements WorkoutSyncApi {
  List<List<Map<String, dynamic>>> callPayloads = [];
  List<int> versionCalls = [];
  List<List<String>?> deletedCalls = [];
  @override
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
    callPayloads.add(List<Map<String, dynamic>>.from(clientWorkouts));
    versionCalls.add(lastSyncVersion);
    deletedCalls.add(deletedIds);
    return (
      serverWorkouts: clientWorkouts.isEmpty
          ? <Map<String, dynamic>>[]
          : [
              {...clientWorkouts.first, 'name': 'Server Copy'},
            ],
      deletedWorkoutIds: const <String>[],
      newSyncVersion: lastSyncVersion + 1,
    );
  }
}

// API that throws on a configured call number to simulate interruption
class _FailingAfterNCallsApi extends _RecordingApi {
  int? throwOnCall; // 1-based; null means never
  int _count = 0;
  _FailingAfterNCallsApi();
  @override
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
    _count += 1;
    if (throwOnCall != null && _count == throwOnCall) {
      // Simulate a transport or server error before any state is recorded
      throw Exception('Simulated failure on call $_count');
    }
    return super.sync(
      accessToken: accessToken,
      lastSyncVersion: lastSyncVersion,
      clientWorkouts: clientWorkouts,
      deletedIds: deletedIds,
      limit: limit,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkoutSyncService resume', () {
    late PreferencesService prefs;
    late _FakeTokenStorage tokens;
    late _FakeRepo repo;
    late _FailingAfterNCallsApi api;
    late WorkoutSyncService svc;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = PreferencesService();
      await prefs.init();
      tokens = _FakeTokenStorage().._access = 'acc';
      repo = _FakeRepo();
      api = _FailingAfterNCallsApi();
      svc = WorkoutSyncService(prefs, tokens, repo, api);
    });

    test(
      'persists last version after each successful batch and resumes after interruption',
      () async {
        // Create 225 completed workouts => expected batches: 100 + 100 + 25
        for (int i = 0; i < 225; i++) {
          final s = WorkoutSession(
            id: 'w$i',
            name: 'N$i',
            startTime: DateTime.parse(
              '2024-01-01T10:00:00Z',
            ).add(Duration(minutes: i)),
            endTime: DateTime.parse(
              '2024-01-01T11:00:00Z',
            ).add(Duration(minutes: i)),
            exercises: const [
              WorkoutExercise(
                id: 'we',
                exercise: Exercise(name: 'Bench Press', muscles: []),
                sets: [
                  WorkoutSet(id: 's', weight: 100, reps: 5, isCompleted: true),
                ],
              ),
            ],
          );
          await repo.createWorkoutSession(s);
        }

        // Fail on the 3rd API call (after two successful batches)
        api.throwOnCall = 3;

        // First sync attempt: should process 2 batches, then hit failure and stop
        await svc.syncNow();

        // Verify only two calls were made and persisted version is 2
        expect(api.callPayloads.length, 2);
        final firstBatchSize = api.callPayloads[0].length;
        expect(firstBatchSize, greaterThan(0));
        expect(api.callPayloads[1].length, firstBatchSize);
        final vAfterFailure = await prefs.getWorkoutsSyncVersion();
        expect(
          vAfterFailure,
          2,
          reason: 'version must persist after each batch',
        );

        // Resume: remove failure and run again
        api.throwOnCall = null;
        final beforeCalls = api.callPayloads.length;
        await svc.syncNow();
        final secondRunCalls = api.callPayloads.length - beforeCalls;

        // Resume should start from version 2 (persisted). Our implementation
        // re-exports all local payload in batches and relies on server-side
        // idempotency, so it will perform 3 more calls (100, 100, 25).
        // Collect versionCalls from the second run: ensure a call used 2.
        // Note: versionCalls are cumulative in our recording api
        expect(
          api.versionCalls.contains(2),
          isTrue,
          reason: 'resume should pass last persisted version to API',
        );

        // Final version should be 2 (persisted) + count of batches in second run
        final vFinal = await prefs.getWorkoutsSyncVersion();
        expect(vFinal, vAfterFailure + secondRunCalls);
      },
    );
  });
}
