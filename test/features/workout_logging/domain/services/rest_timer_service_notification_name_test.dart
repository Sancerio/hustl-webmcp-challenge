import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/services/notification_service.dart';
import 'package:hustl_app/features/workout_logging/domain/services/rest_timer_service.dart';

class _RecordingNotificationService implements NotificationService {
  @override
  Future<void> showAutoLoggedProposal({
    required String id,
    required bool isFood,
    required String body,
  }) async {}

  @override
  Future<void> handleAppLaunchNotification() async {}
  int scheduleCount = 0;
  int cancelCount = 0;
  int? lastSeconds;
  String? lastExerciseName;
  bool? lastIsNextSet;
  bool? lastShownIsNextSet;

  @override
  Future<void> cancelRestComplete() async {
    cancelCount++;
  }

  @override
  Future<void> cancelInactivityReminder() async {}

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
  }) async {
    scheduleCount++;
    lastSeconds = seconds;
    lastExerciseName = exerciseName;
    lastIsNextSet = isNextSet;
  }

  @override
  Future<void> scheduleInactivityReminder(int seconds) async {}

  @override
  Future<void> showRestComplete({
    String? exerciseName,
    bool isNextSet = false,
    bool skipForegroundBell = false,
  }) async {
    lastExerciseName = exerciseName;
    lastShownIsNextSet = isNextSet;
  }

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
  group('RestTimerService notification exercise name', () {
    test('uses next exercise for notification and current for UI', () async {
      DateTime now = DateTime(2024, 1, 1, 12, 0, 0);
      final notifier = _RecordingNotificationService();
      final service = RestTimerService(
        now: () => now,
        notificationService: notifier,
      );

      // Start a timer for current exercise 'Squat' and set next as 'Bench'
      service.startTimer(
        durationInSeconds: 10,
        exerciseName: 'Squat',
        notificationNextExerciseName: 'Bench',
        notificationIsNextSet: false,
      );

      expect(service.currentExerciseName, 'Squat');
      expect(notifier.scheduleCount, 1);
      expect(notifier.lastSeconds, 10);
      expect(notifier.lastExerciseName, 'Bench');
      expect(notifier.lastIsNextSet, isFalse);

      // Pause cancels; resume re-schedules with the same next exercise for notification
      service.pauseTimer();
      expect(notifier.cancelCount, 1);

      service.resumeTimer();
      expect(notifier.scheduleCount, 2);
      expect(notifier.lastExerciseName, 'Bench');
      expect(notifier.lastIsNextSet, isFalse);

      // Adjust via startTimer without passing notificationNextExerciseName keeps prior next exercise
      service.startTimer(
        durationInSeconds: 15,
        exerciseName: service.currentExerciseName,
      );
      expect(service.currentExerciseName, 'Squat');
      expect(notifier.scheduleCount, 3);
      expect(notifier.lastSeconds, 15);
      expect(notifier.lastExerciseName, 'Bench');
      expect(notifier.lastIsNextSet, isFalse);

      service.dispose();
    });

    test('explicit null next exercise clears a stale stored name', () async {
      DateTime now = DateTime(2024, 1, 1, 12, 0, 0);
      final notifier = _RecordingNotificationService();
      final service = RestTimerService(
        now: () => now,
        notificationService: notifier,
      );

      // First rest names "Bench" as the next exercise.
      service.startTimer(
        durationInSeconds: 10,
        exerciseName: 'Squat',
        notificationNextExerciseName: 'Bench',
        notificationIsNextSet: false,
        updateNotificationNextExercise: true,
      );
      expect(notifier.lastExerciseName, 'Bench');

      // Completing the last set leaves no next exercise: a fresh decision with
      // a null name must clear the stored "Bench" so the completion body falls
      // back to the generic copy instead of naming an already-finished exercise.
      service.startTimer(
        durationInSeconds: 12,
        exerciseName: 'Bench',
        notificationNextExerciseName: null,
        notificationIsNextSet: false,
        updateNotificationNextExercise: true,
      );

      expect(notifier.scheduleCount, 2);
      expect(notifier.lastExerciseName, isNull);
      expect(notifier.lastIsNextSet, isFalse);

      service.dispose();
    });
  });
}
