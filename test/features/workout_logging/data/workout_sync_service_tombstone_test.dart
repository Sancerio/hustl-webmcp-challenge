import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/token_storage.dart' as token;
import 'package:hustl_app/features/workout_logging/data/datasources/workout_sync_api.dart';
import 'package:hustl_app/features/workout_logging/data/services/workout_sync_service.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';

class _TokenStorage implements token.TokenStorage {
  @override
  Future<String?> getAccessToken() async => 'tok';
  @override
  Future<String?> getRefreshToken() async => null;
  @override
  Future<void> saveTokenPair({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
  }) async {}
  @override
  Future<void> clearAccessToken() async {}
  @override
  Future<void> clearAll() async {}
}

class _Repo implements WorkoutRepository {
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
  Future<WorkoutSession?> getLatestActiveSession() async => null;
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
  Future<WorkoutExercise> addSetToExercise(
    String sessionId,
    String exerciseId,
    WorkoutSet set,
  ) async => throw UnimplementedError();
  @override
  Future<WorkoutSession> addExerciseToSession(
    String sessionId,
    WorkoutExercise exercise,
  ) async => throw UnimplementedError();
  @override
  Future<WorkoutExercise> updateSetInExercise(
    String sessionId,
    String exerciseId,
    int setIndex,
    WorkoutSet set,
  ) async => throw UnimplementedError();
  @override
  Future<WorkoutSession> completeWorkoutSession(String sessionId) async =>
      throw UnimplementedError();
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
  ) async => throw UnimplementedError();
  @override
  Future<WorkoutSession> removeExerciseFromSession(
    String sessionId,
    String exerciseId,
  ) async => throw UnimplementedError();

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

class _Api implements WorkoutSyncApi {
  List<String>? lastDeleted;
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
    lastDeleted = deletedIds;
    return (
      serverWorkouts: const <Map<String, dynamic>>[],
      deletedWorkoutIds: const ['serverDel'],
      newSyncVersion: lastSyncVersion + 1,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('syncNow sends local deletions and applies server tombstones', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    await prefs.addWorkoutsDeletedId('localDel');

    final repo = _Repo();
    repo.store['serverDel'] = WorkoutSession(
      id: 'serverDel',
      name: 'S',
      startTime: DateTime.now(),
      endTime: DateTime.now(),
      exercises: const [],
      isCompleted: true,
      dirty: false,
    );

    final api = _Api();
    final svc = WorkoutSyncService(prefs, _TokenStorage(), repo, api);
    await svc.syncNow();

    expect(api.lastDeleted, ['localDel']);
    expect(await prefs.getWorkoutsDeletedIds(), isEmpty);
    expect(repo.store.containsKey('serverDel'), isFalse);
  });
}
