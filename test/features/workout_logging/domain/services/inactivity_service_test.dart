import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/features/workout_logging/domain/services/inactivity_service.dart';
import 'package:hustl_app/core/services/notification_service.dart';
import 'package:hustl_app/core/services/preferences_service.dart';

class _MockNotificationService implements NotificationService {

  @override
  Future<void> showAutoLoggedProposal({required String id, required bool isFood, required String body}) async {}


  @override
  Future<void> handleAppLaunchNotification() async {}
  int scheduleCount = 0;
  int cancelCount = 0;
  int? lastSeconds;

  @override
  Future<void> cancelInactivityReminder() async {
    cancelCount++;
  }

  @override
  Future<void> scheduleInactivityReminder(int seconds) async {
    scheduleCount++;
    lastSeconds = seconds;
  }

  // Unused methods
  @override
  Future<void> cancelRestComplete() async {}

  @override
  Future<void> init() async {}

  @override
  Future<void> navigateToActiveWorkout() async {}

  @override
  Future<void> navigateToProposal(String? id) async {}

  @override
  Future<void> scheduleRestComplete(
    int seconds, {
    String? exerciseName,
    bool isNextSet = false,
  }) async {}

  @override
  Future<void> showRestComplete({
    String? exerciseName,
    bool isNextSet = false,
    bool skipForegroundBell = false,
  }) async {}

  @override
  Future<void> showSyncError(String message) async {}

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
  test('schedules reminder after activity and cancels on stop', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    await prefs.setInactivityReminderMinutes(7);
    final mock = _MockNotificationService();
    final service = InactivityService(
      notificationService: mock,
      preferencesService: prefs,
    );

    service.start();
    expect(mock.scheduleCount, 1);
    expect(mock.lastSeconds, 420);

    service.recordActivity();
    expect(mock.scheduleCount, 2);
    expect(mock.lastSeconds, 420);

    await prefs.setInactivityReminderMinutes(10);

    service.recordActivity();
    expect(mock.scheduleCount, 3);
    expect(mock.lastSeconds, 600);

    service.stop();
    expect(mock.cancelCount, greaterThan(0));
  });
}
