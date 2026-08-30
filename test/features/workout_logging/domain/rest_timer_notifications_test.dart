import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/services/notification_service.dart';
import 'package:hustl_app/features/workout_logging/domain/services/rest_timer_service.dart';

class _SpyNotificationService implements NotificationService {

  @override
  Future<void> showAutoLoggedProposal({required String id, required bool isFood, required String body}) async {}


  @override
  Future<void> handleAppLaunchNotification() async {}
  int scheduled = 0;
  int canceled = 0;
  List<int> scheduledSeconds = [];
  int shown = 0;
  List<String> callOrder = [];

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
  }) async {
    shown++;
    callOrder.add('show');
  }

  @override
  Future<void> scheduleRestComplete(
    int seconds, {
    String? exerciseName,
    bool isNextSet = false,
  }) async {
    scheduled++;
    scheduledSeconds.add(seconds);
  }

  @override
  Future<void> cancelRestComplete() async {
    canceled++;
    callOrder.add('cancel');
  }

  @override
  Future<void> scheduleInactivityReminder(int seconds) async {}

  @override
  Future<void> cancelInactivityReminder() async {}

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
  test(
    'schedules on start, cancels on pause/reset/stop, reschedules on resume',
    () async {
      final spy = _SpyNotificationService();
      final svc = RestTimerService(notificationService: spy);

      // Start
      svc.startTimer(durationInSeconds: 90);
      expect(svc.status, TimerStatus.running);
      expect(spy.scheduled, 1);
      expect(spy.scheduledSeconds.last, 90);
      expect(spy.canceled, 0);

      // Pause cancels
      svc.pauseTimer();
      expect(svc.status, TimerStatus.paused);
      expect(spy.canceled, 1);

      // Resume reschedules with remaining seconds (<= original)
      svc.resumeTimer();
      expect(svc.status, TimerStatus.running);
      expect(spy.scheduled, 2);
      expect(spy.scheduledSeconds.last, lessThanOrEqualTo(90));

      // Reset cancels and idles
      svc.resetTimer(durationInSeconds: 60);
      expect(svc.status, TimerStatus.idle);
      expect(spy.canceled, 2);

      // Stop cancels and idles
      svc.startTimer(durationInSeconds: 30);
      expect(spy.scheduled, 3);
      svc.stopTimer();
      expect(svc.status, TimerStatus.idle);
      expect(spy.canceled, 3);
    },
  );

  test(
    'shows completion notification after cancelling pending schedule',
    () async {
      DateTime now = DateTime(2024, 1, 1, 12, 0, 0);
      final spy = _SpyNotificationService();
      final svc = RestTimerService(now: () => now, notificationService: spy);

      svc.startTimer(durationInSeconds: 1, exerciseName: 'Bench');

      // Ignore initial cancel inside scheduleRestComplete.
      spy.callOrder.clear();

      now = now.add(const Duration(seconds: 1));
      svc.refreshNow();
      await Future<void>.delayed(Duration.zero);

      expect(svc.status, TimerStatus.completed);
      expect(spy.callOrder, ['cancel', 'show']);
      expect(spy.shown, 1);
    },
  );
}
