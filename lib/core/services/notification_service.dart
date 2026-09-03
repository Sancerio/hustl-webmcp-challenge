class NotificationService {
  const NotificationService();

  Future<void> cancelRestComplete() async {}
  Future<void> cancelRestOngoing() async {}
  void cancelInactivityReminder() {}
  void scheduleInactivityReminder(int seconds) {}
  Future<void> showRestOngoing(int seconds, {String? exerciseName}) async {}
  Future<bool> ensurePermissionsForWorkout() async => false;
  Future<void> cancelWorkoutOngoing() async {}
  Future<void> showWorkoutOngoing({
    required DateTime startTime,
    String? currentExerciseName,
  }) async {}
  Future<void> updateRestLiveActivity(
    int seconds, {
    String? exerciseName,
    bool isPaused = false,
  }) async {}
  Future<void> scheduleRestComplete(
    int seconds, {
    String? exerciseName,
    String? nextExerciseName,
    bool isNextSet = false,
  }) async {}
  Future<void> endRestLiveActivity() async {}
  Future<bool> isRestCompleteNotificationPending() async => false;
  Future<void> showRestComplete({
    String? exerciseName,
    bool isNextSet = false,
    bool skipForegroundBell = false,
  }) async {}
}
