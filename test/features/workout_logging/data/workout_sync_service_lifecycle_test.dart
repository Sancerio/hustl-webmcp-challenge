import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hustl_app/features/workout_logging/data/services/workout_sync_service.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/token_storage.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/data/datasources/workout_sync_api.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';

class _FakeTokenStorage implements TokenStorage {
  String? token = 't';
  @override
  Future<void> saveTokenPair({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
  }) async {
    token = accessToken;
  }

  @override
  Future<String?> getAccessToken() async => token;

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<void> clearAccessToken() async {
    token = null;
  }

  @override
  Future<void> clearAll() async {
    token = null;
  }
}

class _FakeWorkoutRepo implements WorkoutRepository {
  WorkoutSession _session() => WorkoutSession(
    id: '1',
    name: 'Test',
    startTime: DateTime(2024),
    exercises: const [],
  );
  WorkoutExercise _exercise() => const WorkoutExercise(
    id: 'e1',
    exercise: Exercise(name: 'ex', muscles: []),
    sets: [],
  );
  @override
  Future<WorkoutSession> addExerciseToSession(
    String sessionId,
    WorkoutExercise exercise,
  ) async => _session();

  @override
  Future<WorkoutExercise> addSetToExercise(
    String sessionId,
    String exerciseId,
    WorkoutSet set,
  ) async => _exercise();

  @override
  Future<WorkoutSession> completeWorkoutSession(String sessionId) async =>
      _session();

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
  Future<WorkoutSession?> getWorkoutSession(String id) async => null;

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];

  @override
  Future<void> recomputeAllPrFlags() async {}

  @override
  Future<WorkoutSession> updateExerciseInSession(
    String sessionId,
    String exerciseId,
    WorkoutExercise exercise,
  ) async => _session();

  @override
  Future<WorkoutExercise> updateSetInExercise(
    String sessionId,
    String exerciseId,
    int setIndex,
    WorkoutSet set,
  ) async => _exercise();

  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession session, {
    bool markDirty = true,
  }) async => session;

  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession session) async =>
      session;

  @override
  Future<WorkoutSession> removeExerciseFromSession(
    String sessionId,
    String exerciseId,
  ) async => _session();

  @override
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  }) async => false;

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

class _FakeWorkoutSyncApi implements WorkoutSyncApi {
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
      newSyncVersion: lastSyncVersion,
    );
  }
}

class _TestService extends WorkoutSyncService {
  _TestService(super.prefs, super.tokens, super.repo, super.api);

  bool startCalled = false;
  bool syncCalled = false;

  @override
  void startAutoSync() {
    startCalled = true;
  }

  @override
  Future<void> syncNow() async {
    syncCalled = true;
  }
}

void main() {
  test('restarts auto sync when app resumes', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    final svc = _TestService(
      prefs,
      _FakeTokenStorage(),
      _FakeWorkoutRepo(),
      _FakeWorkoutSyncApi(),
    );

    svc.didChangeAppLifecycleState(AppLifecycleState.resumed);
    // Wait for debounce window to fire
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(svc.startCalled, isTrue);
    expect(svc.syncCalled, isTrue);
  });

  test('debounces rapid resume events (one start + one sync)', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    final svc = _TestService(
      prefs,
      _FakeTokenStorage(),
      _FakeWorkoutRepo(),
      _FakeWorkoutSyncApi(),
    );

    svc.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    svc.didChangeAppLifecycleState(AppLifecycleState.resumed);

    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(svc.startCalled, isTrue);
    expect(svc.syncCalled, isTrue);
  });

  test('skip syncNow if already syncing on subsequent resume', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();

    // Fake API that delays to keep _isSyncing true long enough for second resume
    final delayedApi = _FakeWorkoutSyncApiWithDelay(
      const Duration(milliseconds: 400),
    );

    final svc = _CountingService(
      prefs,
      _FakeTokenStorage(),
      _FakeWorkoutRepo(),
      delayedApi,
    );

    // First resume triggers sync
    svc.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    // While first sync likely still running (due to delay), trigger another resume
    svc.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 700));

    // Only one sync should have been invoked due to isSyncing guard
    expect(svc.syncCount, 1);
  });
}

class _FakeWorkoutSyncApiWithDelay implements WorkoutSyncApi {
  final Duration delay;
  _FakeWorkoutSyncApiWithDelay(this.delay);
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
    await Future<void>.delayed(delay);
    return (
      serverWorkouts: const <Map<String, dynamic>>[],
      deletedWorkoutIds: const <String>[],
      newSyncVersion: lastSyncVersion,
    );
  }
}

class _CountingService extends WorkoutSyncService {
  _CountingService(super.prefs, super.tokens, super.repo, super.api);

  int syncCount = 0;

  @override
  Future<void> syncNow() async {
    syncCount += 1;
    await super.syncNow();
  }
}
