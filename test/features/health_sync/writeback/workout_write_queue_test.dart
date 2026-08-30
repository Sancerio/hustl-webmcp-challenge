import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/health_sync/data/writeback/workout_write_queue.dart';
import 'package:hustl_app/features/health_sync/domain/writeback/workout_record.dart';
import 'package:hustl_app/features/health_sync/domain/writeback/workout_write_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeWorkoutWriteService implements WorkoutWriteService {
  FakeWorkoutWriteService({WorkoutWriteCapability? capability})
    : _capability =
          capability ??
          const WorkoutWriteCapability(
            platform: WorkoutWritePlatform.iosHealthKit,
            supported: true,
            grantedScopes: {WorkoutPermissionScope.workouts},
          );

  WorkoutWriteCapability _capability;
  final StreamController<WorkoutWriteEvent> _events =
      StreamController<WorkoutWriteEvent>.broadcast();
  FutureOr<WorkoutWriteResult> Function(WorkoutRecord record)? onUpsert;
  FutureOr<bool> Function(String externalId)? onDelete;
  FutureOr<bool> Function(WorkoutRecord record, String? keepUuid)?
  onDeleteByRecord;
  int upsertCalls = 0;
  int deleteCalls = 0;
  int deleteByRecordCalls = 0;
  String? lastDeleteByRecordKeepUuid;

  @override
  Stream<WorkoutWriteEvent> get events => _events.stream;

  @override
  Future<WorkoutWriteCapability> getCapabilities() async => _capability;

  @override
  Future<bool> requestPermissions(Set<WorkoutPermissionScope> scopes) async =>
      true;

  @override
  Future<WorkoutWriteResult> upsertWorkout(WorkoutRecord record) async {
    upsertCalls += 1;
    final handler = onUpsert;
    if (handler != null) {
      return await handler(record);
    }
    return const WorkoutWriteResult.success();
  }

  @override
  Future<bool> deleteWorkout(String externalId) async {
    deleteCalls += 1;
    final handler = onDelete;
    if (handler != null) {
      return await handler(externalId);
    }
    return true;
  }

  @override
  Future<bool> deleteWorkoutByRecord(
    WorkoutRecord record, {
    String? keepUuid,
  }) async {
    deleteByRecordCalls += 1;
    lastDeleteByRecordKeepUuid = keepUuid;
    final handler = onDeleteByRecord;
    if (handler != null) {
      return await handler(record, keepUuid);
    }
    return true;
  }

  set capability(WorkoutWriteCapability capability) {
    _capability = capability;
  }
}

