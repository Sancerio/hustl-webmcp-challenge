import 'dart:async';

import 'workout_record.dart';

enum WorkoutWritePlatform { iosHealthKit, androidHealthConnect, unsupported }

enum WorkoutPermissionScope { workouts, energy, distance, heartRate }

class WorkoutWriteCapability {
  const WorkoutWriteCapability({
    required this.platform,
    required this.supported,
    this.grantedScopes = const {},
    this.requiresAppSetup = false,
  });

  final WorkoutWritePlatform platform;
  final bool supported;
  final Set<WorkoutPermissionScope> grantedScopes;
  final bool requiresAppSetup;

  bool get hasWorkoutPermission =>
      grantedScopes.contains(WorkoutPermissionScope.workouts);
}

enum WorkoutWriteStatus { pending, writing, written, failed }

enum WorkoutWriteEventType {
  queued,
  started,
  succeeded,
  failed,
  permissionsUpdated,
}

class WorkoutWriteEvent {
  const WorkoutWriteEvent(
    this.type,
    this.externalId, {
    this.errorCode,
    this.message,
  });

  final WorkoutWriteEventType type;
  final String externalId;
  final String? errorCode;
  final String? message;
}

class WorkoutWriteResult {
  const WorkoutWriteResult.success({this.message})
    : success = true,
      errorCode = null,
      retryable = false;

  const WorkoutWriteResult.failure({
    required this.errorCode,
    this.retryable = false,
    this.message,
  }) : success = false;

  final bool success;
  final String? errorCode;
  final bool retryable;
  final String? message;
}

abstract class WorkoutWriteService {
  Stream<WorkoutWriteEvent> get events;

  Future<WorkoutWriteCapability> getCapabilities();

  Future<bool> requestPermissions(Set<WorkoutPermissionScope> scopes);

  Future<WorkoutWriteResult> upsertWorkout(WorkoutRecord record);

  Future<bool> deleteWorkout(String externalId);

  Future<bool> deleteWorkoutByRecord(WorkoutRecord record, {String? keepUuid});
}
