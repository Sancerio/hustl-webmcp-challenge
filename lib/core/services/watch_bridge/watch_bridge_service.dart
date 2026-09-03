enum WatchCancelReason { discarded, completed }

class WatchBridgeService {
  bool get isEnabled => false;
  void schedulePublish() {}
  Future<void> requestStartRecording({required String sessionId}) async {}
  Future<void> requestStopRecording({required String sessionId}) async {}
  void cancelWorkout({
    required String sessionId,
    String? hkWorkoutUuid,
    WatchCancelReason reason = WatchCancelReason.discarded,
  }) {}
}
