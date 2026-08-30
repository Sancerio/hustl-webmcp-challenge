import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/notification_service.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/token_storage.dart' as token;
import 'package:hustl_app/features/workout_logging/data/datasources/workout_sync_api.dart';
import 'package:hustl_app/features/workout_logging/data/services/workout_sync_service.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';

class _FakeTokenStorage implements token.TokenStorage {
  @override
  Future<String?> getAccessToken() async => 'acc';
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

class _FakeRepo implements WorkoutRepository {
  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async =>
      // Return a couple so we definitely hit the API and then fail
      [
        WorkoutSession(
          id: 'a',
          name: 'A',
          startTime: DateTime(2024, 1, 1, 10),
          endTime: DateTime(2024, 1, 1, 11),
          exercises: const [],
          dirty: true,
        ),
      ];

  // Unused in this test
  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async => null;
  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession session, {
    bool markDirty = true,
  }) async => session;
  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession session) async =>
      session;
  @override
  Future<void> deleteWorkoutSession(String id) async {}
  @override
  Future<WorkoutSession?> getLatestActiveSession() async => null;
  @override
  Future<WorkoutSession> addExerciseToSession(
    String sessionId,
    WorkoutExercise exercise,
  ) async => throw UnimplementedError();
  @override
  Future<WorkoutExercise> addSetToExercise(
    String sessionId,
    String exerciseId,
    WorkoutSet set,
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

class _FailingApi implements WorkoutSyncApi {
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
    throw Exception('Network down');
  }
}

class _RecordingNotificationService implements NotificationService {

  @override
  Future<void> showAutoLoggedProposal({required String id, required bool isFood, required String body}) async {}


  @override
  Future<void> handleAppLaunchNotification() async {}
  int calls = 0;
  String? lastMessage;
  @override
  Future<void> init() async {}
  @override
  Future<void> navigateToActiveWorkout() async {}

  @override
  Future<void> navigateToProposal(String? id) async {}
  @override
  Future<void> showRestComplete({
    String? exerciseName,
    bool isNextSet = false,
    bool skipForegroundBell = false,
  }) async {}
  @override
  Future<void> scheduleRestComplete(
    int seconds, {
    String? exerciseName,
    bool isNextSet = false,
  }) async {}
  @override
  Future<void> cancelRestComplete() async {}
  @override
  Future<void> scheduleInactivityReminder(int seconds) async {}
  @override
  Future<void> cancelInactivityReminder() async {}
  @override
  Future<void> showSyncError(String message) async {
    calls += 1;
    lastMessage = message;
  }

  @override
  Future<bool> ensurePermissionsForWorkout() async => true;

  @override
  Future<void> showRestOngoing(int seconds, {String? exerciseName}) async {}

  @override
  Future<void> cancelRestOngoing() async {}

  @override
  Future<void> showWorkoutOngoing({
    required DateTime startTime,
    String? currentExerciseName,
  }) async {}

  @override
  Future<void> cancelWorkoutOngoing() async {}

  @override
  Future<bool> isRestCompleteNotificationPending() async => true;

  @override
  Future<void> updateRestLiveActivity(
    int seconds, {
    String? exerciseName,
    bool isPaused = false,
  }) async {}

  @override
  Future<void> endRestLiveActivity() async {}

  @override
  Future<void> scheduleWeeklyCheckIn({
    required int weekday,
    required int hour,
    required int minute,
  }) async {}

  @override
  Future<void> cancelWeeklyCheckIn() async {}

  @override
  Future<bool> isWeeklyCheckInScheduled() async => false;

  @override
  Future<void> scheduleWeeklyTrainingRecap({
    required int weekday,
    required int hour,
    required int minute,
  }) async {}

  @override
  Future<void> cancelWeeklyTrainingRecap() async {}

  @override
  Future<bool> isWeeklyTrainingRecapScheduled() async => false;

  @override
  Future<void> navigateToProgress() async {}

  @override
  Future<void> navigateToNutritionStrategy() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('does not notify on sync failure', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    final tokens = _FakeTokenStorage();
    final repo = _FakeRepo();
    final api = _FailingApi();
    final notifier = _RecordingNotificationService();

    final svc = WorkoutSyncService(prefs, tokens, repo, api, notifier);
    await svc.syncNow();

    expect(notifier.calls, 0);
    expect(notifier.lastMessage, isNull);
  });
}