Future<void> pumpQueue() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    await prefs.setRawString('workout_write_queue_v1', null);
  });

  WorkoutRecord buildRecord({String id = 'session-1'}) {
    return WorkoutRecord(
      sessionId: id,
      activityType: WorkoutActivityType.strength,
      startedAt: DateTime.utc(2024, 1, 1, 12),
      endedAt: DateTime.utc(2024, 1, 1, 13),
      duration: 3600,
    );
  }

  group('WorkoutWriteQueue', () {
    late FakeWorkoutWriteService service;
    late PreferencesService prefs;
    late DateTime now;

    setUp(() async {
      service = FakeWorkoutWriteService();
      prefs = PreferencesService();
      now = DateTime.utc(2024, 1, 1, 12);
    });

    WorkoutWriteQueue buildQueue({FakeWorkoutWriteService? overrideService}) {
      final svc = overrideService ?? service;
      return WorkoutWriteQueue(prefs, svc, clock: () => now, random: Random(1));
    }

    test('writes queued workout when service succeeds', () async {
      final queue = buildQueue();
      final record = buildRecord();

      await queue.enqueue(record);
      await pumpQueue();

      expect(queue.items, hasLength(1));
      final item = queue.items.first;
      expect(item.status, WorkoutWriteStatus.written);
      expect(service.upsertCalls, 1);
    });

    test('marks item failed with retry when write fails', () async {
      service.onUpsert = (_) => const WorkoutWriteResult.failure(
        errorCode: 'timeout',
        retryable: true,
      );
      final queue = buildQueue();
      final record = buildRecord();

      await queue.enqueue(record);
      await pumpQueue();

      final item = queue.items.first;
      expect(item.status, WorkoutWriteStatus.failed);
      expect(item.nextRetryAt, isNotNull);
      expect(item.retryCount, 1);
    });

    test('stops reprocessing non-retryable failures', () async {
      service.onUpsert = (_) => const WorkoutWriteResult.failure(
        errorCode: 'permission_denied',
        retryable: false,
      );
      final queue = buildQueue();
      final record = buildRecord();

      await queue.enqueue(record);
      await pumpQueue();

      expect(service.upsertCalls, 1);
      final item = queue.items.first;
      expect(item.status, WorkoutWriteStatus.failed);
      expect(item.nextRetryAt, isNull);

      await pumpQueue();
      expect(service.upsertCalls, 1);
    });

    test('skips re-write when payload hash unchanged', () async {
      final queue = buildQueue();
      final record = buildRecord();

      await queue.enqueue(record);
      await pumpQueue();
      expect(service.upsertCalls, 1);

      await queue.enqueue(record);
      await pumpQueue();
      expect(service.upsertCalls, 1);
    });

    test('hydrates pending items when capability becomes available', () async {
      final blockedService = FakeWorkoutWriteService(
        capability: const WorkoutWriteCapability(
          platform: WorkoutWritePlatform.iosHealthKit,
          supported: false,
        ),
      );

      final queue = buildQueue(overrideService: blockedService);
      final record = buildRecord();

      await queue.enqueue(record);
      await pumpQueue();
      expect(blockedService.upsertCalls, 0);

      final resumeService = FakeWorkoutWriteService(
        capability: const WorkoutWriteCapability(
          platform: WorkoutWritePlatform.iosHealthKit,
          supported: true,
          grantedScopes: {WorkoutPermissionScope.workouts},
        ),
      );

      final resumedQueue = buildQueue(overrideService: resumeService);
      await resumedQueue.refreshCapability();
      await resumedQueue.hydrate();
      await pumpQueue();

      expect(resumeService.upsertCalls, 1);
      final item = resumedQueue.items.first;
      expect(item.status, WorkoutWriteStatus.written);
    });

    test('removing workout during write prevents stale success', () async {
      final completer = Completer<WorkoutWriteResult>();
      service.onUpsert = (_) {
        return completer.future;
      };

      final queue = buildQueue();
      final record = buildRecord();

      await queue.enqueue(record);
      await pumpQueue();
      expect(service.upsertCalls, 1);

      await queue.remove(record.externalId, deleteRemote: false);
      completer.complete(const WorkoutWriteResult.success());
      await pumpQueue();

      expect(
        queue.items.any((item) => item.externalId == record.externalId),
        isFalse,
      );
    });

    test(
      'successful remote delete clears queue item and forwards keep UUID',
      () async {
        service.onDeleteByRecord = (_, __) async => true;
        final queue = buildQueue();
        final record = buildRecord();

        await queue.enqueue(record);
        await pumpQueue();
        expect(service.upsertCalls, 1);

        await queue.remove(
          record.externalId,
          deleteRemote: true,
          keepUuid: 'watch-uuid',
        );
        await pumpQueue();

        expect(service.deleteByRecordCalls, 1);
        expect(service.lastDeleteByRecordKeepUuid, 'watch-uuid');
        expect(queue.items, isEmpty);
      },
    );

    test(
      'missing queue item with keep UUID skips delete when mapping points to keep UUID',
      () async {
        final queue = buildQueue();
        await prefs.upsertWorkoutWritebackMapping(
          'hustl:missing-session',
          'watch-uuid',
        );

        await queue.remove(
          'hustl:missing-session',
          deleteRemote: true,
          keepUuid: 'watch-uuid',
        );
        await pumpQueue();

        expect(service.deleteCalls, 0);
        expect(service.deleteByRecordCalls, 0);
        final mappings = await prefs.getWorkoutWritebackMappings();
        expect(mappings.containsKey('hustl:missing-session'), isFalse);
      },
    );

    test(
      'missing queue item with keep UUID still deletes when mapping differs',
      () async {
        final queue = buildQueue();
        await prefs.upsertWorkoutWritebackMapping(
          'hustl:missing-session',
          'uuid-phone',
        );

        await queue.remove(
          'hustl:missing-session',
          deleteRemote: true,
          keepUuid: 'watch-uuid',
        );
        await pumpQueue();

        expect(service.deleteCalls, 1);
        expect(service.deleteByRecordCalls, 0);
      },
    );

    test(
      'failed remote delete keeps item pending deletion for retry',
      () async {
        service.onDeleteByRecord = (_, __) async => false;
        final queue = buildQueue();
        final record = buildRecord();

        await queue.enqueue(record);
        await pumpQueue();

        await queue.remove(record.externalId, deleteRemote: true);
        await pumpQueue();

        expect(service.deleteByRecordCalls, greaterThanOrEqualTo(1));
        expect(service.deleteCalls, 0);
        final remaining = queue.items.single;
        expect(remaining.pendingDelete, isTrue);
        expect(remaining.status, WorkoutWriteStatus.failed);
      },
    );

    test(
      're-removing with null keepUuid clears previously persisted keep UUID',
      () async {
        var deleteAttempts = 0;
        final seenKeepUuids = <String?>[];
        service.onDeleteByRecord = (_, keepUuid) async {
          deleteAttempts += 1;
          seenKeepUuids.add(keepUuid);
          return deleteAttempts > 1;
        };

        final queue = buildQueue();
        final record = buildRecord(id: 'session-keepuuid-clear');

        await queue.enqueue(record);
        await pumpQueue();

        await queue.remove(
          record.externalId,
          deleteRemote: true,
          keepUuid: 'watch-uuid',
        );
        await pumpQueue();
        expect(seenKeepUuids, ['watch-uuid']);

        await queue.remove(
          record.externalId,
          deleteRemote: true,
          keepUuid: null,
        );
        await pumpQueue();

        expect(seenKeepUuids, ['watch-uuid', null]);
        expect(queue.items, isEmpty);
      },
    );
  });
}
