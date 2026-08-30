import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/workout_logging/domain/services/rest_timer_service.dart';
import 'package:hustl_app/core/services/notification_service.dart';

class _MockNotificationService implements NotificationService {

  @override
  Future<void> showAutoLoggedProposal({required String id, required bool isFood, required String body}) async {}


  @override
  Future<void> handleAppLaunchNotification() async {}
  int scheduleCount = 0;
  int cancelCount = 0;
  int? lastSeconds;

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
  }

  @override
  Future<void> scheduleInactivityReminder(int seconds) async {}

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
  group('RestTimerService clock-based behavior', () {
    test(
      'counts down based on target time even when ticks are delayed',
      () async {
        DateTime fakeNow = DateTime(2024, 1, 1, 12, 0, 0);
        final service = RestTimerService(
          now: () => fakeNow,
          notificationService: _MockNotificationService(),
        );

        // Start a short timer (5s)
        service.startTimer(durationInSeconds: 5, exerciseName: 'Bench');
        expect(service.status, TimerStatus.running);
        expect(service.remainingSeconds, 5);

        // Simulate background: advance wall clock by 6 seconds without any periodic ticks
        fakeNow = fakeNow.add(const Duration(seconds: 6));

        // Force a resync (what would happen on next tick or on resume)
        service.refreshNow();

        expect(service.remainingSeconds, 0);
        expect(service.status, TimerStatus.completed);

        service.dispose();
      },
    );

    test(
      'pause freezes remaining time regardless of wall clock changes',
      () async {
        DateTime fakeNow = DateTime(2024, 1, 1, 12, 0, 0);
        final service = RestTimerService(
          now: () => fakeNow,
          notificationService: _MockNotificationService(),
        );

        // Start a 10s timer
        service.startTimer(durationInSeconds: 10, exerciseName: 'Bench');
        expect(service.status, TimerStatus.running);
        expect(service.remainingSeconds, 10);

        // Advance 3 seconds and resync
        fakeNow = fakeNow.add(const Duration(seconds: 3));
        service.refreshNow();
        expect(
          service.remainingSeconds,
          inInclusiveRange(7, 8),
        ); // allow up to 1s variance

        // Pause and then simulate a long background period (5 minutes)
        service.pauseTimer();
        expect(service.status, TimerStatus.paused);
        final pausedRemaining = service.remainingSeconds;

        fakeNow = fakeNow.add(const Duration(minutes: 5));
        service.refreshNow();

        // Remaining should be unchanged while paused
        expect(service.remainingSeconds, pausedRemaining);
        expect(service.status, TimerStatus.paused);

        // Resume and ensure it resumes from pausedRemaining
        service.resumeTimer();
        expect(service.status, TimerStatus.running);
        expect(service.remainingSeconds, pausedRemaining);

        service.dispose();
      },
    );

    test('schedules notification on start and cancels on stop', () async {
      DateTime now = DateTime(2024, 1, 1, 12, 0, 0);
      final mock = _MockNotificationService();
      final service = RestTimerService(
        now: () => now,
        notificationService: mock,
      );

      service.startTimer(durationInSeconds: 5, exerciseName: 'Bench');
      expect(mock.scheduleCount, 1);
      expect(mock.lastSeconds, 5);

      service.pauseTimer();
      expect(mock.cancelCount, 1);

      service.resumeTimer();
      expect(mock.scheduleCount, 2);

      service.stopTimer();
      expect(mock.cancelCount, 2);
    });
  });
}
