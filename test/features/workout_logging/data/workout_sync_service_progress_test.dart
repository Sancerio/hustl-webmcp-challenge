import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/token_storage.dart';
import 'package:hustl_app/features/workout_logging/data/services/workout_sync_service.dart';
import 'package:hustl_app/features/workout_logging/data/datasources/workout_sync_api.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';

class _FakeTokenStorage implements TokenStorage {
  @override
  Future<void> clearAccessToken() async {}

  @override
  Future<void> clearAll() async {}

  @override
  Future<String?> getAccessToken() async => 'token';

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<void> saveTokenPair({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
  }) async {}
}

class _FakeApi implements WorkoutSyncApi {
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
    return (
      serverWorkouts: <Map<String, dynamic>>[],
      deletedWorkoutIds: const <String>[],
      newSyncVersion: lastSyncVersion + 1,
    );
  }
}

class _FakeRepo implements WorkoutRepository {
  final List<WorkoutSession> sessions;
  _FakeRepo(this.sessions);

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => sessions;

  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async {
    try {
      return sessions.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession session, {
    bool markDirty = true,
  }) async {
    final idx = sessions.indexWhere((s) => s.id == session.id);
    if (idx >= 0) sessions[idx] = session;
    return session;
  }

  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession session) async {
    sessions.add(session);
    return session;
  }

  // Unused methods
  @override
  Future<WorkoutSession> addExerciseToSession(
    String sessionId,
    WorkoutExercise exercise,
  ) async => sessions.first;
  @override
  Future<WorkoutExercise> addSetToExercise(
    String sessionId,
    String exerciseId,
    WorkoutSet set,
  ) async => const WorkoutExercise(
    id: 'e',
    exercise: Exercise(name: 'ex', muscles: []),
    sets: [],
  );
  @override
  Future<WorkoutSession> completeWorkoutSession(String sessionId) async =>
      sessions.first;
  @override
  Future<void> deleteWorkoutSession(String id) async {}
  @override
  Future<WorkoutSession?> getLatestActiveSession() async => null;
  @override
  Future<List<WorkoutSet>?> getPreviousExerciseSets(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;
  @override
  Future<WorkoutSession> removeExerciseFromSession(
    String sessionId,
    String exerciseId,
  ) async => sessions.first;
  @override
  Future<WorkoutSession> updateExerciseInSession(
    String sessionId,
    String exerciseId,
    WorkoutExercise exercise,
  ) async => sessions.first;
  @override
  Future<WorkoutExercise> updateSetInExercise(
    String sessionId,
    String exerciseId,
    int setIndex,
    WorkoutSet set,
  ) async => const WorkoutExercise(
    id: 'e',
    exercise: Exercise(name: 'ex', muscles: []),
    sets: [],
  );
  @override
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  }) async => false;
  @override
  Future<void> recomputeAllPrFlags() async {}

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

void main() {
  test('syncNow emits progress updates', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    final token = _FakeTokenStorage();
    final sessions = List.generate(
      250,
      (i) => WorkoutSession(
        id: 's\$i',
        name: 'w',
        startTime: DateTime(2024, 1, 1),
        endTime: DateTime(2024, 1, 1, 1),
        exercises: const [],
      ),
    );
    final repo = _FakeRepo(sessions);
    final api = _FakeApi();
    final svc = WorkoutSyncService(prefs, token, repo, api);

    final progressValues = <SyncProgress?>[];
    svc.progress.addListener(() {
      progressValues.add(svc.progress.value);
    });

    await svc.syncNow();

    expect(progressValues.first, const SyncProgress(0, 250));
    expect(progressValues, contains(const SyncProgress(25, 250)));
    expect(progressValues, contains(const SyncProgress(150, 250)));
    expect(progressValues, contains(const SyncProgress(250, 250)));
    expect(progressValues.last, isNull);
  });
}
