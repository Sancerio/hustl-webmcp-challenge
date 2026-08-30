import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/health_sync/data/writeback/workout_write_queue.dart';
import 'package:hustl_app/features/health_sync/data/writeback/workout_writeback_coordinator.dart';
import 'package:hustl_app/features/health_sync/domain/writeback/workout_record.dart';
import 'package:hustl_app/features/health_sync/domain/writeback/workout_write_service.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockQueue extends Mock implements WorkoutWriteQueue {}

class _MockService extends Mock implements WorkoutWriteService {}

class _MockPreferences extends Mock implements PreferencesService {}

class _MockWorkoutRepository extends Mock implements WorkoutRepository {}

WorkoutRecord _record(String id) {
  return WorkoutRecord(
    sessionId: id,
    activityType: WorkoutActivityType.strength,
    startedAt: DateTime.utc(2025, 1, 1, 10),
    endedAt: DateTime.utc(2025, 1, 1, 11),
    duration: const Duration(hours: 1).inSeconds,
  );
}

WorkoutWriteQueueItem _writtenItem(String id) {
  final record = _record(id);
  return WorkoutWriteQueueItem(
    externalId: record.externalId,
    record: record,
    payloadHash: record.payloadHash(),
    status: WorkoutWriteStatus.written,
    platform: WorkoutWritePlatform.iosHealthKit,
    updatedAt: DateTime.utc(2025, 1, 1, 12),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_record('fallback'));
  });

  group('WorkoutWritebackCoordinator watch reconciliation', () {
    late _MockQueue queue;
    late _MockService service;
    late _MockPreferences preferences;
    late _MockWorkoutRepository workoutRepository;
    late WorkoutWritebackCoordinator coordinator;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      queue = _MockQueue();
      service = _MockService();
      preferences = _MockPreferences();
      workoutRepository = _MockWorkoutRepository();

      when(
        () => queue.remove(
          any(),
          deleteRemote: any(named: 'deleteRemote'),
          keepUuid: any(named: 'keepUuid'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => service.deleteWorkoutByRecord(
          any(),
          keepUuid: any(named: 'keepUuid'),
        ),
      ).thenAnswer((_) async => true);
      when(() => queue.enqueue(any())).thenAnswer((_) async {});
      when(
        () => preferences.getWatchCompanionEnabled(),
      ).thenAnswer((_) async => true);
      when(
        () => preferences.getWatchCompanionDebugOverride(),
      ).thenAnswer((_) async => null);

      coordinator = WorkoutWritebackCoordinator(
        queue: queue,
        service: service,
        preferences: preferences,
        workoutRepository: workoutRepository,
      );
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'cancelQueuedWriteback clears local queue without remote delete',
      () async {
        await coordinator.cancelQueuedWriteback('session-1');

        verify(
          () => queue.remove(
            'hustl:session-1',
            deleteRemote: false,
            keepUuid: null,
          ),
        ).called(1);
        verifyNever(
          () => service.deleteWorkoutByRecord(
            any(),
            keepUuid: any(named: 'keepUuid'),
          ),
        );
      },
    );

    test(
      'handleWatchCapturedWorkout deletes phone duplicate by record when mapping is missing',
      () async {
        final item = _writtenItem('session-2');
        when(() => queue.items).thenReturn([item]);
        when(
          () => preferences.getWorkoutWritebackMappings(),
        ).thenAnswer((_) async => const <String, String>{});

        await coordinator.handleWatchCapturedWorkout(
          sessionId: 'session-2',
          watchWorkoutUuid: 'watch-uuid',
        );

        verify(
          () => service.deleteWorkoutByRecord(
            item.record,
            keepUuid: 'watch-uuid',
          ),
        ).called(1);
        verify(
          () => queue.remove(
            'hustl:session-2',
            deleteRemote: false,
            keepUuid: null,
          ),
        ).called(1);
      },
    );

    test(
      'handleWatchCapturedWorkout keeps queue retry state when record delete fails and mapping is missing',
      () async {
        final item = _writtenItem('session-2b');
        when(() => queue.items).thenReturn([item]);
        when(
          () => preferences.getWorkoutWritebackMappings(),
        ).thenAnswer((_) async => const <String, String>{});
        when(
          () => service.deleteWorkoutByRecord(
            item.record,
            keepUuid: 'watch-uuid',
          ),
        ).thenAnswer((_) async => false);

        await coordinator.handleWatchCapturedWorkout(
          sessionId: 'session-2b',
          watchWorkoutUuid: 'watch-uuid',
        );

        verify(
          () => service.deleteWorkoutByRecord(
            item.record,
            keepUuid: 'watch-uuid',
          ),
        ).called(1);
        verify(
          () => queue.remove(
            'hustl:session-2b',
            deleteRemote: true,
            keepUuid: 'watch-uuid',
          ),
        ).called(1);
        verifyNever(
          () => queue.remove(
            'hustl:session-2b',
            deleteRemote: false,
            keepUuid: null,
          ),
        );
      },
    );

    test(
      'handleWatchCapturedWorkout keeps watch workout when mapping already points to watch UUID',
      () async {
        final item = _writtenItem('session-3');
        when(() => queue.items).thenReturn([item]);
        when(() => preferences.getWorkoutWritebackMappings()).thenAnswer(
          (_) async => const <String, String>{'hustl:session-3': 'watch-uuid'},
        );
        when(
          () => preferences.removeWorkoutWritebackMapping('hustl:session-3'),
        ).thenAnswer((_) async {});

        await coordinator.handleWatchCapturedWorkout(
          sessionId: 'session-3',
          watchWorkoutUuid: 'watch-uuid',
        );

        verify(
          () => preferences.removeWorkoutWritebackMapping('hustl:session-3'),
        ).called(1);
        verify(
          () => queue.remove(
            'hustl:session-3',
            deleteRemote: false,
            keepUuid: null,
          ),
        ).called(1);
        verifyNever(
          () => service.deleteWorkoutByRecord(
            any(),
            keepUuid: any(named: 'keepUuid'),
          ),
        );
      },
    );

    test(
      'handleWatchCapturedWorkout removes remote phone write when mapping points to non-watch UUID',
      () async {
        final item = _writtenItem('session-4');
        when(() => queue.items).thenReturn([item]);
        when(() => preferences.getWorkoutWritebackMappings()).thenAnswer(
          (_) async => const <String, String>{'hustl:session-4': 'phone-uuid'},
        );

        await coordinator.handleWatchCapturedWorkout(
          sessionId: 'session-4',
          watchWorkoutUuid: 'watch-uuid',
        );

        verify(
          () => queue.remove(
            'hustl:session-4',
            deleteRemote: true,
            keepUuid: 'watch-uuid',
          ),
        ).called(1);
      },
    );

    test(
      'handleWorkoutCompleted does not enqueue phone writeback while watch capture is pending',
      () async {
        final session = WorkoutSession(
          id: 'session-pending',
          name: 'Pending',
          startTime: DateTime.utc(2025, 1, 1, 10),
          endTime: DateTime.utc(2025, 1, 1, 11),
          exercises: const [],
          isCompleted: true,
          watchCapturePending: true,
          watchCapturePendingAt: DateTime.utc(2025, 1, 1, 11),
        );

        coordinator.state.value = const WorkoutWritebackState(
          capability: WorkoutWriteCapability(
            platform: WorkoutWritePlatform.iosHealthKit,
            supported: true,
            grantedScopes: {WorkoutPermissionScope.workouts},
          ),
          enabled: true,
          permissionsGranted: true,
          queueLength: 0,
        );

        await coordinator.handleWorkoutCompleted(session);

        verifyNever(() => queue.enqueue(any()));
      },
    );
  });
}
