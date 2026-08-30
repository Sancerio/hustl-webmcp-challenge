import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hustl_app/core/services/notification_service.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/watch_bridge/watch_bridge_command.dart';
import 'package:hustl_app/core/services/watch_bridge/watch_bridge_handler.dart';
import 'package:hustl_app/core/services/watch_bridge/watch_bridge_health.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/exercise_library/domain/repositories/exercise_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/services/workout_events_service.dart';
import 'package:hustl_app/features/workout_logging/domain/services/rest_timer_service.dart';
import 'package:hustl_app/features/health_sync/data/writeback/workout_writeback_coordinator.dart';

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockRestTimerService extends Mock implements RestTimerService {}

class MockNotificationService extends Mock implements NotificationService {}

class MockWorkoutWritebackCoordinator extends Mock
    implements WorkoutWritebackCoordinator {}

class MockPreferencesService extends Mock implements PreferencesService {}

/// In-memory exercise library for the named-add + catalog tests.
class FakeExerciseRepository extends ExerciseRepository {
  FakeExerciseRepository(this.exercises);

  final List<Exercise> exercises;

  @override
  Future<List<Exercise>> getAllExercises() async => exercises;

  @override
  Future<List<Exercise>> getExercisesByMuscle(String muscle) async {
    final lower = muscle.toLowerCase();
    return exercises
        .where((e) => e.muscles.any((m) => m.toLowerCase().contains(lower)))
        .toList();
  }

  @override
  Future<List<Exercise>> searchExercises(String query) async {
    if (query.isEmpty) return exercises;
    final lower = query.toLowerCase();
    return exercises
        .where((e) => e.name.toLowerCase().contains(lower))
        .toList();
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      WorkoutSession(
        id: 'fallback',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [],
      ),
    );
    registerFallbackValue(
      const WorkoutSet(id: 'fallback-set', weight: 0, reps: 0),
    );
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  test('ignores duplicate watch commands', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    when(() => repo.getLatestActiveSession()).thenAnswer(
      (_) async => WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [],
      ),
    );
    when(() => restTimer.stopTimer()).thenReturn(null);

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    const command = WatchCommand(
      id: 'cmd-1',
      type: WatchCommandType.restStop,
      sessionId: 's1',
    );

    await handler.handleCommand(command);
    await handler.handleCommand(command);

    verify(() => restTimer.stopTimer()).called(1);
  });

  test('ignores watch command ids persisted from a prior app run', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();
    final preferences = MockPreferencesService();

    when(() => repo.getLatestActiveSession()).thenAnswer(
      (_) async => WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [],
      ),
    );
    when(
      () => preferences.getRawString('watch_bridge_recent_command_ids_v1'),
    ).thenAnswer((_) async => '{"s1":["cmd-replayed"]}');

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
      preferences: preferences,
    );

    const command = WatchCommand(
      id: 'cmd-replayed',
      type: WatchCommandType.restStop,
      sessionId: 's1',
    );

    await handler.handleCommand(command);

    verifyNever(() => restTimer.stopTimer());
  });

  test(
    'persists newly processed watch command ids for restart dedupe',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();
      final preferences = MockPreferencesService();

      when(() => repo.getLatestActiveSession()).thenAnswer(
        (_) async => WorkoutSession(
          id: 's1',
          name: 'Workout',
          startTime: DateTime(2024),
          exercises: const [],
        ),
      );
      when(
        () => preferences.getRawString('watch_bridge_recent_command_ids_v1'),
      ).thenAnswer((_) async => null);
      when(
        () => preferences.setRawString(
          'watch_bridge_recent_command_ids_v1',
          any(),
        ),
      ).thenAnswer((_) async {});
      when(() => restTimer.stopTimer()).thenReturn(null);

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
        preferences: preferences,
      );

      const command = WatchCommand(
        id: 'cmd-new',
        type: WatchCommandType.restStop,
        sessionId: 's1',
      );

      await handler.handleCommand(command);

      verify(() => restTimer.stopTimer()).called(1);
      final persisted =
          verify(
                () => preferences.setRawString(
                  'watch_bridge_recent_command_ids_v1',
                  captureAny(),
                ),
              ).captured.single
              as String;
      expect(persisted, contains('cmd-new'));
    },
  );

  test('continues processing after a command handler exception', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    var calls = 0;
    when(() => repo.getLatestActiveSession()).thenAnswer((_) async {
      if (calls++ == 0) {
        throw Exception('boom');
      }
      return WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [],
      );
    });
    when(() => restTimer.stopTimer()).thenReturn(null);

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    const command1 = WatchCommand(
      id: 'cmd-err',
      type: WatchCommandType.restStop,
      sessionId: 's1',
    );
    const command2 = WatchCommand(
      id: 'cmd-ok',
      type: WatchCommandType.restStop,
      sessionId: 's1',
    );

    await handler.handleCommand(command1);
    await handler.handleCommand(command2);

    verify(() => restTimer.stopTimer()).called(1);
  });

  test(
    'start workout command enables watch recording request by default',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();
      final preferences = MockPreferencesService();

      when(() => repo.getLatestActiveSession()).thenAnswer((_) async => null);
      when(() => repo.createWorkoutSession(any())).thenAnswer((
        invocation,
      ) async {
        return invocation.positionalArguments.first as WorkoutSession;
      });
      when(
        () => notifications.showWorkoutOngoing(
          startTime: any(named: 'startTime'),
          currentExerciseName: any(named: 'currentExerciseName'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => preferences.getWatchHeartRateRecordingEnabled(),
      ).thenAnswer((_) async => true);

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
        preferences: preferences,
      );

      const command = WatchCommand(
        id: 'start-1',
        type: WatchCommandType.startWorkout,
      );

      await handler.handleCommand(command);

      final created =
          verify(() => repo.createWorkoutSession(captureAny())).captured.single
              as WorkoutSession;
      expect(created.watchRecordingRequested, isTrue);
    },
  );

  test(
    'start workout command respects disabled watch recording preference',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();
      final preferences = MockPreferencesService();

      when(() => repo.getLatestActiveSession()).thenAnswer((_) async => null);
      when(() => repo.createWorkoutSession(any())).thenAnswer((
        invocation,
      ) async {
        return invocation.positionalArguments.first as WorkoutSession;
      });
      when(
        () => notifications.showWorkoutOngoing(
          startTime: any(named: 'startTime'),
          currentExerciseName: any(named: 'currentExerciseName'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => preferences.getWatchHeartRateRecordingEnabled(),
      ).thenAnswer((_) async => false);

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
        preferences: preferences,
      );

      const command = WatchCommand(
        id: 'start-2',
        type: WatchCommandType.startWorkout,
      );

      await handler.handleCommand(command);

      final created =
          verify(() => repo.createWorkoutSession(captureAny())).captured.single
              as WorkoutSession;
      expect(created.watchRecordingRequested, isFalse);
    },
  );

  test('stores health summary and marks capturedOnWatch', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: const [],
    );

    when(() => repo.getWorkoutSession('s1')).thenAnswer((_) async => session);
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer(
      (invocation) async =>
          invocation.positionalArguments.first as WorkoutSession,
    );

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    const summary = WatchHealthSummary(
      id: 'health-1',
      sessionId: 's1',
      durationSeconds: 1800,
      averageHeartRateBpm: 128,
      maxHeartRateBpm: 162,
      activeEnergyKilocalories: 240.5,
      hkWorkoutUuid: 'uuid-1',
    );

    await handler.handleHealthSummary(summary);
    await handler.handleHealthSummary(summary);

    final captured =
        verify(
              () => repo.updateWorkoutSession(captureAny(), markDirty: false),
            ).captured.single
            as WorkoutSession;
    expect(captured.capturedOnWatch, isTrue);
    expect(captured.activeEnergyKilocalories, 240.5);
    expect(captured.averageHeartRateBpm, 128);
    expect(captured.maxHeartRateBpm, 162);
    expect(captured.watchDurationSeconds, 1800);
    expect(captured.watchWorkoutUuid, 'uuid-1');
  });

  test(
    'health summary marks completed clean workout dirty when watch fields change',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        endTime: DateTime(2024, 1, 1, 0, 30),
        exercises: const [],
        dirty: false,
      );

      when(() => repo.getWorkoutSession('s1')).thenAnswer((_) async => session);
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments.first as WorkoutSession,
      );

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      const summary = WatchHealthSummary(
        id: 'health-1b',
        sessionId: 's1',
        averageHeartRateBpm: 135,
        maxHeartRateBpm: 172,
        recordingStartMs: 10,
        recordingEndMs: 20,
      );

      await handler.handleHealthSummary(summary);

      verify(() => repo.updateWorkoutSession(any(), markDirty: true)).called(1);
    },
  );

  test(
    'health summary without workout uuid marks capturedOnWatch when metrics are present',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [],
      );

      when(() => repo.getWorkoutSession('s1')).thenAnswer((_) async => session);
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments.first as WorkoutSession,
      );

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      const summary = WatchHealthSummary(
        id: 'health-2',
        sessionId: 's1',
        durationSeconds: 1200,
        averageHeartRateBpm: 120,
        maxHeartRateBpm: 150,
        activeEnergyKilocalories: 180.0,
      );

      await handler.handleHealthSummary(summary);

      final captured =
          verify(
                () => repo.updateWorkoutSession(captureAny(), markDirty: false),
              ).captured.single
              as WorkoutSession;
      expect(captured.capturedOnWatch, isTrue);
      expect(captured.activeEnergyKilocalories, 180.0);
      expect(captured.averageHeartRateBpm, 120);
      expect(captured.maxHeartRateBpm, 150);
      expect(captured.watchDurationSeconds, 1200);
      expect(captured.watchWorkoutUuid, isNull);
    },
  );

  test(
    'health summary without workout uuid or metrics keeps capturedOnWatch false',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [],
      );

      when(() => repo.getWorkoutSession('s1')).thenAnswer((_) async => session);
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments.first as WorkoutSession,
      );

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      const summary = WatchHealthSummary(id: 'health-2b', sessionId: 's1');

      await handler.handleHealthSummary(summary);

      final captured =
          verify(
                () => repo.updateWorkoutSession(captureAny(), markDirty: false),
              ).captured.single
              as WorkoutSession;
      expect(captured.capturedOnWatch, isFalse);
      expect(captured.watchWorkoutUuid, isNull);
    },
  );

  test('markSetComplete recomputes the next exercise suggestion', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    const exercise1 = WorkoutExercise(
      id: 'ex-1',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 90,
      sets: [WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: false)],
    );
    const exercise2 = WorkoutExercise(
      id: 'ex-2',
      exercise: Exercise(name: 'Squat', muscles: []),
      sets: [WorkoutSet(id: 'set-2', weight: 140, reps: 5, isCompleted: false)],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: [exercise1, exercise2],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    when(() => restTimer.status).thenReturn(TimerStatus.idle);
    when(() => repo.updateSetInExercise('s1', 'ex-1', 0, any())).thenAnswer((
      invocation,
    ) async {
      final updated = invocation.positionalArguments[3] as WorkoutSet;
      return exercise1.updateSet(0, updated);
    });

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    const command = WatchCommand(
      id: 'cmd-1',
      type: WatchCommandType.markSetComplete,
      sessionId: 's1',
    );

    await handler.handleCommand(command);

    final updatedSet =
        verify(
              () => repo.updateSetInExercise('s1', 'ex-1', 0, captureAny()),
            ).captured.single
            as WorkoutSet;
    expect(updatedSet.watchCommandId, 'cmd-1');

    final captured = verify(
      () => restTimer.startTimer(
        durationInSeconds: any(named: 'durationInSeconds'),
        exerciseId: any(named: 'exerciseId'),
        exerciseName: any(named: 'exerciseName'),
        notificationNextExerciseName: captureAny(
          named: 'notificationNextExerciseName',
        ),
        notificationIsNextSet: captureAny(named: 'notificationIsNextSet'),
        // Pin the exact flag value: the fresh-decision call sites MUST pass
        // true so an explicit null next exercise clears any stale stored name.
        updateNotificationNextExercise: true,
      ),
    ).captured;
    expect(captured[0], 'Squat');
    expect(captured[1], isFalse);
  });

  test('restStart starts the timer with a fresh next-exercise decision '
      '(updateNotificationNextExercise: true)', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    const exercise1 = WorkoutExercise(
      id: 'ex-1',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 90,
      sets: [WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: false)],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: const [exercise1],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    when(() => restTimer.status).thenReturn(TimerStatus.idle);
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer(
      (invocation) async =>
          invocation.positionalArguments.first as WorkoutSession,
    );

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    const command = WatchCommand(
      id: 'cmd-rest',
      type: WatchCommandType.restStart,
      sessionId: 's1',
    );

    await handler.handleCommand(command);

    // The remaining set means the current exercise is its own "next set", and
    // the fresh-decision flag MUST be true so the stored name can never go
    // stale on a later all-complete rest.
    final captured = verify(
      () => restTimer.startTimer(
        durationInSeconds: 90,
        exerciseId: 'ex-1',
        exerciseName: 'Bench Press',
        notificationNextExerciseName: captureAny(
          named: 'notificationNextExerciseName',
        ),
        notificationIsNextSet: captureAny(named: 'notificationIsNextSet'),
        updateNotificationNextExercise: true,
      ),
    ).captured;
    expect(captured[0], 'Bench Press');
    expect(captured[1], isTrue);
  });

  test(
    'replayed markSetComplete command id does not complete the next set',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      const exercise = WorkoutExercise(
        id: 'ex-1',
        exercise: Exercise(name: 'Bench Press', muscles: []),
        restTimerSeconds: 60,
        sets: [
          WorkoutSet(
            id: 'set-1',
            weight: 100,
            reps: 5,
            isCompleted: true,
            watchCommandId: 'cmd-mark-replay',
          ),
          WorkoutSet(id: 'set-2', weight: 105, reps: 5, isCompleted: false),
        ],
      );
      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: [exercise],
      );

      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => session);

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      await handler.handleCommand(
        const WatchCommand(
          id: 'cmd-mark-replay',
          type: WatchCommandType.markSetComplete,
          sessionId: 's1',
        ),
      );

      verifyNever(() => repo.updateSetInExercise(any(), any(), any(), any()));
      verifyNever(
        () => restTimer.startTimer(
          durationInSeconds: any(named: 'durationInSeconds'),
          exerciseId: any(named: 'exerciseId'),
          exerciseName: any(named: 'exerciseName'),
          notificationNextExerciseName: any(
            named: 'notificationNextExerciseName',
          ),
          notificationIsNextSet: any(named: 'notificationIsNextSet'),
        ),
      );
    },
  );

  test('markSetComplete with an explicit exerciseId targets THAT exercise '
      'even while a REST timer is running for ANOTHER exercise (explicit id is '
      'authoritative, not the rest-anchored selection)', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    // ex-1 (the intended target) still has an incomplete set; ex-2 is the
    // exercise the rest timer is anchored to (the user is mid-rest on ex-2).
    const first = WorkoutExercise(
      id: 'ex-1',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 60,
      sets: [WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: false)],
    );
    const second = WorkoutExercise(
      id: 'ex-2',
      exercise: Exercise(name: 'Squat', muscles: []),
      restTimerSeconds: 90,
      sets: [WorkoutSet(id: 'set-2', weight: 140, reps: 5, isCompleted: false)],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: [first, second],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    // A rest timer is RUNNING for ex-2 — the OLD code completed a set here.
    when(() => restTimer.status).thenReturn(TimerStatus.running);
    when(() => restTimer.currentExerciseId).thenReturn('ex-2');
    when(
      () => restTimer.startTimer(
        durationInSeconds: any(named: 'durationInSeconds'),
        exerciseId: any(named: 'exerciseId'),
        exerciseName: any(named: 'exerciseName'),
        notificationNextExerciseName: any(
          named: 'notificationNextExerciseName',
        ),
        notificationIsNextSet: any(named: 'notificationIsNextSet'),
        updateNotificationNextExercise: any(
          named: 'updateNotificationNextExercise',
        ),
      ),
    ).thenReturn(null);
    when(() => repo.updateSetInExercise('s1', 'ex-1', any(), any())).thenAnswer(
      (invocation) async {
        final index = invocation.positionalArguments[2] as int;
        final updated = invocation.positionalArguments[3] as WorkoutSet;
        return first.updateSet(index, updated);
      },
    );

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    await handler.handleCommand(
      const WatchCommand(
        id: 'cmd-mark-explicit',
        type: WatchCommandType.markSetComplete,
        sessionId: 's1',
        exerciseId: 'ex-1',
      ),
    );

    // The set completed on ex-1 (the explicit target), NEVER on the resting
    // ex-2.
    verifyNever(() => repo.updateSetInExercise('s1', 'ex-2', any(), any()));
    final updated = verify(
      () => repo.updateSetInExercise('s1', 'ex-1', captureAny(), captureAny()),
    ).captured;
    expect(updated, hasLength(2));
    expect(updated[0], 0);
    expect((updated[1] as WorkoutSet).isCompleted, isTrue);
    // Rest restarts for the COMPLETED exercise (ex-1), and the notification
    // points at the next incomplete exercise (ex-2), with the fresh-decision
    // flag set so a later all-complete rest can never reuse a stale name.
    final started = verify(
      () => restTimer.startTimer(
        durationInSeconds: 60,
        exerciseId: 'ex-1',
        exerciseName: 'Bench Press',
        notificationNextExerciseName: captureAny(
          named: 'notificationNextExerciseName',
        ),
        notificationIsNextSet: captureAny(named: 'notificationIsNextSet'),
        updateNotificationNextExercise: true,
      ),
    ).captured;
    expect(started[0], 'Squat');
    expect(started[1], isFalse);
  });

  test(
    'markSetComplete with a stale/unknown exerciseId no-ops (does NOT complete '
    'a set on the first exercise) and echoes the command id for ack',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      const first = WorkoutExercise(
        id: 'ex-1',
        exercise: Exercise(name: 'Bench Press', muscles: []),
        restTimerSeconds: 60,
        sets: [
          WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: false),
        ],
      );
      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: [first],
      );

      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => session);
      when(() => restTimer.status).thenReturn(TimerStatus.idle);
      when(() => restTimer.currentExerciseId).thenReturn(null);

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      await handler.handleCommand(
        const WatchCommand(
          id: 'cmd-mark-stale',
          type: WatchCommandType.markSetComplete,
          sessionId: 's1',
          exerciseId: 'ex-gone',
        ),
      );

      // No set completed ANYWHERE — crucially not against the first exercise.
      verifyNever(() => repo.updateSetInExercise(any(), any(), any(), any()));
      verifyNever(
        () => restTimer.startTimer(
          durationInSeconds: any(named: 'durationInSeconds'),
          exerciseId: any(named: 'exerciseId'),
          exerciseName: any(named: 'exerciseName'),
          notificationNextExerciseName: any(
            named: 'notificationNextExerciseName',
          ),
          notificationIsNextSet: any(named: 'notificationIsNextSet'),
          updateNotificationNextExercise: any(
            named: 'updateNotificationNextExercise',
          ),
        ),
      );

      // The command id is still echoed so the watch's optimistic overlay clears
      // on the no-op path (the set is never stamped there, so the applied-id
      // ledger is its only ack).
      final after = await handler.buildStatePayload();
      expect((after!['appliedCommandIds'] as List), contains('cmd-mark-stale'));
    },
  );

  test('markSetComplete with a catalog exerciseId targets a watch-created row '
      'before the phone row id echo arrives', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    const watchAdded = WorkoutExercise(
      id: 'row-curl',
      exercise: Exercise(id: 'cat-curl', name: '21s Bicep Curl', muscles: []),
      restTimerSeconds: 60,
      createdFromWatch: true,
      sets: [WorkoutSet(id: 'set-1', weight: 15, reps: 7, isCompleted: false)],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: const [watchAdded],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    when(() => restTimer.status).thenReturn(TimerStatus.idle);
    when(() => restTimer.currentExerciseId).thenReturn(null);
    when(
      () => repo.updateSetInExercise('s1', 'row-curl', any(), any()),
    ).thenAnswer((invocation) async {
      final index = invocation.positionalArguments[2] as int;
      final updated = invocation.positionalArguments[3] as WorkoutSet;
      return watchAdded.updateSet(index, updated);
    });
    when(
      () => restTimer.startTimer(
        durationInSeconds: any(named: 'durationInSeconds'),
        exerciseId: any(named: 'exerciseId'),
        exerciseName: any(named: 'exerciseName'),
        notificationNextExerciseName: any(
          named: 'notificationNextExerciseName',
        ),
        notificationIsNextSet: any(named: 'notificationIsNextSet'),
        updateNotificationNextExercise: any(
          named: 'updateNotificationNextExercise',
        ),
      ),
    ).thenReturn(null);

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    await handler.handleCommand(
      const WatchCommand(
        id: 'cmd-mark-catalog',
        type: WatchCommandType.markSetComplete,
        sessionId: 's1',
        exerciseId: 'cat-curl',
      ),
    );

    final updated = verify(
      () => repo.updateSetInExercise('s1', 'row-curl', captureAny(), any()),
    ).captured;
    expect(updated.single, 0);
    verify(
      () => restTimer.startTimer(
        durationInSeconds: 60,
        exerciseId: 'row-curl',
        exerciseName: '21s Bicep Curl',
        notificationNextExerciseName: any(
          named: 'notificationNextExerciseName',
        ),
        notificationIsNextSet: any(named: 'notificationIsNextSet'),
        updateNotificationNextExercise: true,
      ),
    ).called(1);
  });

  test('logSet updates weight/reps and can complete multiple sets', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    const exercise = WorkoutExercise(
      id: 'ex-1',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 60,
      sets: [
        WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: false),
        WorkoutSet(id: 'set-2', weight: 100, reps: 5, isCompleted: false),
      ],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: [exercise],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    when(() => restTimer.status).thenReturn(TimerStatus.idle);
    when(() => repo.updateSetInExercise('s1', 'ex-1', any(), any())).thenAnswer(
      (invocation) async {
        final index = invocation.positionalArguments[2] as int;
        final updated = invocation.positionalArguments[3] as WorkoutSet;
        return exercise.updateSet(index, updated);
      },
    );

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    const command = WatchCommand(
      id: 'cmd-1',
      type: WatchCommandType.logSet,
      sessionId: 's1',
      exerciseId: 'ex-1',
      weight: 135,
      reps: 8,
      setCount: 2,
    );

    await handler.handleCommand(command);

    final capturedUpdates = verify(
      () => repo.updateSetInExercise('s1', 'ex-1', captureAny(), captureAny()),
    ).captured;
    expect(capturedUpdates, hasLength(4));
    expect(capturedUpdates[0], 0);
    expect((capturedUpdates[1] as WorkoutSet).weight, 135);
    expect((capturedUpdates[1] as WorkoutSet).reps, 8);
    expect((capturedUpdates[1] as WorkoutSet).isCompleted, isTrue);
    expect((capturedUpdates[1] as WorkoutSet).watchCommandId, 'cmd-1');
    expect(capturedUpdates[2], 1);
    expect((capturedUpdates[3] as WorkoutSet).weight, 135);
    expect((capturedUpdates[3] as WorkoutSet).reps, 8);
    expect((capturedUpdates[3] as WorkoutSet).isCompleted, isTrue);
    expect((capturedUpdates[3] as WorkoutSet).watchCommandId, 'cmd-1');
  });

  test('replayed logSet command id does not complete the next set', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    const exercise = WorkoutExercise(
      id: 'ex-1',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 60,
      sets: [
        WorkoutSet(
          id: 'set-1',
          weight: 135,
          reps: 8,
          isCompleted: true,
          watchCommandId: 'cmd-replay',
        ),
        WorkoutSet(id: 'set-2', weight: 100, reps: 5, isCompleted: false),
      ],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: [exercise],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    await handler.handleCommand(
      const WatchCommand(
        id: 'cmd-replay',
        type: WatchCommandType.logSet,
        sessionId: 's1',
        exerciseId: 'ex-1',
        weight: 140,
        reps: 10,
      ),
    );

    verifyNever(() => repo.updateSetInExercise(any(), any(), any(), any()));
    verifyNever(
      () => restTimer.startTimer(
        durationInSeconds: any(named: 'durationInSeconds'),
        exerciseId: any(named: 'exerciseId'),
        exerciseName: any(named: 'exerciseName'),
        notificationNextExerciseName: any(
          named: 'notificationNextExerciseName',
        ),
        notificationIsNextSet: any(named: 'notificationIsNextSet'),
      ),
    );
  });

  test('logSet completion advances the next phone state payload', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    var session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: const [
        WorkoutExercise(
          id: 'ex-1',
          exercise: Exercise(name: 'Bench Press', muscles: []),
          restTimerSeconds: 60,
          sets: [
            WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: false),
            WorkoutSet(
              id: 'set-2',
              weight: 105,
              reps: 5,
              rpe: 8,
              isCompleted: false,
            ),
          ],
        ),
      ],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    when(() => restTimer.status).thenReturn(TimerStatus.idle);
    when(
      () => restTimer.remainingSeconds,
    ).thenReturn(RestTimerService.defaultRestTime);
    when(
      () => restTimer.originalDurationSeconds,
    ).thenReturn(RestTimerService.defaultRestTime);
    when(() => restTimer.currentExerciseId).thenReturn(null);
    when(() => repo.updateSetInExercise('s1', 'ex-1', any(), any())).thenAnswer(
      (invocation) async {
        final index = invocation.positionalArguments[2] as int;
        final updated = invocation.positionalArguments[3] as WorkoutSet;
        final exercise = session.exercises.first;
        final updatedExercise = exercise.updateSet(index, updated);
        session = session.updateExercise(0, updatedExercise);
        return updatedExercise;
      },
    );

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    final before = await handler.buildStatePayload();
    expect(before?['nextSetIndex'], 1);

    await handler.handleCommand(
      const WatchCommand(
        id: 'cmd-advance',
        type: WatchCommandType.logSet,
        sessionId: 's1',
        exerciseId: 'ex-1',
        weight: 102.5,
        reps: 6,
        rpe: 9,
      ),
    );

    final after = await handler.buildStatePayload();
    expect(after?['nextSetIndex'], 2);
    expect(after?['nextSetWeight'], 105);
    expect(after?['nextSetReps'], 5);
    expect(after?['nextSetRpe'], 8);
    expect(session.exercises.first.sets.first.rpe, 9);
    expect((after?['appliedCommandIds'] as List), contains('cmd-advance'));
  });

  test('logSet on an exercise whose sets are ALL complete is a no-op '
      '(phantom final-set tap writes nothing)', () async {
    // Regression for the watch final-set phantom-log / data-loss path: after the
    // last set is complete the watch must not keep firing log_set. The phone-side
    // guard (no incomplete set -> completedAny == false -> early return) is what
    // makes those extra taps a SILENT no-op; if the watch ever queues one (offline),
    // this proves the phone neither writes a set nor restarts rest.
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    const exercise = WorkoutExercise(
      id: 'ex-1',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 60,
      sets: [WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: true)],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: [exercise],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    when(() => restTimer.status).thenReturn(TimerStatus.idle);
    when(() => restTimer.currentExerciseId).thenReturn(null);

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    await handler.handleCommand(
      const WatchCommand(
        id: 'cmd-phantom-final',
        type: WatchCommandType.logSet,
        sessionId: 's1',
        exerciseId: 'ex-1',
        weight: 110,
        reps: 6,
        setCount: 1,
      ),
    );

    // No set was written (nothing to complete), and no rest timer was (re)started.
    verifyNever(() => repo.updateSetInExercise(any(), any(), any(), any()));
    verifyNever(
      () => restTimer.startTimer(
        durationInSeconds: any(named: 'durationInSeconds'),
        exerciseId: any(named: 'exerciseId'),
        exerciseName: any(named: 'exerciseName'),
        notificationNextExerciseName: any(
          named: 'notificationNextExerciseName',
        ),
        notificationIsNextSet: any(named: 'notificationIsNextSet'),
      ),
    );
  });

  test('addSet appends an incomplete set seeded from the last set', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    const exercise = WorkoutExercise(
      id: 'ex-1',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 60,
      sets: [WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: true)],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: [exercise],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    when(() => restTimer.status).thenReturn(TimerStatus.idle);
    when(() => repo.addSetToExercise('s1', 'ex-1', any())).thenAnswer((
      invocation,
    ) async {
      final set = invocation.positionalArguments[2] as WorkoutSet;
      return exercise.addSet(set);
    });

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    const command = WatchCommand(
      id: 'cmd-add-set',
      type: WatchCommandType.addSet,
      sessionId: 's1',
      exerciseId: 'ex-1',
    );

    await handler.handleCommand(command);

    final appended =
        verify(
              () => repo.addSetToExercise('s1', 'ex-1', captureAny()),
            ).captured.single
            as WorkoutSet;
    expect(appended.isCompleted, isFalse);
    // Seeded from the exercise's last (completed) set so it prefills sensibly.
    expect(appended.weight, 100);
    expect(appended.reps, 5);
    expect(appended.setType, SetType.regular);
    expect(
      appended.id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(appended.id, isNot('watch-add-cmd-add-set'));
    expect(appended.watchCommandId, 'cmd-add-set');
  });

  test('replayed addSet command id does not append a duplicate set', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    const exercise = WorkoutExercise(
      id: 'ex-1',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 60,
      sets: [
        WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: true),
        WorkoutSet(
          id: '550e8400-e29b-41d4-a716-446655440001',
          weight: 100,
          reps: 5,
          watchCommandId: 'cmd-add-replay',
        ),
      ],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: [exercise],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    await handler.handleCommand(
      const WatchCommand(
        id: 'cmd-add-replay',
        type: WatchCommandType.addSet,
        sessionId: 's1',
        exerciseId: 'ex-1',
      ),
    );

    verifyNever(() => repo.addSetToExercise(any(), any(), any()));
  });

  test(
    'addSet re-enables set marking after the planned set was completed',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      // Single planned set, already completed -> canMarkSet is false.
      var exercise = const WorkoutExercise(
        id: 'ex-1',
        exercise: Exercise(name: 'Bench Press', muscles: []),
        restTimerSeconds: 60,
        sets: [
          WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: true),
        ],
      );
      WorkoutSession sessionOf(WorkoutExercise ex) => WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: [ex],
      );

      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => sessionOf(exercise));
      when(() => restTimer.status).thenReturn(TimerStatus.idle);
      when(() => restTimer.currentExerciseId).thenReturn(null);
      when(() => repo.addSetToExercise('s1', 'ex-1', any())).thenAnswer((
        invocation,
      ) async {
        final set = invocation.positionalArguments[2] as WorkoutSet;
        exercise = exercise.addSet(set);
        return exercise;
      });

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      // Before: all planned sets complete, nothing to mark.
      final before = await handler.buildStatePayload();
      expect(
        (before!['capabilities'] as Map)['canMarkSet'],
        isFalse,
        reason: 'all planned sets are complete',
      );
      expect(before['nextSetIndex'], isNull);

      await handler.handleCommand(
        const WatchCommand(
          id: 'cmd-add-set-2',
          type: WatchCommandType.addSet,
          sessionId: 's1',
          exerciseId: 'ex-1',
        ),
      );

      // After: the appended incomplete set makes the snapshot immediately markable.
      final after = await handler.buildStatePayload();
      expect((after!['capabilities'] as Map)['canMarkSet'], isTrue);
      expect(after['nextSetIndex'], 2, reason: '2nd set, 1-based');
      expect(after['nextSetTotal'], 2);
    },
  );

  test('addSet with a stale/unknown exerciseId no-ops (does NOT append to the '
      'first exercise) and lets state republish', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    // Two exercises; a queued Add Set references an exercise id that no longer
    // exists in the active session (an older watch snapshot).
    const first = WorkoutExercise(
      id: 'ex-1',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 60,
      sets: [WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: false)],
    );
    const second = WorkoutExercise(
      id: 'ex-2',
      exercise: Exercise(name: 'Squat', muscles: []),
      restTimerSeconds: 60,
      sets: [WorkoutSet(id: 'set-2', weight: 140, reps: 5, isCompleted: false)],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: [first, second],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    when(() => restTimer.status).thenReturn(TimerStatus.idle);
    when(() => restTimer.currentExerciseId).thenReturn(null);

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    await handler.handleCommand(
      const WatchCommand(
        id: 'cmd-add-set-stale',
        type: WatchCommandType.addSet,
        sessionId: 's1',
        exerciseId: 'ex-gone',
      ),
    );

    // No set appended ANYWHERE — crucially not to the first exercise.
    verifyNever(() => repo.addSetToExercise(any(), any(), any()));

    // State republishes unchanged (the service's trailing publish handles this;
    // here we just confirm the current snapshot still reads correctly).
    final after = await handler.buildStatePayload();
    expect(after!['nextSetTotal'], 1, reason: 'no set was appended');
    expect((after['capabilities'] as Map)['canMarkSet'], isTrue);
  });

  test('addSet with a catalog exerciseId targets a watch-created row before '
      'the phone row id echo arrives', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    const watchAdded = WorkoutExercise(
      id: 'row-curl',
      exercise: Exercise(id: 'cat-curl', name: '21s Bicep Curl', muscles: []),
      restTimerSeconds: 60,
      createdFromWatch: true,
      sets: [WorkoutSet(id: 'set-1', weight: 10, reps: 8, isCompleted: true)],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: const [watchAdded],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    when(() => repo.addSetToExercise('s1', 'row-curl', any())).thenAnswer((
      invocation,
    ) async {
      final set = invocation.positionalArguments[2] as WorkoutSet;
      return watchAdded.addSet(set);
    });

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    await handler.handleCommand(
      const WatchCommand(
        id: 'cmd-add-catalog',
        type: WatchCommandType.addSet,
        sessionId: 's1',
        exerciseId: 'cat-curl',
      ),
    );

    final captured =
        verify(
              () => repo.addSetToExercise('s1', 'row-curl', captureAny()),
            ).captured.single
            as WorkoutSet;
    expect(captured.isCompleted, isFalse);
    expect(captured.weight, 10);
    expect(captured.reps, 8);
  });

  test(
    'addSet with an ambiguous catalog exerciseId across repeated watch-created '
    'rows no-ops',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      const first = WorkoutExercise(
        id: 'row-curl-1',
        exercise: Exercise(id: 'cat-curl', name: '21s Bicep Curl', muscles: []),
        restTimerSeconds: 60,
        createdFromWatch: true,
        sets: [WorkoutSet(id: 'set-1', weight: 10, reps: 8)],
      );
      const second = WorkoutExercise(
        id: 'row-curl-2',
        exercise: Exercise(id: 'cat-curl', name: '21s Bicep Curl', muscles: []),
        restTimerSeconds: 60,
        createdFromWatch: true,
        sets: [WorkoutSet(id: 'set-2', weight: 12, reps: 6)],
      );
      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [first, second],
      );

      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => session);

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      await handler.handleCommand(
        const WatchCommand(
          id: 'cmd-add-ambiguous-catalog',
          type: WatchCommandType.addSet,
          sessionId: 's1',
          exerciseId: 'cat-curl',
        ),
      );

      verifyNever(() => repo.addSetToExercise(any(), any(), any()));
    },
  );

  test(
    'addSet with a valid exerciseId appends to THAT exercise (not the first)',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      const first = WorkoutExercise(
        id: 'ex-1',
        exercise: Exercise(name: 'Bench Press', muscles: []),
        restTimerSeconds: 60,
        sets: [
          WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: false),
        ],
      );
      const second = WorkoutExercise(
        id: 'ex-2',
        exercise: Exercise(name: 'Squat', muscles: []),
        restTimerSeconds: 60,
        sets: [
          WorkoutSet(id: 'set-2', weight: 140, reps: 6, isCompleted: true),
        ],
      );
      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: [first, second],
      );

      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => session);
      when(() => restTimer.status).thenReturn(TimerStatus.idle);
      when(() => restTimer.currentExerciseId).thenReturn(null);
      when(() => repo.addSetToExercise('s1', 'ex-2', any())).thenAnswer((
        invocation,
      ) async {
        final set = invocation.positionalArguments[2] as WorkoutSet;
        return second.addSet(set);
      });

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      await handler.handleCommand(
        const WatchCommand(
          id: 'cmd-add-set-valid',
          type: WatchCommandType.addSet,
          sessionId: 's1',
          exerciseId: 'ex-2',
        ),
      );

      // Appended to ex-2 (the explicit target), never to ex-1.
      verifyNever(() => repo.addSetToExercise('s1', 'ex-1', any()));
      final appended =
          verify(
                () => repo.addSetToExercise('s1', 'ex-2', captureAny()),
              ).captured.single
              as WorkoutSet;
      expect(appended.isCompleted, isFalse);
      // Seeded from ex-2's last set (copy-last-set default).
      expect(appended.weight, 140);
      expect(appended.reps, 6);
      expect(appended.setType, SetType.regular);
    },
  );

  test('logSet with an explicit exerciseId targets THAT exercise even while a '
      'REST timer is running for ANOTHER exercise (Fix 1: explicit id is '
      'authoritative, not the rest-anchored selection)', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    // ex-1 (the intended target) still has an incomplete set; ex-2 is the
    // exercise the rest timer is anchored to (the user is mid-rest on ex-2).
    const first = WorkoutExercise(
      id: 'ex-1',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 60,
      sets: [WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: false)],
    );
    const second = WorkoutExercise(
      id: 'ex-2',
      exercise: Exercise(name: 'Squat', muscles: []),
      restTimerSeconds: 90,
      sets: [WorkoutSet(id: 'set-2', weight: 140, reps: 5, isCompleted: false)],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: [first, second],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    // A rest timer is RUNNING for ex-2 — the OLD code routed the set here.
    when(() => restTimer.status).thenReturn(TimerStatus.running);
    when(() => restTimer.currentExerciseId).thenReturn('ex-2');
    when(
      () => restTimer.startTimer(
        durationInSeconds: any(named: 'durationInSeconds'),
        exerciseId: any(named: 'exerciseId'),
        exerciseName: any(named: 'exerciseName'),
        notificationNextExerciseName: any(
          named: 'notificationNextExerciseName',
        ),
        notificationIsNextSet: any(named: 'notificationIsNextSet'),
      ),
    ).thenReturn(null);
    when(() => repo.updateSetInExercise('s1', 'ex-1', any(), any())).thenAnswer(
      (invocation) async {
        final index = invocation.positionalArguments[2] as int;
        final updated = invocation.positionalArguments[3] as WorkoutSet;
        return first.updateSet(index, updated);
      },
    );

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    await handler.handleCommand(
      const WatchCommand(
        id: 'cmd-log-explicit',
        type: WatchCommandType.logSet,
        sessionId: 's1',
        exerciseId: 'ex-1',
        weight: 135,
        reps: 8,
        setCount: 1,
      ),
    );

    // The set landed on ex-1 (the explicit target), NEVER on the resting ex-2.
    verifyNever(() => repo.updateSetInExercise('s1', 'ex-2', any(), any()));
    final updated = verify(
      () => repo.updateSetInExercise('s1', 'ex-1', captureAny(), captureAny()),
    ).captured;
    expect(updated, hasLength(2));
    expect(updated[0], 0);
    expect((updated[1] as WorkoutSet).weight, 135);
    expect((updated[1] as WorkoutSet).reps, 8);
    expect((updated[1] as WorkoutSet).isCompleted, isTrue);
    // Rest restarts for the LOGGED exercise (ex-1), not the previously-resting one.
    verify(
      () => restTimer.startTimer(
        durationInSeconds: 60,
        exerciseId: 'ex-1',
        exerciseName: 'Bench Press',
        notificationNextExerciseName: any(
          named: 'notificationNextExerciseName',
        ),
        notificationIsNextSet: any(named: 'notificationIsNextSet'),
        // Pin the exact flag value: the fresh-decision call sites MUST pass
        // true so an explicit null next exercise clears any stale stored name.
        updateNotificationNextExercise: true,
      ),
    ).called(1);
  });

  test('logSet with a catalog exerciseId targets a watch-created row before '
      'the phone row id echo arrives', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    const watchAdded = WorkoutExercise(
      id: 'row-curl',
      exercise: Exercise(id: 'cat-curl', name: '21s Bicep Curl', muscles: []),
      restTimerSeconds: 60,
      createdFromWatch: true,
      sets: [WorkoutSet(id: 'set-1', weight: 0, reps: 0, isCompleted: false)],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: const [watchAdded],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    when(
      () => repo.updateSetInExercise('s1', 'row-curl', any(), any()),
    ).thenAnswer((invocation) async {
      final index = invocation.positionalArguments[2] as int;
      final updated = invocation.positionalArguments[3] as WorkoutSet;
      return watchAdded.updateSet(index, updated);
    });
    when(
      () => restTimer.startTimer(
        durationInSeconds: any(named: 'durationInSeconds'),
        exerciseId: any(named: 'exerciseId'),
        exerciseName: any(named: 'exerciseName'),
        notificationNextExerciseName: any(
          named: 'notificationNextExerciseName',
        ),
        notificationIsNextSet: any(named: 'notificationIsNextSet'),
      ),
    ).thenReturn(null);

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    await handler.handleCommand(
      const WatchCommand(
        id: 'cmd-log-catalog',
        type: WatchCommandType.logSet,
        sessionId: 's1',
        exerciseId: 'cat-curl',
        weight: 15,
        reps: 7,
      ),
    );

    final updated = verify(
      () => repo.updateSetInExercise(
        's1',
        'row-curl',
        captureAny(),
        captureAny(),
      ),
    ).captured;
    expect(updated[0], 0);
    final set = updated[1] as WorkoutSet;
    expect(set.weight, 15);
    expect(set.reps, 7);
    expect(set.isCompleted, isTrue);
    verify(
      () => restTimer.startTimer(
        durationInSeconds: 60,
        exerciseId: 'row-curl',
        exerciseName: '21s Bicep Curl',
        notificationNextExerciseName: any(
          named: 'notificationNextExerciseName',
        ),
        notificationIsNextSet: any(named: 'notificationIsNextSet'),
        // Pin the exact flag value: the fresh-decision call sites MUST pass
        // true so an explicit null next exercise clears any stale stored name.
        updateNotificationNextExercise: true,
      ),
    ).called(1);
  });

  test(
    'logSet with a catalog exerciseId does not target a phone-authored row',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      const phoneAdded = WorkoutExercise(
        id: 'row-curl',
        exercise: Exercise(id: 'cat-curl', name: '21s Bicep Curl', muscles: []),
        restTimerSeconds: 60,
        createdFromWatch: false,
        sets: [WorkoutSet(id: 'set-1', weight: 0, reps: 0, isCompleted: false)],
      );
      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [phoneAdded],
      );

      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => session);
      when(() => restTimer.status).thenReturn(TimerStatus.idle);
      when(() => restTimer.currentExerciseId).thenReturn(null);

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      await handler.handleCommand(
        const WatchCommand(
          id: 'cmd-log-phone-catalog',
          type: WatchCommandType.logSet,
          sessionId: 's1',
          exerciseId: 'cat-curl',
          weight: 15,
          reps: 7,
        ),
      );

      verifyNever(() => repo.updateSetInExercise(any(), any(), any(), any()));
      verifyNever(
        () => restTimer.startTimer(
          durationInSeconds: any(named: 'durationInSeconds'),
          exerciseId: any(named: 'exerciseId'),
          exerciseName: any(named: 'exerciseName'),
          notificationNextExerciseName: any(
            named: 'notificationNextExerciseName',
          ),
          notificationIsNextSet: any(named: 'notificationIsNextSet'),
        ),
      );
    },
  );

  test(
    'logSet with an ambiguous catalog exerciseId across repeated watch-created '
    'rows no-ops',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      const first = WorkoutExercise(
        id: 'row-curl-1',
        exercise: Exercise(id: 'cat-curl', name: '21s Bicep Curl', muscles: []),
        restTimerSeconds: 60,
        createdFromWatch: true,
        sets: [WorkoutSet(id: 'set-1', weight: 10, reps: 8)],
      );
      const second = WorkoutExercise(
        id: 'row-curl-2',
        exercise: Exercise(id: 'cat-curl', name: '21s Bicep Curl', muscles: []),
        restTimerSeconds: 60,
        createdFromWatch: true,
        sets: [WorkoutSet(id: 'set-2', weight: 12, reps: 6)],
      );
      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [first, second],
      );

      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => session);

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      await handler.handleCommand(
        const WatchCommand(
          id: 'cmd-log-ambiguous-catalog',
          type: WatchCommandType.logSet,
          sessionId: 's1',
          exerciseId: 'cat-curl',
          weight: 15,
          reps: 7,
        ),
      );

      verifyNever(() => repo.updateSetInExercise(any(), any(), any(), any()));
      verifyNever(
        () => restTimer.startTimer(
          durationInSeconds: any(named: 'durationInSeconds'),
          exerciseId: any(named: 'exerciseId'),
          exerciseName: any(named: 'exerciseName'),
          notificationNextExerciseName: any(
            named: 'notificationNextExerciseName',
          ),
          notificationIsNextSet: any(named: 'notificationIsNextSet'),
        ),
      );
    },
  );

  test(
    'logSet with a stale/unknown exerciseId no-ops (does NOT log against the '
    'first exercise) and lets state republish (Fix 1 stale-id edge case)',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      const first = WorkoutExercise(
        id: 'ex-1',
        exercise: Exercise(name: 'Bench Press', muscles: []),
        restTimerSeconds: 60,
        sets: [
          WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: false),
        ],
      );
      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: [first],
      );

      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => session);
      when(() => restTimer.status).thenReturn(TimerStatus.idle);
      when(() => restTimer.currentExerciseId).thenReturn(null);

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      await handler.handleCommand(
        const WatchCommand(
          id: 'cmd-log-stale',
          type: WatchCommandType.logSet,
          sessionId: 's1',
          exerciseId: 'ex-gone',
          weight: 135,
          reps: 8,
          setCount: 1,
        ),
      );

      // No set written ANYWHERE — crucially not against the first exercise.
      verifyNever(() => repo.updateSetInExercise(any(), any(), any(), any()));
      verifyNever(
        () => restTimer.startTimer(
          durationInSeconds: any(named: 'durationInSeconds'),
          exerciseId: any(named: 'exerciseId'),
          exerciseName: any(named: 'exerciseName'),
          notificationNextExerciseName: any(
            named: 'notificationNextExerciseName',
          ),
          notificationIsNextSet: any(named: 'notificationIsNextSet'),
        ),
      );

      // State still republishes the unchanged snapshot (the service's trailing
      // publish ships it; here we confirm the snapshot reads correctly) AND
      // echoes the command id so the watch overlay can still clear on this ack.
      final after = await handler.buildStatePayload();
      expect(after!['nextSetIndex'], 1, reason: 'no set was completed');
      expect((after['appliedCommandIds'] as List), contains('cmd-log-stale'));
    },
  );

  // --- Issue #481: characterize the conditions under which a set completed on
  // the watch silently fails to complete on the phone. These assert the CURRENT
  // (no-op) behavior so we can pin the root cause; a targeted fix follows once a
  // device repro confirms which guard fires in practice. ---

  test('DIAG #481: logSet keyed on a catalog id for a PHONE-authored row no-ops '
      '(catalog-id rescue only applies to watch-created rows)', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    // A phone-authored exercise (createdFromWatch: false) that carries a
    // catalog id. If the watch ever keys its command on the catalog id (or
    // the phone re-created the row with a new row id while the watch still
    // holds the catalog id), the explicit-id match fails on the row id AND the
    // catalog-id rescue is skipped because the row is not watch-created — so
    // the set silently does not complete on the phone.
    const phoneRow = WorkoutExercise(
      id: 'row-phone-1',
      exercise: Exercise(id: 'cat-bench', name: 'Bench Press', muscles: []),
      restTimerSeconds: 60,
      sets: [WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: false)],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: const [phoneRow],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    when(() => restTimer.status).thenReturn(TimerStatus.idle);
    when(() => restTimer.currentExerciseId).thenReturn(null);

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    await handler.handleCommand(
      const WatchCommand(
        id: 'cmd-log-catalog-phone',
        type: WatchCommandType.logSet,
        sessionId: 's1',
        exerciseId: 'cat-bench', // catalog id, not the row id
        weight: 135,
        reps: 8,
        setCount: 1,
      ),
    );

    // Silent fail: nothing completed, but the id is still acked so the watch
    // overlay clears (the user sees the tap "succeed" while the phone keeps
    // the set open — exactly the reported symptom).
    verifyNever(() => repo.updateSetInExercise(any(), any(), any(), any()));
    final after = await handler.buildStatePayload();
    expect(
      (after!['appliedCommandIds'] as List),
      contains('cmd-log-catalog-phone'),
    );
  });

  // DIAG #481 (lineage): this test previously PINNED the buggy contract — a
  // foreign-session log_set was dropped yet ACKED in `appliedCommandIds`, so the
  // watch cleared its optimistic overlay as a false success and the completed set
  // was lost. The fix splits the foreign-session path into REJECT (target
  // unknown/terminal) and RECOVERY (target still real → retarget the mutation).
  // The two tests below pin the NEW correct contract.
  test('DIAG #481: logSet for an UNKNOWN/terminal non-active session is REJECTED '
      '(not acked as applied) so the watch can surface a failure', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    // The watch is acting on an older session snapshot (s-old) while the phone
    // has already moved on to a new active session (s-new). s-old no longer
    // resolves to any stored session, so the command CANNOT be retargeted — it
    // must be reported as rejected, not silently acked.
    const exercise = WorkoutExercise(
      id: 'ex-1',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 60,
      sets: [WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: false)],
    );
    final activeSession = WorkoutSession(
      id: 's-new',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: const [exercise],
    );

    when(
      () => repo.getLatestActiveSession(),
    ).thenAnswer((_) async => activeSession);
    // s-old is gone: recovery lookup returns null → the command is rejected.
    when(() => repo.getWorkoutSession('s-old')).thenAnswer((_) async => null);
    when(() => restTimer.status).thenReturn(TimerStatus.idle);
    when(() => restTimer.currentExerciseId).thenReturn(null);

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    await handler.handleCommand(
      const WatchCommand(
        id: 'cmd-log-foreign',
        type: WatchCommandType.logSet,
        sessionId: 's-old', // superseded session the watch still holds
        exerciseId: 'ex-1',
        weight: 135,
        reps: 8,
        setCount: 1,
      ),
    );

    verifyNever(() => repo.updateSetInExercise(any(), any(), any(), any()));
    final after = await handler.buildStatePayload();
    // NEW contract: the dropped id is REJECTED, not applied — so the watch reverts
    // its overlay and signals failure instead of a false success.
    expect((after!['rejectedCommandIds'] as List), contains('cmd-log-foreign'));
    expect(
      (after['appliedCommandIds'] as List?) ?? const [],
      isNot(contains('cmd-log-foreign')),
    );
  });

  test('DIAG #481: logSet for a still-real non-active session is RECOVERED — the '
      'set lands on that session instead of being dropped', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    // The watch holds s-old (a real, still-running session) while the phone's
    // ACTIVE session is s-new. The completed set must not be lost: it is
    // retargeted onto s-old (its true owner) rather than dropped.
    const activeExercise = WorkoutExercise(
      id: 'ex-new',
      exercise: Exercise(name: 'Squat', muscles: []),
      restTimerSeconds: 60,
      sets: [
        WorkoutSet(id: 'set-new', weight: 200, reps: 5, isCompleted: false),
      ],
    );
    final activeSession = WorkoutSession(
      id: 's-new',
      name: 'Workout B',
      startTime: DateTime(2024, 1, 2),
      exercises: const [activeExercise],
    );
    const oldExercise = WorkoutExercise(
      id: 'ex-1',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 60,
      sets: [WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: false)],
    );
    final oldSession = WorkoutSession(
      id: 's-old',
      name: 'Workout A',
      startTime: DateTime(2024),
      exercises: const [oldExercise],
    );

    when(
      () => repo.getLatestActiveSession(),
    ).thenAnswer((_) async => activeSession);
    // s-old is still real and non-terminal → recovery retargets the mutation.
    when(
      () => repo.getWorkoutSession('s-old'),
    ).thenAnswer((_) async => oldSession);
    when(
      () => repo.updateSetInExercise('s-old', 'ex-1', 0, any()),
    ).thenAnswer((_) async => oldExercise);
    when(() => restTimer.status).thenReturn(TimerStatus.idle);
    when(() => restTimer.currentExerciseId).thenReturn(null);

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    await handler.handleCommand(
      const WatchCommand(
        id: 'cmd-log-recover',
        type: WatchCommandType.logSet,
        sessionId: 's-old',
        exerciseId: 'ex-1',
        weight: 135,
        reps: 8,
        setCount: 1,
      ),
    );

    // The set lands on the recovered session, NOT the active one.
    final captured = verify(
      () => repo.updateSetInExercise('s-old', 'ex-1', 0, captureAny()),
    ).captured;
    final landedSet = captured.single as WorkoutSet;
    expect(landedSet.isCompleted, isTrue);
    expect(landedSet.weight, 135);
    expect(landedSet.reps, 8);
    verifyNever(() => repo.updateSetInExercise('s-new', any(), any(), any()));

    // DIAG #481 (lineage): a retargeted background set must NOT hijack the phone's
    // GLOBAL rest timer, which is anchored to the FOREGROUND active session
    // (s-new). Previously the full case body ran against s-old and started the
    // singleton rest countdown/notification for s-old's exercise — an uncovered
    // cross-session side effect. The recovery path now suppresses it.
    verifyNever(
      () => restTimer.startTimer(
        durationInSeconds: any(named: 'durationInSeconds'),
        exerciseId: any(named: 'exerciseId'),
        exerciseName: any(named: 'exerciseName'),
        notificationNextExerciseName: any(
          named: 'notificationNextExerciseName',
        ),
        notificationIsNextSet: any(named: 'notificationIsNextSet'),
        updateNotificationNextExercise: any(
          named: 'updateNotificationNextExercise',
        ),
      ),
    );

    final after = await handler.buildStatePayload();
    // A recovered set is APPLIED, not rejected.
    expect((after!['appliedCommandIds'] as List), contains('cmd-log-recover'));
    expect(
      (after['rejectedCommandIds'] as List?) ?? const [],
      isNot(contains('cmd-log-recover')),
    );
  });

  test('COMMAND-ACK: an applied log_set id is echoed in appliedCommandIds so the '
      'watch can clear its optimistic overlay authoritatively', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    const exercise = WorkoutExercise(
      id: 'ex-1',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 60,
      sets: [
        WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: false),
        WorkoutSet(id: 'set-2', weight: 100, reps: 5, isCompleted: false),
      ],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: [exercise],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    when(() => restTimer.status).thenReturn(TimerStatus.idle);
    when(() => restTimer.currentExerciseId).thenReturn(null);
    when(
      () => restTimer.startTimer(
        durationInSeconds: any(named: 'durationInSeconds'),
        exerciseId: any(named: 'exerciseId'),
        exerciseName: any(named: 'exerciseName'),
        notificationNextExerciseName: any(
          named: 'notificationNextExerciseName',
        ),
        notificationIsNextSet: any(named: 'notificationIsNextSet'),
      ),
    ).thenReturn(null);
    when(() => repo.updateSetInExercise('s1', 'ex-1', any(), any())).thenAnswer(
      (invocation) async {
        final index = invocation.positionalArguments[2] as int;
        final updated = invocation.positionalArguments[3] as WorkoutSet;
        return exercise.updateSet(index, updated);
      },
    );

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    // Before any command, no acks are present.
    final before = await handler.buildStatePayload();
    expect(before!['appliedCommandIds'], isNull);

    await handler.handleCommand(
      const WatchCommand(
        id: 'cmd-ack-1',
        type: WatchCommandType.logSet,
        sessionId: 's1',
        exerciseId: 'ex-1',
        weight: 135,
        reps: 8,
        setCount: 1,
      ),
    );

    // The applied id is now echoed so the watch overlay clears on this exact ack.
    final after = await handler.buildStatePayload();
    final acks = after!['appliedCommandIds'] as List;
    expect(acks, contains('cmd-ack-1'));
  });

  test(
    'COMMAND-ACK (Fix 2): the NO-SESSION state payload echoes appliedCommandIds '
    'so a session-end null echo still acks a just-logged set',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      const exercise = WorkoutExercise(
        id: 'ex-1',
        exercise: Exercise(name: 'Bench Press', muscles: []),
        restTimerSeconds: 60,
        sets: [
          WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: false),
        ],
      );
      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: [exercise],
      );

      // First the session is active (so a log_set records an ack), then it ends
      // (the next state build returns the no-session payload).
      var active = true;
      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => active ? session : null);
      when(
        () => repo.getWorkoutSessions(limit: any(named: 'limit')),
      ).thenAnswer((_) async => const []);
      when(() => restTimer.status).thenReturn(TimerStatus.idle);
      when(() => restTimer.currentExerciseId).thenReturn(null);
      when(
        () => restTimer.startTimer(
          durationInSeconds: any(named: 'durationInSeconds'),
          exerciseId: any(named: 'exerciseId'),
          exerciseName: any(named: 'exerciseName'),
          notificationNextExerciseName: any(
            named: 'notificationNextExerciseName',
          ),
          notificationIsNextSet: any(named: 'notificationIsNextSet'),
        ),
      ).thenReturn(null);
      when(
        () => repo.updateSetInExercise('s1', 'ex-1', any(), any()),
      ).thenAnswer((invocation) async {
        final index = invocation.positionalArguments[2] as int;
        final updated = invocation.positionalArguments[3] as WorkoutSet;
        return exercise.updateSet(index, updated);
      });

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      await handler.handleCommand(
        const WatchCommand(
          id: 'cmd-end-ack',
          type: WatchCommandType.logSet,
          sessionId: 's1',
          exerciseId: 'ex-1',
          weight: 135,
          reps: 8,
          setCount: 1,
        ),
      );

      // The workout ends; the next published state is the no-session payload.
      active = false;
      final payload = await handler.buildStatePayload();
      expect(payload, isNotNull);
      expect(payload!['sessionId'], isNull);
      expect(
        payload['appliedCommandIds'],
        isNotNull,
        reason: 'no-session payload must still echo the ack',
      );
      expect((payload['appliedCommandIds'] as List), contains('cmd-end-ack'));
    },
  );

  test('COMMAND-ACK (Fix 3): a DEDUPED log_set still records the ack on the '
      'early-return path so the overlay clears on re-delivery', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    const exercise = WorkoutExercise(
      id: 'ex-1',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 60,
      sets: [
        WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: false),
        WorkoutSet(id: 'set-2', weight: 100, reps: 5, isCompleted: false),
      ],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: [exercise],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    when(() => restTimer.status).thenReturn(TimerStatus.idle);
    when(() => restTimer.currentExerciseId).thenReturn(null);
    when(
      () => restTimer.startTimer(
        durationInSeconds: any(named: 'durationInSeconds'),
        exerciseId: any(named: 'exerciseId'),
        exerciseName: any(named: 'exerciseName'),
        notificationNextExerciseName: any(
          named: 'notificationNextExerciseName',
        ),
        notificationIsNextSet: any(named: 'notificationIsNextSet'),
      ),
    ).thenReturn(null);
    when(() => repo.updateSetInExercise('s1', 'ex-1', any(), any())).thenAnswer(
      (invocation) async {
        final index = invocation.positionalArguments[2] as int;
        final updated = invocation.positionalArguments[3] as WorkoutSet;
        return exercise.updateSet(index, updated);
      },
    );

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    const command = WatchCommand(
      id: 'cmd-dedupe',
      type: WatchCommandType.logSet,
      sessionId: 's1',
      exerciseId: 'ex-1',
      weight: 135,
      reps: 8,
      setCount: 1,
    );

    // First delivery applies the set.
    await handler.handleCommand(command);
    // Re-delivery (sendMessage failed -> transferUserInfo retry) is deduped:
    // the set is NOT applied twice, but the ack must still be (re-)recorded.
    await handler.handleCommand(command);

    // Only one set write (the dedup prevented a double-apply)...
    verify(
      () => repo.updateSetInExercise('s1', 'ex-1', any(), any()),
    ).called(1);
    // ...but the ack is present so the watch overlay clears on this delivery.
    final after = await handler.buildStatePayload();
    expect((after!['appliedCommandIds'] as List), contains('cmd-dedupe'));
  });

  test(
    'COMMAND-ACK (Fix 3 / #481): a CROSS-SESSION log_set for an UNKNOWN session is '
    'REJECTED on the early-return path (not falsely acked as applied)',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      // The ACTIVE session is s2, but the watch command targets the older s1.
      final session = WorkoutSession(
        id: 's2',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [],
      );

      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => session);
      // s1 no longer exists → the command cannot be retargeted, so it is rejected.
      when(() => repo.getWorkoutSession('s1')).thenAnswer((_) async => null);
      when(() => restTimer.status).thenReturn(TimerStatus.idle);
      when(() => restTimer.currentExerciseId).thenReturn(null);

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      await handler.handleCommand(
        const WatchCommand(
          id: 'cmd-foreign',
          type: WatchCommandType.logSet,
          sessionId: 's1',
          exerciseId: 'ex-old',
          weight: 135,
          reps: 8,
          setCount: 1,
        ),
      );

      // No set written (unknown session) and the id is REJECTED, not applied — so
      // the watch reverts its overlay and signals failure instead of a false
      // success (the previous contract falsely acked this drop).
      verifyNever(() => repo.updateSetInExercise(any(), any(), any(), any()));
      final after = await handler.buildStatePayload();
      expect((after!['rejectedCommandIds'] as List), contains('cmd-foreign'));
      expect(
        (after['appliedCommandIds'] as List?) ?? const [],
        isNot(contains('cmd-foreign')),
      );
    },
  );

  test('COMMAND-ACK ledger (Fix 4): endWorkout clears the applied-id ledger so '
      'finished ids do not leak into the next session', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    const exercise = WorkoutExercise(
      id: 'ex-1',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 60,
      sets: [WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: false)],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: [exercise],
    );

    // The session is active until endWorkout completes it, after which
    // getLatestActiveSession returns null (so the next build is no-session).
    var active = true;
    when(
      () => repo.getLatestActiveSession(),
    ).thenAnswer((_) async => active ? session : null);
    when(
      () => repo.getWorkoutSessions(limit: any(named: 'limit')),
    ).thenAnswer((_) async => const []);
    when(() => restTimer.status).thenReturn(TimerStatus.idle);
    when(() => restTimer.currentExerciseId).thenReturn(null);
    when(() => restTimer.stopTimer()).thenReturn(null);
    when(
      () => restTimer.startTimer(
        durationInSeconds: any(named: 'durationInSeconds'),
        exerciseId: any(named: 'exerciseId'),
        exerciseName: any(named: 'exerciseName'),
        notificationNextExerciseName: any(
          named: 'notificationNextExerciseName',
        ),
        notificationIsNextSet: any(named: 'notificationIsNextSet'),
      ),
    ).thenReturn(null);
    when(() => repo.updateSetInExercise('s1', 'ex-1', any(), any())).thenAnswer(
      (invocation) async {
        final index = invocation.positionalArguments[2] as int;
        final updated = invocation.positionalArguments[3] as WorkoutSet;
        return exercise.updateSet(index, updated);
      },
    );
    when(() => repo.completeWorkoutSession('s1')).thenAnswer((_) async {
      active = false;
      return session.copyWith(endTime: DateTime(2024, 1, 1, 1));
    });
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer(
      (invocation) async => invocation.positionalArguments[0] as WorkoutSession,
    );
    when(() => notifications.cancelWorkoutOngoing()).thenAnswer((_) async {});

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    // Log a set (records an ack), then end the workout (should clear ledger).
    await handler.handleCommand(
      const WatchCommand(
        id: 'cmd-pre-end',
        type: WatchCommandType.logSet,
        sessionId: 's1',
        exerciseId: 'ex-1',
        weight: 135,
        reps: 8,
        setCount: 1,
      ),
    );
    final beforeEnd = await handler.buildStatePayload();
    expect((beforeEnd!['appliedCommandIds'] as List), contains('cmd-pre-end'));

    await handler.handleCommand(
      const WatchCommand(
        id: 'cmd-end',
        type: WatchCommandType.endWorkout,
        sessionId: 's1',
      ),
    );

    // The ledger is cleared on teardown: the no-session payload carries no
    // leaked ids (omitted entirely when empty).
    final afterEnd = await handler.buildStatePayload();
    expect(afterEnd!['sessionId'], isNull);
    expect(
      afterEnd['appliedCommandIds'],
      isNull,
      reason: 'ledger cleared on endWorkout',
    );
  });

  test('rest payload uses per-exercise rest when idle', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    const exercise = WorkoutExercise(
      id: 'ex-1',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 60,
      sets: [WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: false)],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: [exercise],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    when(() => restTimer.status).thenReturn(TimerStatus.idle);
    when(
      () => restTimer.remainingSeconds,
    ).thenReturn(RestTimerService.defaultRestTime);
    when(
      () => restTimer.originalDurationSeconds,
    ).thenReturn(RestTimerService.defaultRestTime);
    when(() => restTimer.currentExerciseId).thenReturn(null);

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    final payload = await handler.buildStatePayload();
    final rest = payload?['rest'] as Map<String, dynamic>;
    expect(rest['targetSec'], 60);
    expect(rest['remainingSec'], 60);
  });

  test(
    'buildStatePayload includes numeric next-set weight, reps, and RPE',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      const exercise = WorkoutExercise(
        id: 'ex-1',
        exercise: Exercise(name: 'Bench Press', muscles: []),
        sets: [
          WorkoutSet(
            id: 'set-1',
            weight: 12.5,
            reps: 8,
            rpe: 8,
            isCompleted: false,
          ),
          WorkoutSet(id: 'set-2', weight: 12.5, reps: 8, isCompleted: false),
        ],
      );
      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: [exercise],
      );

      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => session);
      when(() => restTimer.status).thenReturn(TimerStatus.idle);
      when(
        () => restTimer.remainingSeconds,
      ).thenReturn(RestTimerService.defaultRestTime);
      when(
        () => restTimer.originalDurationSeconds,
      ).thenReturn(RestTimerService.defaultRestTime);
      when(() => restTimer.currentExerciseId).thenReturn(null);

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      final payload = await handler.buildStatePayload();
      expect(payload?['nextSetIndex'], 1);
      expect(payload?['nextSetTotal'], 2);
      expect(payload?['nextSetWeight'], 12.5);
      expect(payload?['nextSetReps'], 8);
      expect(payload?['nextSetRpe'], 8);
      expect(payload?['exerciseLoggingMode'], 'weightReps');
      expect(payload?['nextSetSummary'], '12.5×8');
      expect(payload?['upNextExerciseName'], 'Bench Press');
      expect(payload?['upNextIsCurrentExercise'], isTrue);
    },
  );

  test(
    'buildStatePayload labels cardio as distance-duration for watch UI',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      const exercise = WorkoutExercise(
        id: 'ex-cardio',
        exercise: Exercise(
          name: 'Treadmill',
          muscles: [],
          kind: ExerciseKind.cardio,
          loggingMode: ExerciseLoggingMode.distanceDuration,
        ),
        sets: [
          WorkoutSet(id: 'set-1', weight: 2.5, reps: 1200, isCompleted: false),
        ],
      );
      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: [exercise],
      );

      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => session);
      when(() => restTimer.status).thenReturn(TimerStatus.idle);
      when(
        () => restTimer.remainingSeconds,
      ).thenReturn(RestTimerService.defaultRestTime);
      when(
        () => restTimer.originalDurationSeconds,
      ).thenReturn(RestTimerService.defaultRestTime);
      when(() => restTimer.currentExerciseId).thenReturn(null);

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      final payload = await handler.buildStatePayload();
      expect(payload?['exerciseName'], 'Treadmill');
      expect(payload?['exerciseLoggingMode'], 'distanceDuration');
      expect(payload?['nextSetWeight'], 2.5);
      expect(payload?['nextSetReps'], 1200);
      expect(payload?['nextSetSummary'], '2.5 km × 20:00');
    },
  );

  test(
    'buildStatePayload skips quick-start history while a workout is active',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();
      final library = FakeExerciseRepository([
        const Exercise(name: 'Bench Press', muscles: ['chest']),
      ]);

      const exercise = WorkoutExercise(
        id: 'ex-1',
        exercise: Exercise(name: 'Bench Press', muscles: []),
        sets: [
          WorkoutSet(id: 'set-1', weight: 12.5, reps: 8, isCompleted: false),
        ],
      );
      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [exercise],
      );

      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => session);
      when(() => restTimer.status).thenReturn(TimerStatus.idle);
      when(
        () => restTimer.remainingSeconds,
      ).thenReturn(RestTimerService.defaultRestTime);
      when(
        () => restTimer.originalDurationSeconds,
      ).thenReturn(RestTimerService.defaultRestTime);
      when(() => restTimer.currentExerciseId).thenReturn(null);

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
        exerciseRepository: library,
      );

      final payload = await handler.buildStatePayload();
      expect(payload, isNotNull);
      expect(payload, isNot(contains('quickStarts')));
      verifyNever(() => repo.getWorkoutSessions(limit: any(named: 'limit')));
    },
  );

  test(
    'buildStatePayload keeps up-next on remaining work when selected exercise is complete',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      const exercise1 = WorkoutExercise(
        id: 'ex-1',
        exercise: Exercise(name: 'Bench Press', muscles: []),
        sets: [
          WorkoutSet(id: 'set-1', weight: 12.5, reps: 8, isCompleted: false),
        ],
      );
      const exercise2 = WorkoutExercise(
        id: 'ex-2',
        exercise: Exercise(name: 'Plank', muscles: []),
        sets: [WorkoutSet(id: 'set-2', weight: 0, reps: 30, isCompleted: true)],
      );
      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [exercise1, exercise2],
      );

      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => session);
      when(() => restTimer.status).thenReturn(TimerStatus.idle);
      when(
        () => restTimer.remainingSeconds,
      ).thenReturn(RestTimerService.defaultRestTime);
      when(
        () => restTimer.originalDurationSeconds,
      ).thenReturn(RestTimerService.defaultRestTime);
      when(() => restTimer.currentExerciseId).thenReturn(null);

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      await handler.buildStatePayload();

      await handler.handleCommand(
        const WatchCommand(
          id: 'nav-next',
          type: WatchCommandType.navNextExercise,
          sessionId: 's1',
        ),
      );

      final payload = await handler.buildStatePayload();
      expect(payload?['exerciseName'], 'Plank');
      expect(payload?['upNextExerciseName'], 'Bench Press');
      expect(payload?['upNextIsCurrentExercise'], isFalse);
    },
  );

  test(
    'buildStatePayload points up-next to next exercise on final set of current exercise',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      const exercise1 = WorkoutExercise(
        id: 'ex-1',
        exercise: Exercise(name: 'Bench Press', muscles: []),
        sets: [
          WorkoutSet(id: 'set-1', weight: 12.5, reps: 8, isCompleted: true),
          WorkoutSet(id: 'set-2', weight: 12.5, reps: 8, isCompleted: false),
        ],
      );
      const exercise2 = WorkoutExercise(
        id: 'ex-2',
        exercise: Exercise(name: 'Plank', muscles: []),
        sets: [
          WorkoutSet(id: 'set-3', weight: 0, reps: 30, isCompleted: false),
        ],
      );
      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [exercise1, exercise2],
      );

      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => session);
      when(() => restTimer.status).thenReturn(TimerStatus.idle);
      when(
        () => restTimer.remainingSeconds,
      ).thenReturn(RestTimerService.defaultRestTime);
      when(
        () => restTimer.originalDurationSeconds,
      ).thenReturn(RestTimerService.defaultRestTime);
      when(() => restTimer.currentExerciseId).thenReturn(null);

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      final payload = await handler.buildStatePayload();
      expect(payload?['exerciseName'], 'Bench Press');
      expect(payload?['upNextExerciseName'], 'Plank');
      expect(payload?['upNextIsCurrentExercise'], isFalse);
    },
  );

  test(
    'recording state without workout uuid does not mark capturedOnWatch',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [],
      );

      when(() => repo.getWorkoutSession('s1')).thenAnswer((_) async => session);
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments.first as WorkoutSession,
      );

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      const state = WatchHealthRecordingState(
        id: 'rec-1',
        sessionId: 's1',
        isRecording: true,
      );

      await handler.handleHealthRecordingState(state);

      final captured =
          verify(
                () => repo.updateWorkoutSession(captureAny(), markDirty: false),
              ).captured.single
              as WorkoutSession;
      expect(captured.capturedOnWatch, isFalse);
      expect(captured.watchCapturePending, isTrue);
      expect(captured.watchWorkoutUuid, isNull);
      handler.dispose();
    },
  );

  test('recording failure clears pending watch recording request', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: const [],
      watchRecordingRequested: true,
      watchCapturePending: true,
      watchCapturePendingAt: DateTime(2024),
    );

    when(() => repo.getWorkoutSession('s1')).thenAnswer((_) async => session);
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer(
      (invocation) async =>
          invocation.positionalArguments.first as WorkoutSession,
    );

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    const state = WatchHealthRecordingState(
      id: 'rec-denied',
      sessionId: 's1',
      isRecording: false,
      error: 'Health permissions denied',
    );

    await handler.handleHealthRecordingState(state);

    final captured =
        verify(
              () => repo.updateWorkoutSession(captureAny(), markDirty: false),
            ).captured.single
            as WorkoutSession;
    expect(captured.watchRecordingRequested, isFalse);
    expect(captured.watchRecordingActive, isFalse);
    expect(captured.watchCapturePending, isFalse);
    expect(captured.watchCapturePendingAt, isNull);
    expect(captured.capturedOnWatch, isFalse);
    expect(captured.watchWorkoutUuid, isNull);
    handler.dispose();
  });

  test(
    'recording failure falls back to latest active session when id is stale',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [],
        watchRecordingRequested: true,
        watchCapturePending: true,
        watchCapturePendingAt: DateTime(2024),
      );

      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => session);
      when(() => repo.getWorkoutSession('stale')).thenAnswer((_) async => null);
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments.first as WorkoutSession,
      );

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      const state = WatchHealthRecordingState(
        id: 'rec-stale-denied',
        sessionId: 'stale',
        isRecording: false,
        error: 'Health permissions denied',
      );

      await handler.handleHealthRecordingState(state);

      final captured =
          verify(
                () => repo.updateWorkoutSession(captureAny(), markDirty: false),
              ).captured.single
              as WorkoutSession;
      expect(captured.id, 's1');
      expect(captured.watchRecordingRequested, isFalse);
      expect(captured.watchRecordingActive, isFalse);
      expect(captured.watchCapturePending, isFalse);
      expect(captured.watchCapturePendingAt, isNull);
      handler.dispose();
    },
  );

  test(
    'recording failure for tombstoned stale session does not clear latest active request',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      when(() => repo.getWorkoutSession('stale')).thenAnswer((_) async => null);

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      )..markSessionCancelled('stale');

      const state = WatchHealthRecordingState(
        id: 'rec-stale-cancelled',
        sessionId: 'stale',
        isRecording: false,
        error: 'Health permissions denied',
      );

      await handler.handleHealthRecordingState(state);

      verifyNever(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      );
      verifyNever(() => repo.getLatestActiveSession());
      handler.dispose();
    },
  );

  test('plain recording stop keeps pending request state unchanged', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: const [],
      watchRecordingRequested: true,
    );

    when(() => repo.getWorkoutSession('s1')).thenAnswer((_) async => session);
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer(
      (invocation) async =>
          invocation.positionalArguments.first as WorkoutSession,
    );

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    const state = WatchHealthRecordingState(
      id: 'rec-plain-stop',
      sessionId: 's1',
      isRecording: false,
    );

    await handler.handleHealthRecordingState(state);

    final captured =
        verify(
              () => repo.updateWorkoutSession(captureAny(), markDirty: false),
            ).captured.single
            as WorkoutSession;
    expect(captured.watchRecordingRequested, isTrue);
    expect(captured.watchRecordingActive, isFalse);
    expect(captured.watchCapturePending, isTrue);
    handler.dispose();
  });

  test(
    'recording state marks completed clean workout dirty when watch fields change',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        endTime: DateTime(2024, 1, 1, 0, 30),
        exercises: const [],
        dirty: false,
      );

      when(() => repo.getWorkoutSession('s1')).thenAnswer((_) async => session);
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments.first as WorkoutSession,
      );

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      const state = WatchHealthRecordingState(
        id: 'rec-1b',
        sessionId: 's1',
        isRecording: false,
        hkWorkoutUuid: 'uuid-1',
        recordingStartMs: 123,
      );

      await handler.handleHealthRecordingState(state);

      verify(() => repo.updateWorkoutSession(any(), markDirty: true)).called(1);
    },
  );

  test('recording state with workout uuid marks capturedOnWatch', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: const [],
    );

    when(() => repo.getWorkoutSession('s1')).thenAnswer((_) async => session);
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer(
      (invocation) async =>
          invocation.positionalArguments.first as WorkoutSession,
    );

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    const state = WatchHealthRecordingState(
      id: 'rec-2',
      sessionId: 's1',
      isRecording: false,
      hkWorkoutUuid: 'uuid-1',
    );

    await handler.handleHealthRecordingState(state);

    final captured =
        verify(
              () => repo.updateWorkoutSession(captureAny(), markDirty: false),
            ).captured.single
            as WorkoutSession;
    expect(captured.capturedOnWatch, isTrue);
    expect(captured.watchWorkoutUuid, 'uuid-1');
  });

  test('watch-captured uuid triggers writeback reconciliation', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: const [],
      capturedOnWatch: false,
    );

    when(() => repo.getWorkoutSession('s1')).thenAnswer((_) async => session);
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer(
      (invocation) async =>
          invocation.positionalArguments.first as WorkoutSession,
    );

    final coordinator = MockWorkoutWritebackCoordinator();
    when(
      () => coordinator.handleWatchCapturedWorkout(
        sessionId: any(named: 'sessionId'),
        watchWorkoutUuid: any(named: 'watchWorkoutUuid'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => coordinator.handleWorkoutDeleted(any()),
    ).thenAnswer((_) async {});
    GetIt.instance.registerSingleton<WorkoutWritebackCoordinator>(coordinator);

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    const summary = WatchHealthSummary(
      id: 'health-3',
      sessionId: 's1',
      hkWorkoutUuid: 'uuid-1',
    );

    await handler.handleHealthSummary(summary);

    verify(
      () => coordinator.handleWatchCapturedWorkout(
        sessionId: 's1',
        watchWorkoutUuid: 'uuid-1',
      ),
    ).called(1);
    verifyNever(() => coordinator.handleWorkoutDeleted(any()));
  });

  test(
    'watch session creates a completed dirty workout when none exists',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      when(
        () => repo.getWorkoutSession('watch-1'),
      ).thenAnswer((_) async => null);
      when(() => repo.createWorkoutSession(any())).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments.first as WorkoutSession,
      );

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      const watchSession = WatchSession(
        id: 'watch-1',
        startedAtMs: 1000,
        endedAtMs: 1000 + 1800 * 1000,
        hkWorkoutUuid: 'hk-1',
        avgHr: 130,
        maxHr: 168,
        activeEnergyKcal: 250.5,
        durationSec: 1800,
        exercises: [
          WatchSessionExercise(
            name: 'Bench Press',
            exerciseId: 'bench-press',
            exerciseLoggingMode: 'weightReps',
            sets: [
              WatchSessionSet(weight: 100, reps: 5, completedAtMs: 2000),
              WatchSessionSet(weight: 100, reps: 5),
            ],
          ),
        ],
      );

      await handler.handleWatchSession(watchSession);

      final created =
          verify(() => repo.createWorkoutSession(captureAny())).captured.single
              as WorkoutSession;
      expect(created.id, 'watch-1');
      expect(created.isCompleted, isTrue);
      expect(created.dirty, isTrue);
      expect(created.capturedOnWatch, isTrue);
      expect(created.endTime, isNotNull);
      expect(created.watchWorkoutUuid, 'hk-1');
      expect(created.averageHeartRateBpm, 130);
      expect(created.maxHeartRateBpm, 168);
      expect(created.activeEnergyKilocalories, 250.5);
      expect(created.watchDurationSeconds, 1800);
      expect(created.exercises, hasLength(1));
      expect(created.exercises.first.exercise.name, 'Bench Press');
      expect(
        created.exercises.first.exercise.loggingMode,
        ExerciseLoggingMode.weightReps,
      );
      expect(created.exercises.first.sets, hasLength(2));
      expect(created.exercises.first.sets.every((s) => s.isCompleted), isTrue);
      expect(created.exercises.first.sets.first.weight, 100);
    },
  );

  test(
    'watch session preserves cardio logging mode from standalone payload',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      when(
        () => repo.getWorkoutSession('watch-cardio'),
      ).thenAnswer((_) async => null);
      when(() => repo.createWorkoutSession(any())).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments.first as WorkoutSession,
      );

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      const watchSession = WatchSession(
        id: 'watch-cardio',
        startedAtMs: 1000,
        endedAtMs: 2000,
        exercises: [
          WatchSessionExercise(
            name: 'Treadmill',
            exerciseId: 'treadmill',
            exerciseLoggingMode: 'distanceDuration',
            sets: [
              WatchSessionSet(weight: 2.5, reps: 1200, completedAtMs: 1500),
            ],
          ),
        ],
      );

      await handler.handleWatchSession(watchSession);

      final created =
          verify(() => repo.createWorkoutSession(captureAny())).captured.single
              as WorkoutSession;
      final exercise = created.exercises.single.exercise;
      expect(exercise.name, 'Treadmill');
      expect(exercise.kind, ExerciseKind.cardio);
      expect(exercise.loggingMode, ExerciseLoggingMode.distanceDuration);
      expect(created.exercises.single.sets.single.weight, 2.5);
      expect(created.exercises.single.sets.single.reps, 1200);
    },
  );

  test(
    'live watch add creates an editable tail set when the wrist exercise has no sets',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      final existing = WorkoutSession(
        id: 'watch-add-1',
        name: 'Workout',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000),
        exercises: const [],
        capturedOnWatch: true,
        watchRecordingStartMs: 1000,
        lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );
      when(
        () => repo.getWorkoutSession('watch-add-1'),
      ).thenAnswer((_) async => existing);
      WorkoutSession? stored;
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer((invocation) async {
        stored = invocation.positionalArguments.first as WorkoutSession;
        return stored!;
      });

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      const snapshot = WatchSession(
        id: 'watch-add-1',
        startedAtMs: 1000,
        inProgress: true,
        snapshotMs: 3000,
        exercises: [
          WatchSessionExercise(
            name: '21s Bicep Curl',
            exerciseId: 'ex-21s-curl',
            exerciseLoggingMode: 'weightReps',
          ),
        ],
      );

      await handler.handleWatchSession(snapshot);

      expect(stored, isNotNull);
      expect(stored!.exercises, hasLength(1));
      final exercise = stored!.exercises.single;
      expect(exercise.createdFromWatch, isTrue);
      expect(exercise.exercise.id, 'ex-21s-curl');
      expect(exercise.sets, hasLength(1));
      expect(exercise.sets.single.isCompleted, isFalse);
      expect(exercise.sets.single.weight, 0);
      expect(exercise.sets.single.reps, 0);
    },
  );

  test(
    'live watch merge preserves an explicit incomplete watch set without adding another tail',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      final existing = WorkoutSession(
        id: 'watch-draft-1',
        name: 'Workout',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000),
        exercises: const [],
        capturedOnWatch: true,
        watchRecordingStartMs: 1000,
        lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );
      when(
        () => repo.getWorkoutSession('watch-draft-1'),
      ).thenAnswer((_) async => existing);
      WorkoutSession? stored;
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer((invocation) async {
        stored = invocation.positionalArguments.first as WorkoutSession;
        return stored!;
      });

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      const snapshot = WatchSession(
        id: 'watch-draft-1',
        startedAtMs: 1000,
        inProgress: true,
        snapshotMs: 3000,
        exercises: [
          WatchSessionExercise(
            name: 'Treadmill',
            exerciseId: 'treadmill',
            exerciseLoggingMode: 'distanceDuration',
            sets: [WatchSessionSet(weight: 1.2, reps: 480, isCompleted: false)],
          ),
        ],
      );

      await handler.handleWatchSession(snapshot);

      expect(stored, isNotNull);
      final exercise = stored!.exercises.single;
      expect(
        exercise.exercise.loggingMode,
        ExerciseLoggingMode.distanceDuration,
      );
      expect(exercise.sets, hasLength(1));
      expect(exercise.sets.single.isCompleted, isFalse);
      expect(exercise.sets.single.completedAt, isNull);
      expect(exercise.sets.single.weight, 1.2);
      expect(exercise.sets.single.reps, 480);
    },
  );

  test(
    'finished watch sessions do not create an editable phantom set',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      when(
        () => repo.getWorkoutSession('watch-finished-empty'),
      ).thenAnswer((_) async => null);
      when(() => repo.createWorkoutSession(any())).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments.first as WorkoutSession,
      );

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      const watchSession = WatchSession(
        id: 'watch-finished-empty',
        startedAtMs: 1000,
        endedAtMs: 5000,
        exercises: [WatchSessionExercise(name: 'Squat', exerciseId: 'squat')],
      );

      await handler.handleWatchSession(watchSession);

      final created =
          verify(() => repo.createWorkoutSession(captureAny())).captured.single
              as WorkoutSession;
      expect(created.isCompleted, isTrue);
      expect(created.exercises.single.sets, isEmpty);
    },
  );

  test('watch session is idempotent: same payload twice creates one', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    WorkoutSession? stored;
    when(
      () => repo.getWorkoutSession('watch-1'),
    ).thenAnswer((_) async => stored);
    when(() => repo.createWorkoutSession(any())).thenAnswer((invocation) async {
      stored = invocation.positionalArguments.first as WorkoutSession;
      return stored!;
    });
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer((invocation) async {
      stored = invocation.positionalArguments.first as WorkoutSession;
      return stored!;
    });

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    const watchSession = WatchSession(
      id: 'watch-1',
      startedAtMs: 1000,
      endedAtMs: 5000,
      hkWorkoutUuid: 'hk-1',
      durationSec: 4,
      exercises: [
        WatchSessionExercise(
          name: 'Squat',
          sets: [WatchSessionSet(weight: 140, reps: 5)],
        ),
      ],
    );

    await handler.handleWatchSession(watchSession);
    await handler.handleWatchSession(watchSession);

    verify(() => repo.createWorkoutSession(any())).called(1);
    expect(stored, isNotNull);
    expect(stored!.id, 'watch-1');
    expect(stored!.exercises, hasLength(1));
  });

  test('live handoff: in-progress adopt, last-writer-wins, finish completes', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    WorkoutSession? stored;
    when(
      () => repo.getWorkoutSession('watch-9'),
    ).thenAnswer((_) async => stored);
    when(() => repo.createWorkoutSession(any())).thenAnswer((inv) async {
      stored = inv.positionalArguments.first as WorkoutSession;
      return stored!;
    });
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer((inv) async {
      stored = inv.positionalArguments.first as WorkoutSession;
      return stored!;
    });
    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    WatchSession snapshot(int ts, int sets) => WatchSession(
      id: 'watch-9',
      startedAtMs: 1000,
      inProgress: true,
      snapshotMs: ts,
      exercises: [
        WatchSessionExercise(
          name: 'Bench',
          sets: [
            for (var i = 0; i < sets; i++)
              const WatchSessionSet(weight: 60, reps: 8),
          ],
        ),
      ],
    );

    // Adopt the in-progress workout as a LIVE (not completed, not synced) session.
    await handler.handleWatchSession(snapshot(2000, 1));
    expect(stored, isNotNull);
    expect(stored!.isCompleted, isFalse);
    expect(stored!.endTime, isNull);
    expect(stored!.dirty, isFalse);

    // A newer snapshot updates it.
    await handler.handleWatchSession(snapshot(3000, 2));
    expect(stored!.exercises.first.sets, hasLength(3));
    expect(
      stored!.exercises.first.sets.take(2).every((s) => s.isCompleted),
      isTrue,
    );
    expect(stored!.exercises.first.sets.last.isCompleted, isFalse);

    // A stale snapshot (older ts) is ignored (last-writer-wins).
    await handler.handleWatchSession(snapshot(1500, 9));
    expect(stored!.exercises.first.sets, hasLength(3));

    // Finishing on the watch completes the adopted session. The finished payload
    // (guaranteed delivery) carries 3 sets even though the last live snapshot the
    // phone saw had 2 — the authoritative log replaces it (dropped-snapshot safety).
    await handler.handleWatchSession(
      const WatchSession(
        id: 'watch-9',
        startedAtMs: 1000,
        endedAtMs: 5000,
        snapshotMs: 6000,
        exercises: [
          WatchSessionExercise(
            name: 'Bench',
            sets: [
              WatchSessionSet(weight: 60, reps: 8),
              WatchSessionSet(weight: 60, reps: 8),
              WatchSessionSet(weight: 60, reps: 8),
            ],
          ),
        ],
      ),
    );
    expect(stored!.isCompleted, isTrue);
    expect(stored!.endTime, isNotNull);
    expect(stored!.exercises.first.sets, hasLength(3));
    // The completion transition (adopted clean -> finished) MUST mark dirty so the
    // finished watch workout actually syncs to the backend. Live in-progress updates
    // stay clean (markDirty:false); only the finish flips it to true. Without this the
    // completed workout stayed clean forever and the backend never got it.
    verify(() => repo.updateWorkoutSession(any(), markDirty: true)).called(1);
    // Adopted once, never duplicated.
    verify(() => repo.createWorkoutSession(any())).called(1);
  });

  test('watch session merges into existing session by hkWorkoutUuid', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    final existing = WorkoutSession(
      id: 'phone-1',
      name: 'Workout',
      startTime: DateTime(2024),
      endTime: DateTime(2024, 1, 1, 0, 30),
      exercises: const [],
      dirty: false,
      watchWorkoutUuid: 'hk-1',
    );

    when(() => repo.getWorkoutSession('watch-1')).thenAnswer((_) async => null);
    when(() => repo.getWorkoutSessions()).thenAnswer((_) async => [existing]);
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer(
      (invocation) async =>
          invocation.positionalArguments.first as WorkoutSession,
    );

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    const watchSession = WatchSession(
      id: 'watch-1',
      startedAtMs: 1000,
      endedAtMs: 5000,
      hkWorkoutUuid: 'hk-1',
      avgHr: 142,
      durationSec: 4,
    );

    await handler.handleWatchSession(watchSession);

    verifyNever(() => repo.createWorkoutSession(any()));
    final captured =
        verify(
              () => repo.updateWorkoutSession(captureAny(), markDirty: true),
            ).captured.single
            as WorkoutSession;
    expect(captured.id, 'phone-1');
    expect(captured.capturedOnWatch, isTrue);
    expect(captured.averageHeartRateBpm, 142);
    expect(captured.watchDurationSeconds, 4);
  });

  test(
    'watch summary with metrics and no uuid cancels queued writeback',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [],
      );

      when(() => repo.getWorkoutSession('s1')).thenAnswer((_) async => session);
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments.first as WorkoutSession,
      );

      final coordinator = MockWorkoutWritebackCoordinator();
      when(
        () => coordinator.cancelQueuedWriteback(any()),
      ).thenAnswer((_) async {});
      when(
        () => coordinator.handleWatchCapturedWorkout(
          sessionId: any(named: 'sessionId'),
          watchWorkoutUuid: any(named: 'watchWorkoutUuid'),
        ),
      ).thenAnswer((_) async {});
      GetIt.instance.registerSingleton<WorkoutWritebackCoordinator>(
        coordinator,
      );

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      const summary = WatchHealthSummary(
        id: 'health-4',
        sessionId: 's1',
        averageHeartRateBpm: 130,
      );

      await handler.handleHealthSummary(summary);

      verify(() => coordinator.cancelQueuedWriteback('s1')).called(1);
      verifyNever(
        () => coordinator.handleWatchCapturedWorkout(
          sessionId: any(named: 'sessionId'),
          watchWorkoutUuid: any(named: 'watchWorkoutUuid'),
        ),
      );
    },
  );
  test(
    'discard command deletes the session and does not complete it',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [],
      );

      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => session);
      when(() => restTimer.stopTimer()).thenReturn(null);
      when(() => repo.deleteWorkoutSession('s1')).thenAnswer((_) async {});
      when(() => notifications.cancelWorkoutOngoing()).thenAnswer((_) async {});

      final changes = <WorkoutChange>[];
      final events = WorkoutEventsService();
      final sub = events.stream.listen(changes.add);

      String? publishedSessionId;
      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
        workoutEvents: events,
        onPublishCancelled:
            ({required String sessionId, String? hkWorkoutUuid}) {
              publishedSessionId = sessionId;
            },
      );

      await handler.handleCommand(
        const WatchCommand(
          id: 'discard-1',
          type: WatchCommandType.discardWorkout,
          sessionId: 's1',
        ),
      );

      verify(() => repo.deleteWorkoutSession('s1')).called(1);
      verifyNever(() => repo.completeWorkoutSession(any()));
      verifyNever(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      );
      expect(publishedSessionId, 's1');

      await Future<void>.delayed(Duration.zero);
      expect(changes.any((c) => c.kind == WorkoutChangeKind.cancelled), isTrue);
      await sub.cancel();
      await events.dispose();
    },
  );

  test(
    'tombstoned watch session is not re-adopted (no resurrect after discard)',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      final session = WorkoutSession(
        id: 'watch-1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [],
      );

      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => session);
      when(() => restTimer.stopTimer()).thenReturn(null);
      when(() => repo.deleteWorkoutSession('watch-1')).thenAnswer((_) async {});
      when(() => notifications.cancelWorkoutOngoing()).thenAnswer((_) async {});

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      // Discard the session (tombstone it).
      await handler.handleCommand(
        const WatchCommand(
          id: 'discard-2',
          type: WatchCommandType.discardWorkout,
          sessionId: 'watch-1',
        ),
      );
      verify(() => repo.deleteWorkoutSession('watch-1')).called(1);

      // A late/queued watch snapshot for the same id arrives — must be ignored.
      const stale = WatchSession(
        id: 'watch-1',
        startedAtMs: 1000,
        inProgress: true,
        snapshotMs: 9999,
        exercises: [
          WatchSessionExercise(
            name: 'Bench',
            sets: [WatchSessionSet(weight: 60, reps: 8)],
          ),
        ],
      );
      await handler.handleWatchSession(stale);

      verifyNever(() => repo.createWorkoutSession(any()));
    },
  );

  test(
    'live merge: phone-added exercise survives a smaller watch snapshot',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      // Adopted, in-progress session with TWO exercises: one the watch knows
      // (Bench) and one the phone added (Curl) that the watch payload omits.
      final existing = WorkoutSession(
        id: 'watch-5',
        name: 'Workout',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000),
        exercises: const [
          WorkoutExercise(
            id: 'row-bench',
            exercise: Exercise(id: 'bench', name: 'Bench', muscles: []),
            sets: [
              WorkoutSet(id: 'b1', weight: 60, reps: 8, isCompleted: true),
            ],
          ),
          WorkoutExercise(
            id: 'row-curl',
            exercise: Exercise(id: 'curl', name: 'Curl', muscles: []),
            supersetGroupId: 'g1',
            supersetOrder: 1,
            sets: [WorkoutSet(id: 'c1', weight: 20, reps: 12)],
          ),
        ],
        lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      when(
        () => repo.getWorkoutSession('watch-5'),
      ).thenAnswer((_) async => existing);
      WorkoutSession? stored;
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer((inv) async {
        stored = inv.positionalArguments.first as WorkoutSession;
        return stored!;
      });

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      // Newer snapshot, but it only carries Bench (a stale/smaller view). The watch
      // echoes the phone ROW UUID ('row-bench') exactly as buildStatePayload publishes
      // it, so Bench reconciles via the primary row-id match.
      const snapshot = WatchSession(
        id: 'watch-5',
        startedAtMs: 1000,
        inProgress: true,
        snapshotMs: 3000,
        exercises: [
          WatchSessionExercise(
            name: 'Bench',
            exerciseId: 'row-bench',
            sets: [WatchSessionSet(weight: 60, reps: 8)],
          ),
        ],
      );

      await handler.handleWatchSession(snapshot);

      expect(stored, isNotNull);
      // The phone-only Curl exercise MUST survive (never shrink the list).
      expect(stored!.exercises, hasLength(2));
      final curl = stored!.exercises.firstWhere(
        (e) => e.exercise.name == 'Curl',
      );
      expect(curl.id, 'row-curl');
      expect(curl.supersetGroupId, 'g1');
      expect(curl.supersetOrder, 1);
      expect(curl.sets.single.id, 'c1');
    },
  );

  test('live merge: a genuine watch set-edit still applies', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    final existing = WorkoutSession(
      id: 'watch-6',
      name: 'Workout',
      startTime: DateTime.fromMillisecondsSinceEpoch(1000),
      exercises: const [
        WorkoutExercise(
          id: 'row-bench',
          exercise: Exercise(id: 'bench', name: 'Bench', muscles: []),
          sets: [WorkoutSet(id: 'b1', weight: 60, reps: 8, isCompleted: false)],
        ),
      ],
      lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    when(
      () => repo.getWorkoutSession('watch-6'),
    ).thenAnswer((_) async => existing);
    WorkoutSession? stored;
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer((inv) async {
      stored = inv.positionalArguments.first as WorkoutSession;
      return stored!;
    });

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    // The watch edits Bench: heavier weight + a second logged set. It echoes the
    // phone ROW UUID ('row-bench'), so the edit reconciles onto the phone instance.
    const snapshot = WatchSession(
      id: 'watch-6',
      startedAtMs: 1000,
      inProgress: true,
      snapshotMs: 3000,
      exercises: [
        WatchSessionExercise(
          name: 'Bench',
          exerciseId: 'row-bench',
          sets: [
            WatchSessionSet(weight: 70, reps: 6),
            WatchSessionSet(weight: 70, reps: 6),
          ],
        ),
      ],
    );

    await handler.handleWatchSession(snapshot);

    expect(stored, isNotNull);
    final bench = stored!.exercises.single;
    expect(bench.id, 'row-bench'); // stable identity preserved
    expect(bench.sets, hasLength(2)); // watch added a set
    expect(bench.sets.first.id, 'b1'); // reuse phone set id positionally
    expect(bench.sets.first.weight, 70); // genuine edit applied
    expect(bench.sets.first.reps, 6);
    expect(bench.sets.every((s) => s.isCompleted), isTrue);
  });

  test('live merge: same exercise twice mirrors both instances (no collapse)', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    // Phone has a single Bench block adopted live.
    final existing = WorkoutSession(
      id: 'watch-7',
      name: 'Workout',
      startTime: DateTime.fromMillisecondsSinceEpoch(1000),
      exercises: const [
        WorkoutExercise(
          id: 'row-bench',
          exercise: Exercise(id: 'bench', name: 'Bench', muscles: []),
          sets: [WorkoutSet(id: 'b1', weight: 60, reps: 8, isCompleted: true)],
        ),
      ],
      lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    when(
      () => repo.getWorkoutSession('watch-7'),
    ).thenAnswer((_) async => existing);
    WorkoutSession? stored;
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer((inv) async {
      stored = inv.positionalArguments.first as WorkoutSession;
      return stored!;
    });

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    // The watch reports the SAME exercise (Bench) TWICE — two separate blocks
    // with distinct work. The first echoes the phone ROW UUID ('row-bench') and
    // reconciles; the second is a genuine wrist-started instance with its OWN id
    // the phone has never seen. A by-key index would collapse the second onto the
    // first; the per-instance queue must mirror BOTH, in order.
    const snapshot = WatchSession(
      id: 'watch-7',
      startedAtMs: 1000,
      inProgress: true,
      snapshotMs: 3000,
      exercises: [
        WatchSessionExercise(
          name: 'Bench',
          exerciseId: 'row-bench',
          sets: [WatchSessionSet(weight: 60, reps: 8)],
        ),
        WatchSessionExercise(
          name: 'Bench',
          exerciseId: 'watch-bench-2',
          sets: [
            WatchSessionSet(weight: 80, reps: 3),
            WatchSessionSet(weight: 80, reps: 3),
          ],
        ),
      ],
    );

    await handler.handleWatchSession(snapshot);

    expect(stored, isNotNull);
    final benches = stored!.exercises
        .where((e) => e.exercise.name == 'Bench')
        .toList();
    // Both Bench instances are mirrored (not collapsed into one).
    expect(benches, hasLength(2));
    // First instance is the matched phone block (keeps its identity + set id).
    expect(benches[0].id, 'row-bench');
    expect(benches[0].sets.single.id, 'b1');
    expect(benches[0].sets.single.weight, 60);
    // Second instance is the appended watch-only block, in order, with its own
    // sets (the heavier 2-set block) — never dropped or merged into the first.
    expect(benches[1].id, isNot('row-bench'));
    expect(benches[1].sets, hasLength(3));
    expect(benches[1].sets.every((s) => s.weight == 80), isTrue);
    expect(benches[1].sets.take(2).every((s) => s.isCompleted), isTrue);
    expect(benches[1].sets.last.isCompleted, isFalse);
  });

  // --- #359 regression: real watch<->phone round-trip (id-namespace) ---------
  //
  // The phone publishes `exerciseId: selection.exercise.id` — the WorkoutExercise
  // ROW UUID — and the watch echoes it back as WatchSessionExercise.exerciseId. The
  // merge used to key the phone side on the LIBRARY id (`phoneEx.exercise.id`), so
  // the echoed row UUID never matched and the single exercise was appended as a
  // SECOND card. These tests reproduce the real round-trip (echo carries the row
  // UUID, NOT the library id).
  test('live merge: phone-driven exercise whose watch echo carries the ROW UUID '
      'collapses to ONE card (not two)', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    // Phone-driven single exercise. Library id ('reverse-fly') != row UUID
    // ('row-rfly'); the watch echoes the ROW UUID, exactly as buildStatePayload
    // publishes it.
    final existing = WorkoutSession(
      id: 'watch-rt-1',
      name: 'Workout',
      startTime: DateTime.fromMillisecondsSinceEpoch(1000),
      exercises: const [
        WorkoutExercise(
          id: 'row-rfly',
          exercise: Exercise(
            id: 'reverse-fly',
            name: 'Reverse Fly (Machine)',
            muscles: [],
          ),
          sets: [
            WorkoutSet(id: 's1', weight: 30, reps: 12, isCompleted: false),
          ],
        ),
      ],
      lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    when(
      () => repo.getWorkoutSession('watch-rt-1'),
    ).thenAnswer((_) async => existing);
    WorkoutSession? stored;
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer((inv) async {
      stored = inv.positionalArguments.first as WorkoutSession;
      return stored!;
    });

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    // The watch echoes the ROW UUID ('row-rfly'), NOT the library id — and marks
    // the set done. Before the fix this appended a second identical card.
    const snapshot = WatchSession(
      id: 'watch-rt-1',
      startedAtMs: 1000,
      inProgress: true,
      snapshotMs: 3000,
      exercises: [
        WatchSessionExercise(
          name: 'Reverse Fly (Machine)',
          exerciseId: 'row-rfly',
          sets: [WatchSessionSet(weight: 30, reps: 12)],
        ),
      ],
    );

    await handler.handleWatchSession(snapshot);

    expect(stored, isNotNull);
    // ONE card, not two. The phone instance keeps its identity + set id.
    expect(stored!.exercises, hasLength(1));
    final rfly = stored!.exercises.single;
    expect(rfly.id, 'row-rfly');
    expect(rfly.sets.single.id, 's1');
    expect(rfly.sets.single.isCompleted, isTrue); // watch edit applied
  });

  test('live merge: a genuine TWO-instance watch session (distinct ids the phone '
      'does not have) still yields TWO cards', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    // Phone has a single Bench block (row UUID 'row-bench-a').
    final existing = WorkoutSession(
      id: 'watch-rt-2',
      name: 'Workout',
      startTime: DateTime.fromMillisecondsSinceEpoch(1000),
      exercises: const [
        WorkoutExercise(
          id: 'row-bench-a',
          exercise: Exercise(id: 'bench', name: 'Bench', muscles: []),
          sets: [WorkoutSet(id: 'b1', weight: 60, reps: 8, isCompleted: true)],
        ),
      ],
      lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    when(
      () => repo.getWorkoutSession('watch-rt-2'),
    ).thenAnswer((_) async => existing);
    WorkoutSession? stored;
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer((inv) async {
      stored = inv.positionalArguments.first as WorkoutSession;
      return stored!;
    });

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    // The watch genuinely logs Bench as TWO separate instances with DISTINCT row
    // UUIDs. The first echoes the phone's row UUID (a phone-driven instance the
    // watch is mirroring); the second is a brand-new wrist-started instance the
    // phone has never seen. That second one must NOT be swallowed by the first —
    // #359's intended behavior (two genuine instances => two cards) must hold.
    const snapshot = WatchSession(
      id: 'watch-rt-2',
      startedAtMs: 1000,
      inProgress: true,
      snapshotMs: 3000,
      exercises: [
        WatchSessionExercise(
          name: 'Bench',
          exerciseId: 'row-bench-a',
          sets: [WatchSessionSet(weight: 60, reps: 8)],
        ),
        WatchSessionExercise(
          name: 'Bench',
          exerciseId: 'watch-bench-b',
          sets: [
            WatchSessionSet(weight: 100, reps: 3),
            WatchSessionSet(weight: 100, reps: 3),
          ],
        ),
      ],
    );

    await handler.handleWatchSession(snapshot);

    expect(stored, isNotNull);
    final benches = stored!.exercises
        .where((e) => e.exercise.name == 'Bench')
        .toList();
    // TWO cards — the genuine second instance is preserved, not collapsed.
    expect(benches, hasLength(2));
    // First is the matched phone instance (row-UUID hit): keeps identity + set id.
    expect(benches[0].id, 'row-bench-a');
    expect(benches[0].sets.single.id, 'b1');
    expect(benches[0].sets.single.weight, 60);
    // Second is the appended wrist-started instance with its own heavier work.
    expect(benches[1].id, isNot('row-bench-a'));
    expect(benches[1].sets, hasLength(3));
    expect(benches[1].sets.every((s) => s.weight == 100), isTrue);
    expect(benches[1].sets.take(2).every((s) => s.isCompleted), isTrue);
    expect(benches[1].sets.last.isCompleted, isFalse);
  });

  // --- #376 [P2] regression: name fallback must not eat a DISTINCT-id instance ----
  //
  // The name fallback exists only for an echo that DROPPED its id. A watch instance
  // carrying a NON-EMPTY id the phone doesn't have is a genuinely separate instance;
  // matching it by name would OVERWRITE the phone row's sets (the inverse of #359 —
  // a phone "Bench" silently swallowed by a distinct watch "Bench").
  test('live merge: a watch "Bench" with a DISTINCT non-empty id does NOT overwrite '
      'the same-named phone "Bench" — both instances are kept', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    // Phone already has a "Bench" instance (row UUID 'A') with its own logged set.
    final existing = WorkoutSession(
      id: 'watch-rt-4',
      name: 'Workout',
      startTime: DateTime.fromMillisecondsSinceEpoch(1000),
      exercises: const [
        WorkoutExercise(
          id: 'A',
          exercise: Exercise(id: 'bench', name: 'Bench', muscles: []),
          sets: [WorkoutSet(id: 'a1', weight: 60, reps: 8, isCompleted: true)],
        ),
      ],
      lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    when(
      () => repo.getWorkoutSession('watch-rt-4'),
    ).thenAnswer((_) async => existing);
    WorkoutSession? stored;
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer((inv) async {
      stored = inv.positionalArguments.first as WorkoutSession;
      return stored!;
    });

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    // The watch logs a SEPARATE "Bench" instance under its OWN id ('B') — NOT the
    // phone's row UUID 'A'. The id is non-empty and different, so the name fallback
    // must NOT consume the phone row; this is a genuine second instance to append.
    const snapshot = WatchSession(
      id: 'watch-rt-4',
      startedAtMs: 1000,
      inProgress: true,
      snapshotMs: 3000,
      exercises: [
        WatchSessionExercise(
          name: 'Bench',
          exerciseId: 'B',
          sets: [
            WatchSessionSet(weight: 100, reps: 3),
            WatchSessionSet(weight: 100, reps: 3),
          ],
        ),
      ],
    );

    await handler.handleWatchSession(snapshot);

    expect(stored, isNotNull);
    final benches = stored!.exercises
        .where((e) => e.exercise.name == 'Bench')
        .toList();
    // TWO "Bench" instances — the phone row is NOT overwritten/collapsed.
    expect(benches, hasLength(2));
    // The phone instance survives UNTOUCHED (identity, set id, and its 60x8 work).
    final phoneBench = benches.firstWhere((e) => e.id == 'A');
    expect(phoneBench.sets, hasLength(1));
    expect(phoneBench.sets.single.id, 'a1');
    expect(phoneBench.sets.single.weight, 60);
    expect(phoneBench.sets.single.reps, 8);
    // The wrist-started instance is appended with its own heavier work.
    final watchBench = benches.firstWhere((e) => e.id != 'A');
    expect(watchBench.sets, hasLength(3));
    expect(watchBench.sets.every((s) => s.weight == 100), isTrue);
    expect(watchBench.sets.take(2).every((s) => s.isCompleted), isTrue);
    expect(watchBench.sets.last.isCompleted, isFalse);
  });

  test('live merge: a watch exercise with a BLANK id reconciles to the same-named '
      'phone instance by name (echo that dropped its id)', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    // Phone has a single "Bench" instance (row UUID 'row-bench').
    final existing = WorkoutSession(
      id: 'watch-rt-5',
      name: 'Workout',
      startTime: DateTime.fromMillisecondsSinceEpoch(1000),
      exercises: const [
        WorkoutExercise(
          id: 'row-bench',
          exercise: Exercise(id: 'bench', name: 'Bench', muscles: []),
          sets: [WorkoutSet(id: 'b1', weight: 60, reps: 8, isCompleted: false)],
        ),
      ],
      lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    when(
      () => repo.getWorkoutSession('watch-rt-5'),
    ).thenAnswer((_) async => existing);
    WorkoutSession? stored;
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer((inv) async {
      stored = inv.positionalArguments.first as WorkoutSession;
      return stored!;
    });

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    // The echo DROPPED its id (null). The name fallback applies ONLY for a blank id,
    // so this reconciles onto the phone instance rather than appending a duplicate.
    const snapshot = WatchSession(
      id: 'watch-rt-5',
      startedAtMs: 1000,
      inProgress: true,
      snapshotMs: 3000,
      exercises: [
        WatchSessionExercise(
          name: 'Bench',
          sets: [WatchSessionSet(weight: 60, reps: 8)],
        ),
      ],
    );

    await handler.handleWatchSession(snapshot);

    expect(stored, isNotNull);
    // ONE card — reconciled by name onto the phone instance (no duplicate).
    expect(stored!.exercises, hasLength(1));
    final bench = stored!.exercises.single;
    expect(bench.id, 'row-bench'); // phone identity preserved
    expect(bench.sets.single.id, 'b1'); // phone set id reused positionally
    expect(bench.sets.single.isCompleted, isTrue); // watch edit applied
  });

  // --- #376 [P1] regression: a WATCH-OWNED/catalog exercise must not duplicate on -
  // each in-progress snapshot. `_createSessionFromWatch` mints a fresh phone ROW UUID
  // while the watch keeps re-sending the CATALOG id (never that UUID). Before the fix
  // the second snapshot found no row-UUID match and APPENDED the exercise again,
  // duplicating it on every live update. A watch-created row is now re-matched by its
  // `exercise.id` (the catalog id) so it reconciles instead of duplicating.
  test('live merge (END TO END): a watch-owned exercise (catalog id, no phone ROW UUID '
      'echo) adopted from a first snapshot stays ONE card on a SECOND snapshot with the '
      'same catalog id (no duplication on each update)', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();
    when(() => restTimer.stopTimer()).thenReturn(null);

    // A tiny in-memory store that round-trips through toMap/fromMap so the test
    // proves the `createdFromWatch` marker SURVIVES persistence (the merge reloads
    // `existing` from the repo on each snapshot).
    WorkoutSession? stored;
    WorkoutSession roundTrip(WorkoutSession session) {
      final map = session.toMap();
      final exercises = (map['exercises'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map(
            (em) => WorkoutExercise.fromMap(
              em,
              Exercise(
                id: em['exerciseId'] as String?,
                name: em['exerciseName'] as String,
                muscles: const [],
              ),
            ),
          )
          .toList();
      return WorkoutSession.fromMap(map, exercises);
    }

    when(
      () => repo.getWorkoutSession('watch-owned-1'),
    ).thenAnswer((_) async => stored);
    when(() => repo.getWorkoutSessions()).thenAnswer((_) async => const []);
    when(() => repo.createWorkoutSession(any())).thenAnswer((inv) async {
      stored = roundTrip(inv.positionalArguments.first as WorkoutSession);
      return stored!;
    });
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer((inv) async {
      stored = roundTrip(inv.positionalArguments.first as WorkoutSession);
      return stored!;
    });

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    // FIRST snapshot: the watch owns a catalog exercise (id 'cat-curl'); there is no
    // phone session yet, so this is adopted via _createSessionFromWatch — minting a
    // fresh phone ROW UUID with exercise.id == 'cat-curl' and createdFromWatch=true.
    const first = WatchSession(
      id: 'watch-owned-1',
      startedAtMs: 1000,
      inProgress: true,
      snapshotMs: 2000,
      exercises: [
        WatchSessionExercise(
          name: 'Bicep Curl',
          exerciseId: 'cat-curl',
          sets: [WatchSessionSet(weight: 20, reps: 10)],
        ),
      ],
    );
    await handler.handleWatchSession(first);

    expect(stored, isNotNull);
    expect(stored!.exercises, hasLength(1));
    final created = stored!.exercises.single;
    expect(created.createdFromWatch, isTrue);
    expect(created.exercise.id, 'cat-curl');
    // Sanity: the watch never echoed this phone ROW UUID — it only knows 'cat-curl'.
    expect(created.id, isNot('cat-curl'));
    final phoneRowUuid = created.id;

    // SECOND snapshot: the watch re-sends the SAME catalog id (it does not know the
    // phone ROW UUID) plus a newly completed set. This must RECONCILE onto the same
    // row, not append a second card.
    const second = WatchSession(
      id: 'watch-owned-1',
      startedAtMs: 1000,
      inProgress: true,
      snapshotMs: 3000,
      exercises: [
        WatchSessionExercise(
          name: 'Bicep Curl',
          exerciseId: 'cat-curl',
          sets: [
            WatchSessionSet(weight: 20, reps: 10),
            WatchSessionSet(weight: 20, reps: 10),
          ],
        ),
      ],
    );
    await handler.handleWatchSession(second);

    // STILL ONE card — the watch-owned row was re-matched by its catalog id.
    expect(stored!.exercises, hasLength(1));
    final reconciled = stored!.exercises.single;
    expect(reconciled.id, phoneRowUuid); // same phone row identity preserved
    expect(reconciled.exercise.id, 'cat-curl');
    expect(reconciled.createdFromWatch, isTrue); // marker survives the merge
    expect(reconciled.sets, hasLength(3)); // two completed sets + editable tail
    expect(reconciled.sets.take(2).every((s) => s.isCompleted), isTrue);
    expect(reconciled.sets.last.isCompleted, isFalse);
  });

  test(
    'live merge: an EXISTING watch-created row (createdFromWatch=true, exercise.id == '
    'catalog id) reconciles on a snapshot carrying that catalog id — stays ONE',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      // The phone already holds a wrist-minted row: fresh ROW UUID 'row-x', catalog id
      // 'cat-row' on exercise.id, createdFromWatch=true.
      final existing = WorkoutSession(
        id: 'watch-owned-2',
        name: 'Workout',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000),
        exercises: const [
          WorkoutExercise(
            id: 'row-x',
            exercise: Exercise(id: 'cat-row', name: 'Cable Row', muscles: []),
            sets: [
              WorkoutSet(id: 'r1', weight: 50, reps: 10, isCompleted: false),
            ],
            createdFromWatch: true,
          ),
        ],
        lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      when(
        () => repo.getWorkoutSession('watch-owned-2'),
      ).thenAnswer((_) async => existing);
      WorkoutSession? stored;
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer((inv) async {
        stored = inv.positionalArguments.first as WorkoutSession;
        return stored!;
      });

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      // The watch re-sends the CATALOG id 'cat-row' (NOT the phone ROW UUID 'row-x').
      const snapshot = WatchSession(
        id: 'watch-owned-2',
        startedAtMs: 1000,
        inProgress: true,
        snapshotMs: 3000,
        exercises: [
          WatchSessionExercise(
            name: 'Cable Row',
            exerciseId: 'cat-row',
            sets: [WatchSessionSet(weight: 50, reps: 10)],
          ),
        ],
      );
      await handler.handleWatchSession(snapshot);

      expect(stored, isNotNull);
      // ONE card — re-matched by exercise.id because the row is watch-created.
      expect(stored!.exercises, hasLength(1));
      final row = stored!.exercises.single;
      expect(row.id, 'row-x'); // identity preserved (not re-appended)
      expect(row.sets, hasLength(2));
      expect(row.sets.first.id, 'r1'); // phone set id reused
      expect(row.sets.first.isCompleted, isTrue); // watch edit applied
      expect(row.sets.last.isCompleted, isFalse);
    },
  );

  test(
    'live merge: a phone-completed tail on a watch-created row survives the next watch heartbeat',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      final existing = WorkoutSession(
        id: 'watch-owned-phone-tail',
        name: 'Workout',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000),
        exercises: const [
          WorkoutExercise(
            id: 'row-curl',
            exercise: Exercise(id: 'cat-curl', name: 'Curl', muscles: []),
            sets: [
              WorkoutSet(id: 'w1', weight: 20, reps: 10, isCompleted: true),
              WorkoutSet(
                id: 'phone-completed-tail',
                weight: 25,
                reps: 12,
                isCompleted: true,
              ),
            ],
            createdFromWatch: true,
          ),
        ],
        capturedOnWatch: true,
        watchRecordingStartMs: 1000,
        lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      when(
        () => repo.getWorkoutSession('watch-owned-phone-tail'),
      ).thenAnswer((_) async => existing);
      WorkoutSession? stored;
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer((inv) async {
        stored = inv.positionalArguments.first as WorkoutSession;
        return stored!;
      });

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      const snapshot = WatchSession(
        id: 'watch-owned-phone-tail',
        startedAtMs: 1000,
        inProgress: true,
        snapshotMs: 3000,
        exercises: [
          WatchSessionExercise(
            name: 'Curl',
            exerciseId: 'cat-curl',
            sets: [WatchSessionSet(weight: 20, reps: 10)],
          ),
        ],
      );

      await handler.handleWatchSession(snapshot);

      expect(stored, isNotNull);
      final sets = stored!.exercises.single.sets;
      expect(sets, hasLength(3));
      expect(sets[0].id, 'w1');
      expect(sets[0].isCompleted, isTrue);
      expect(sets[1].id, 'phone-completed-tail');
      expect(sets[1].weight, 25);
      expect(sets[1].reps, 12);
      expect(sets[1].isCompleted, isTrue);
      expect(sets[2].isCompleted, isFalse);
    },
  );

  test(
    'live merge: a stale same-index watch draft cannot uncomplete a phone-completed tail',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();
      final completedAt = DateTime.fromMillisecondsSinceEpoch(2500);

      final existing = WorkoutSession(
        id: 'watch-owned-same-index-draft',
        name: 'Workout',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000),
        exercises: [
          WorkoutExercise(
            id: 'row-curl',
            exercise: const Exercise(id: 'cat-curl', name: 'Curl', muscles: []),
            sets: [
              const WorkoutSet(
                id: 'w1',
                weight: 20,
                reps: 10,
                isCompleted: true,
              ),
              WorkoutSet(
                id: 'phone-completed-tail',
                weight: 25,
                reps: 12,
                isCompleted: true,
                completedAt: completedAt,
              ),
            ],
            createdFromWatch: true,
          ),
        ],
        capturedOnWatch: true,
        watchRecordingStartMs: 1000,
        lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      when(
        () => repo.getWorkoutSession('watch-owned-same-index-draft'),
      ).thenAnswer((_) async => existing);
      WorkoutSession? stored;
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer((inv) async {
        stored = inv.positionalArguments.first as WorkoutSession;
        return stored!;
      });

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      const snapshot = WatchSession(
        id: 'watch-owned-same-index-draft',
        startedAtMs: 1000,
        inProgress: true,
        snapshotMs: 3000,
        exercises: [
          WatchSessionExercise(
            name: 'Curl',
            exerciseId: 'cat-curl',
            sets: [
              WatchSessionSet(weight: 20, reps: 10),
              WatchSessionSet(weight: 0, reps: 0, isCompleted: false),
            ],
          ),
        ],
      );

      await handler.handleWatchSession(snapshot);

      expect(stored, isNotNull);
      final sets = stored!.exercises.single.sets;
      expect(sets, hasLength(3));
      expect(sets[1].id, 'phone-completed-tail');
      expect(sets[1].weight, 25);
      expect(sets[1].reps, 12);
      expect(sets[1].isCompleted, isTrue);
      expect(sets[1].completedAt, completedAt);
      expect(sets[2].isCompleted, isFalse);
    },
  );

  test(
    'live merge: a synthesized editable tail on a watch-created heartbeat does not churn',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      final existing = WorkoutSession(
        id: 'watch-owned-heartbeat-tail',
        name: 'Workout',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000),
        exercises: const [
          WorkoutExercise(
            id: 'row-curl',
            exercise: Exercise(id: 'cat-curl', name: 'Curl', muscles: []),
            sets: [
              WorkoutSet(id: 'w1', weight: 20, reps: 10, isCompleted: true),
              WorkoutSet(id: 'tail', weight: 20, reps: 10),
            ],
            createdFromWatch: true,
          ),
        ],
        capturedOnWatch: true,
        watchRecordingStartMs: 1000,
        lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      when(
        () => repo.getWorkoutSession('watch-owned-heartbeat-tail'),
      ).thenAnswer((_) async => existing);
      var updateCalls = 0;
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer((inv) async {
        updateCalls += 1;
        return inv.positionalArguments.first as WorkoutSession;
      });

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      const snapshot = WatchSession(
        id: 'watch-owned-heartbeat-tail',
        startedAtMs: 1000,
        inProgress: true,
        snapshotMs: 9000,
        exercises: [
          WatchSessionExercise(
            name: 'Curl',
            exerciseId: 'cat-curl',
            sets: [WatchSessionSet(weight: 20, reps: 10)],
          ),
        ],
      );

      await handler.handleWatchSession(snapshot);

      expect(updateCalls, 0);
    },
  );

  test('live merge: a watch-created row + a GENUINE second wrist instance of the SAME '
      'catalog id reconciles the first and APPENDS the second (case 3 holds for '
      'watch-created rows too)', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    final existing = WorkoutSession(
      id: 'watch-owned-3',
      name: 'Workout',
      startTime: DateTime.fromMillisecondsSinceEpoch(1000),
      exercises: const [
        WorkoutExercise(
          id: 'row-y',
          exercise: Exercise(id: 'cat-press', name: 'Press', muscles: []),
          sets: [WorkoutSet(id: 'p1', weight: 40, reps: 8, isCompleted: true)],
          createdFromWatch: true,
        ),
      ],
      lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    when(
      () => repo.getWorkoutSession('watch-owned-3'),
    ).thenAnswer((_) async => existing);
    WorkoutSession? stored;
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer((inv) async {
      stored = inv.positionalArguments.first as WorkoutSession;
      return stored!;
    });

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    // The watch logs Press TWICE under the SAME catalog id 'cat-press' — the existing
    // wrist instance plus a brand-new second block. The first reconciles onto 'row-y'
    // (consumed); the second is a genuine new instance that must APPEND.
    const snapshot = WatchSession(
      id: 'watch-owned-3',
      startedAtMs: 1000,
      inProgress: true,
      snapshotMs: 3000,
      exercises: [
        WatchSessionExercise(
          name: 'Press',
          exerciseId: 'cat-press',
          sets: [WatchSessionSet(weight: 40, reps: 8)],
        ),
        WatchSessionExercise(
          name: 'Press',
          exerciseId: 'cat-press',
          sets: [
            WatchSessionSet(weight: 80, reps: 3),
            WatchSessionSet(weight: 80, reps: 3),
          ],
        ),
      ],
    );
    await handler.handleWatchSession(snapshot);

    expect(stored, isNotNull);
    final presses = stored!.exercises
        .where((e) => e.exercise.name == 'Press')
        .toList();
    // TWO cards — the consumed-flag stops the catalog-id match from eating the genuine
    // second instance; it appends instead.
    expect(presses, hasLength(2));
    expect(
      presses[0].id,
      'row-y',
    ); // first reconciled onto the existing wrist row
    expect(presses[0].sets, hasLength(2));
    expect(presses[0].sets.first.weight, 40);
    expect(presses[0].sets.first.isCompleted, isTrue);
    expect(presses[0].sets.last.isCompleted, isFalse);
    expect(presses[1].id, isNot('row-y')); // second appended as a new instance
    expect(presses[1].sets, hasLength(3));
    expect(presses[1].sets.every((s) => s.weight == 80), isTrue);
    expect(presses[1].sets.take(2).every((s) => s.isCompleted), isTrue);
    expect(presses[1].sets.last.isCompleted, isFalse);
  });

  test('live merge: a PHONE-authored row (createdFromWatch=false) is NOT collapsed by a '
      'distinct non-empty watch id that merely equals its exercise.id — both kept '
      '(inverse-of-#359 guard for the catalog-id match)', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    // PHONE-authored row: ROW UUID 'row-sq', library id 'squat', createdFromWatch is
    // false (the phone published 'row-sq' to the watch as its exerciseId).
    final existing = WorkoutSession(
      id: 'phone-auth-1',
      name: 'Workout',
      startTime: DateTime.fromMillisecondsSinceEpoch(1000),
      exercises: const [
        WorkoutExercise(
          id: 'row-sq',
          exercise: Exercise(id: 'squat', name: 'Squat', muscles: []),
          sets: [WorkoutSet(id: 'q1', weight: 100, reps: 5, isCompleted: true)],
        ),
      ],
      lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    when(
      () => repo.getWorkoutSession('phone-auth-1'),
    ).thenAnswer((_) async => existing);
    WorkoutSession? stored;
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer((inv) async {
      stored = inv.positionalArguments.first as WorkoutSession;
      return stored!;
    });

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    // The watch sends a DISTINCT non-empty id that happens to equal the phone row's
    // library id 'squat' (NOT its ROW UUID 'row-sq'). Because the phone row is NOT
    // watch-created, the catalog-id match is GATED OFF, so this is a genuine separate
    // instance to append — the phone row must NOT be collapsed/overwritten (#359).
    const snapshot = WatchSession(
      id: 'phone-auth-1',
      startedAtMs: 1000,
      inProgress: true,
      snapshotMs: 3000,
      exercises: [
        WatchSessionExercise(
          name: 'Squat',
          exerciseId: 'squat',
          sets: [WatchSessionSet(weight: 140, reps: 2)],
        ),
      ],
    );
    await handler.handleWatchSession(snapshot);

    expect(stored, isNotNull);
    final squats = stored!.exercises
        .where((e) => e.exercise.name == 'Squat')
        .toList();
    // TWO cards — the phone-authored row is preserved untouched; the catalog-id match
    // is NOT allowed to collapse it.
    expect(squats, hasLength(2));
    final phoneSquat = squats.firstWhere((e) => e.id == 'row-sq');
    expect(phoneSquat.sets.single.id, 'q1');
    expect(phoneSquat.sets.single.weight, 100); // untouched
    final watchSquat = squats.firstWhere((e) => e.id != 'row-sq');
    expect(watchSquat.sets, hasLength(2));
    expect(watchSquat.sets.first.weight, 140);
    expect(watchSquat.sets.first.isCompleted, isTrue);
    expect(watchSquat.sets.last.isCompleted, isFalse);
  });

  test('live merge: an unchanged watch heartbeat (only lastUpdatedAt would bump) '
      'does NOT persist or emit (lag guard)', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    // Already watch-captured, with watchRecordingStartMs set: a heartbeat that
    // carries identical exercises is a pure no-op for the user.
    final existing = WorkoutSession(
      id: 'watch-rt-3',
      name: 'Workout',
      startTime: DateTime.fromMillisecondsSinceEpoch(1000),
      exercises: const [
        WorkoutExercise(
          id: 'row-bench',
          exercise: Exercise(id: 'bench', name: 'Bench', muscles: []),
          sets: [WorkoutSet(id: 'b1', weight: 60, reps: 8, isCompleted: true)],
        ),
      ],
      capturedOnWatch: true,
      watchRecordingStartMs: 1000,
      lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    when(
      () => repo.getWorkoutSession('watch-rt-3'),
    ).thenAnswer((_) async => existing);
    var updateCalls = 0;
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer((inv) async {
      updateCalls += 1;
      return inv.positionalArguments.first as WorkoutSession;
    });

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    // Newer snapshot time, but the exercise/set content is identical (heartbeat).
    // The watch echoes the row UUID, so it still reconciles to the SAME content.
    const snapshot = WatchSession(
      id: 'watch-rt-3',
      startedAtMs: 1000,
      inProgress: true,
      snapshotMs: 9000,
      exercises: [
        WatchSessionExercise(
          name: 'Bench',
          exerciseId: 'row-bench',
          sets: [WatchSessionSet(weight: 60, reps: 8)],
        ),
      ],
    );

    await handler.handleWatchSession(snapshot);

    // No content delta -> no persist, no churn.
    expect(updateCalls, 0);
  });

  test(
    'live merge: a no-op heartbeat advances the staleness WATERMARK, so a later '
    'OUT-OF-ORDER older-but-changed snapshot is REJECTED (does not overwrite)',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      // T0 = 2000: adopted watch session, one Bench set. lastUpdatedAt stays at
      // T0 across the run because the only accepted event below is a SUPPRESSED
      // no-op heartbeat (which never re-stamps the persisted lastUpdatedAt). The
      // staleness floor must therefore be carried by the in-memory watermark.
      var stored = WorkoutSession(
        id: 'watch-wm-1',
        name: 'Workout',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000),
        exercises: const [
          WorkoutExercise(
            id: 'row-bench',
            exercise: Exercise(id: 'bench', name: 'Bench', muscles: []),
            sets: [
              WorkoutSet(id: 'b1', weight: 60, reps: 8, isCompleted: true),
            ],
          ),
        ],
        capturedOnWatch: true,
        watchRecordingStartMs: 1000,
        lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      when(
        () => repo.getWorkoutSession('watch-wm-1'),
      ).thenAnswer((_) async => stored);
      var updateCalls = 0;
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer((inv) async {
        updateCalls += 1;
        stored = inv.positionalArguments.first as WorkoutSession;
        return stored;
      });

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      // T2 = 9000: unchanged heartbeat (echoes the same row UUID + identical set).
      // Emission is SUPPRESSED (lag/churn fix) but the watermark must advance to T2.
      const heartbeatT2 = WatchSession(
        id: 'watch-wm-1',
        startedAtMs: 1000,
        inProgress: true,
        snapshotMs: 9000,
        exercises: [
          WatchSessionExercise(
            name: 'Bench',
            exerciseId: 'row-bench',
            sets: [WatchSessionSet(weight: 60, reps: 8)],
          ),
        ],
      );
      await handler.handleWatchSession(heartbeatT2);
      expect(updateCalls, 0); // suppressed no-op

      // T1 = 5000 (T0 < T1 < T2): a DELAYED OLDER snapshot whose content CHANGED
      // (a second set). Its snapMs still beats the persisted lastUpdatedAt (T0=2000),
      // so without the watermark it would be accepted and OVERWRITE the newer state
      // the watch already advanced past at T2. The watermark (now T2=9000) rejects it.
      const olderChangedT1 = WatchSession(
        id: 'watch-wm-1',
        startedAtMs: 1000,
        inProgress: true,
        snapshotMs: 5000,
        exercises: [
          WatchSessionExercise(
            name: 'Bench',
            exerciseId: 'row-bench',
            sets: [
              WatchSessionSet(weight: 60, reps: 8),
              WatchSessionSet(weight: 60, reps: 8),
            ],
          ),
        ],
      );
      await handler.handleWatchSession(olderChangedT1);

      // Rejected as stale: no persist, content unchanged (still one set).
      expect(updateCalls, 0);
      expect(stored.exercises.single.sets, hasLength(1));
    },
  );

  test(
    'add_exercise with a named exercise adds the real library exercise (not a blank)',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();
      final library = FakeExerciseRepository([
        const Exercise(
          id: 'ex-pullup',
          slug: 'pull-up',
          name: 'Pull Up',
          muscles: ['Back'],
        ),
        const Exercise(id: 'ex-squat', name: 'Squat', muscles: ['Legs']),
      ]);

      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [],
      );
      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => session);
      when(
        () => repo.getPreviousExerciseSets(
          any(),
          exerciseSlug: any(named: 'exerciseSlug'),
        ),
      ).thenAnswer((_) async => null);
      WorkoutSession? stored;
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer((inv) async {
        stored = inv.positionalArguments.first as WorkoutSession;
        return stored!;
      });

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
        exerciseRepository: library,
      );

      const command = WatchCommand(
        id: 'add-named-1',
        type: WatchCommandType.addExercise,
        sessionId: 's1',
        exerciseId: 'ex-pullup',
        exerciseName: 'Pull Up',
        exerciseSlug: 'pull-up',
      );

      await handler.handleCommand(command);

      expect(stored, isNotNull);
      final added = stored!.exercises.single;
      expect(added.exercise.name, 'Pull Up');
      expect(added.exercise.id, 'ex-pullup');
      expect(added.exercise.slug, 'pull-up');
      expect(added.createdFromWatch, isTrue);
      verify(() => repo.updateWorkoutSession(any(), markDirty: true)).called(1);
    },
  );

  test(
    'watch-added exercise reconciles with its live snapshot instead of duplicating',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();
      final library = FakeExerciseRepository([
        const Exercise(
          id: 'ex-pullup',
          slug: 'pull-up',
          name: 'Pull Up',
          muscles: ['Back'],
        ),
      ]);

      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [],
      );
      WorkoutSession? stored = session;
      when(() => repo.getLatestActiveSession()).thenAnswer((_) async => stored);
      when(() => repo.getWorkoutSession('s1')).thenAnswer((_) async => stored);
      when(
        () => repo.getPreviousExerciseSets(
          any(),
          exerciseSlug: any(named: 'exerciseSlug'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer((inv) async {
        stored = inv.positionalArguments.first as WorkoutSession;
        return stored!;
      });

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
        exerciseRepository: library,
      );

      await handler.handleCommand(
        const WatchCommand(
          id: 'add-named-2',
          type: WatchCommandType.addExercise,
          sessionId: 's1',
          exerciseId: 'ex-pullup',
          exerciseName: 'Pull Up',
          exerciseSlug: 'pull-up',
        ),
      );

      final added = stored!.exercises.single;
      expect(added.createdFromWatch, isTrue);

      await handler.handleWatchSession(
        WatchSession(
          id: 's1',
          startedAtMs: session.startTime.millisecondsSinceEpoch,
          inProgress: true,
          snapshotMs: DateTime.now()
              .add(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
          exercises: const [
            WatchSessionExercise(
              name: 'Pull Up',
              exerciseId: 'ex-pullup',
              sets: [WatchSessionSet(weight: 10, reps: 5, isCompleted: true)],
            ),
          ],
        ),
      );

      expect(stored!.exercises, hasLength(1));
      expect(stored!.exercises.single.exercise.name, 'Pull Up');
      expect(stored!.exercises.single.createdFromWatch, isTrue);
      expect(stored!.exercises.single.sets.first.isCompleted, isTrue);
      expect(stored!.exercises.single.sets.first.weight, 10);
      expect(stored!.exercises.single.sets.first.reps, 5);
    },
  );

  test(
    'add_exercise with no name falls back to a blank Exercise N placeholder',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      final session = WorkoutSession(
        id: 's1',
        name: 'Workout',
        startTime: DateTime(2024),
        exercises: const [],
      );
      when(
        () => repo.getLatestActiveSession(),
      ).thenAnswer((_) async => session);
      WorkoutSession? stored;
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer((inv) async {
        stored = inv.positionalArguments.first as WorkoutSession;
        return stored!;
      });

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      const command = WatchCommand(
        id: 'add-blank-1',
        type: WatchCommandType.addExercise,
        sessionId: 's1',
      );

      await handler.handleCommand(command);

      expect(stored, isNotNull);
      expect(stored!.exercises.single.exercise.name, 'Exercise 1');
      expect(stored!.exercises.single.createdFromWatch, isTrue);
    },
  );

  test(
    'exercise_catalog_request replies with a bounded, named catalog slice',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();
      final library = FakeExerciseRepository([
        const Exercise(
          id: 'ex-bench',
          slug: 'bench-press',
          name: 'Bench Press',
          muscles: ['Chest', 'Triceps'],
        ),
        const Exercise(
          id: 'ex-treadmill',
          slug: 'treadmill',
          name: 'Treadmill',
          muscles: ['Cardio'],
          kind: ExerciseKind.cardio,
          loggingMode: ExerciseLoggingMode.distanceDuration,
        ),
        const Exercise(
          id: 'ex-ohp',
          name: 'Overhead Press',
          muscles: ['Shoulders'],
        ),
      ]);

      when(() => repo.getLatestActiveSession()).thenAnswer((_) async => null);

      Map<String, dynamic>? sent;
      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
        exerciseRepository: library,
        onSendCatalogResponse: (payload) => sent = payload,
      );

      const command = WatchCommand(
        id: 'cat-req-1',
        type: WatchCommandType.exerciseCatalogRequest,
        searchQuery: 'press',
      );

      await handler.handleCommand(command);

      expect(sent, isNotNull);
      expect(sent!['type'], 'exercise_catalog');
      expect(sent!['searchQuery'], 'press');
      final exercises = sent!['exercises'] as List;
      expect(exercises, isNotEmpty);
      final names = exercises.map((e) => (e as Map)['name'] as String).toList();
      expect(names, contains('Bench Press'));
      expect(names, contains('Overhead Press'));
      final bench = exercises.cast<Map>().firstWhere(
        (e) => e['name'] == 'Bench Press',
      );
      expect(bench['id'], 'ex-bench');
      expect(bench['slug'], 'bench-press');
      expect(bench['exerciseLoggingMode'], 'weightReps');

      await handler.handleCommand(
        const WatchCommand(
          id: 'cat-req-2',
          type: WatchCommandType.exerciseCatalogRequest,
          searchQuery: 'treadmill',
        ),
      );
      final cardioExercises = sent!['exercises'] as List;
      final treadmill = cardioExercises.cast<Map>().firstWhere(
        (e) => e['name'] == 'Treadmill',
      );
      expect(treadmill['exerciseLoggingMode'], 'distanceDuration');
    },
  );

  // --- RPE lane: new watch payloads carry RPE while legacy payloads still
  // preserve phone-entered values during snapshot reconciliation. -------------
  test('WatchCommand parses RPE and the explicit clear marker', () {
    final logged = WatchCommand.tryParse({
      'id': 'rpe-log',
      'type': 'log_set',
      'rpe': 9,
    });
    final cleared = WatchCommand.tryParse({
      'id': 'rpe-clear',
      'type': 'log_set',
      'clearRpe': true,
    });

    expect(logged?.rpe, 9);
    expect(logged?.clearRpe, isFalse);
    expect(cleared?.rpe, isNull);
    expect(cleared?.clearRpe, isTrue);

    final legacySnapshotSet = WatchSessionSet.tryParse({
      'weight': 80,
      'reps': 8,
    });
    final clearedSnapshotSet = WatchSessionSet.tryParse({
      'weight': 80,
      'reps': 8,
      'rpeKnown': true,
    });
    expect(legacySnapshotSet?.rpeKnown, isFalse);
    expect(clearedSnapshotSet?.rpeKnown, isTrue);
    expect(clearedSnapshotSet?.rpe, isNull);
  });

  test('logSet can explicitly clear a prefilled RPE', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();
    const exercise = WorkoutExercise(
      id: 'ex-rpe-clear',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 60,
      sets: [
        WorkoutSet(
          id: 'set-rpe-clear',
          weight: 80,
          reps: 8,
          rpe: 8,
          isCompleted: false,
        ),
      ],
    );
    final session = WorkoutSession(
      id: 'rpe-clear-session',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: const [exercise],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    when(() => restTimer.status).thenReturn(TimerStatus.idle);
    when(() => restTimer.currentExerciseId).thenReturn(null);
    when(
      () => repo.updateSetInExercise(
        'rpe-clear-session',
        'ex-rpe-clear',
        0,
        any(),
      ),
    ).thenAnswer((_) async => exercise);

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    await handler.handleCommand(
      const WatchCommand(
        id: 'clear-rpe-command',
        type: WatchCommandType.logSet,
        sessionId: 'rpe-clear-session',
        exerciseId: 'ex-rpe-clear',
        weight: 80,
        reps: 8,
        clearRpe: true,
      ),
    );

    final updated =
        verify(
              () => repo.updateSetInExercise(
                'rpe-clear-session',
                'ex-rpe-clear',
                0,
                captureAny(),
              ),
            ).captured.single
            as WorkoutSet;
    expect(updated.rpe, isNull);
  });

  test('legacy logSet without RPE fields preserves a prefilled RPE', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();
    const exercise = WorkoutExercise(
      id: 'ex-rpe-legacy',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 60,
      sets: [
        WorkoutSet(
          id: 'set-rpe-legacy',
          weight: 80,
          reps: 8,
          rpe: 8,
          isCompleted: false,
        ),
      ],
    );
    final session = WorkoutSession(
      id: 'rpe-legacy-session',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: const [exercise],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    when(() => restTimer.status).thenReturn(TimerStatus.idle);
    when(() => restTimer.currentExerciseId).thenReturn(null);
    when(
      () => repo.updateSetInExercise(
        'rpe-legacy-session',
        'ex-rpe-legacy',
        0,
        any(),
      ),
    ).thenAnswer((_) async => exercise);

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    await handler.handleCommand(
      const WatchCommand(
        id: 'legacy-no-rpe-command',
        type: WatchCommandType.logSet,
        sessionId: 'rpe-legacy-session',
        exerciseId: 'ex-rpe-legacy',
        weight: 80,
        reps: 8,
      ),
    );

    final updated =
        verify(
              () => repo.updateSetInExercise(
                'rpe-legacy-session',
                'ex-rpe-legacy',
                0,
                captureAny(),
              ),
            ).captured.single
            as WorkoutSet;
    expect(updated.rpe, 8);
  });

  test('watch session snapshot imports a watch-entered RPE', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();
    WorkoutSession? stored;

    when(
      () => repo.getWorkoutSession('watch-rpe-import'),
    ).thenAnswer((_) async => stored);
    when(() => repo.createWorkoutSession(any())).thenAnswer((invocation) async {
      stored = invocation.positionalArguments.first as WorkoutSession;
      return stored!;
    });

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    await handler.handleWatchSession(
      const WatchSession(
        id: 'watch-rpe-import',
        startedAtMs: 1000,
        inProgress: true,
        snapshotMs: 2000,
        exercises: [
          WatchSessionExercise(
            name: 'Bench Press',
            sets: [WatchSessionSet(weight: 80, reps: 8, rpe: 9)],
          ),
        ],
      ),
    );

    expect(stored?.exercises.single.sets.first.rpe, 9);
  });
  test('addSet does not inherit RPE from the last set', () async {
    final repo = MockWorkoutRepository();
    final restTimer = MockRestTimerService();
    final notifications = MockNotificationService();

    const exercise = WorkoutExercise(
      id: 'ex-1',
      exercise: Exercise(name: 'Bench Press', muscles: []),
      restTimerSeconds: 60,
      sets: [
        WorkoutSet(
          id: 'set-1',
          weight: 100,
          reps: 5,
          rpe: 8,
          isCompleted: true,
        ),
      ],
    );
    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime(2024),
      exercises: [exercise],
    );

    when(() => repo.getLatestActiveSession()).thenAnswer((_) async => session);
    when(() => restTimer.status).thenReturn(TimerStatus.idle);
    when(() => repo.addSetToExercise('s1', 'ex-1', any())).thenAnswer((
      invocation,
    ) async {
      final set = invocation.positionalArguments[2] as WorkoutSet;
      return exercise.addSet(set);
    });

    final handler = WatchBridgeHandler(
      workoutRepository: repo,
      restTimerService: restTimer,
      notificationService: notifications,
    );

    const command = WatchCommand(
      id: 'cmd-add-set-rpe',
      type: WatchCommandType.addSet,
      sessionId: 's1',
      exerciseId: 'ex-1',
    );

    await handler.handleCommand(command);

    final appended =
        verify(
              () => repo.addSetToExercise('s1', 'ex-1', captureAny()),
            ).captured.single
            as WorkoutSet;
    expect(appended.rpe, isNull);
  });

  test(
    'live snapshot preserves legacy RPE omission and applies explicit clear',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      WorkoutSession? stored;
      when(
        () => repo.getWorkoutSession('watch-rpe'),
      ).thenAnswer((_) async => stored);
      when(() => repo.createWorkoutSession(any())).thenAnswer((inv) async {
        stored = inv.positionalArguments.first as WorkoutSession;
        return stored!;
      });
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer((inv) async {
        stored = inv.positionalArguments.first as WorkoutSession;
        return stored!;
      });

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      WatchSession snapshot(int ts) => WatchSession(
        id: 'watch-rpe',
        startedAtMs: 1000,
        inProgress: true,
        snapshotMs: ts,
        exercises: const [
          WatchSessionExercise(
            name: 'Bench',
            sets: [WatchSessionSet(weight: 60, reps: 8)],
          ),
        ],
      );

      // Adopt the in-progress workout (one set, watch-minted).
      await handler.handleWatchSession(snapshot(2000));
      expect(stored!.exercises.first.sets.first.weight, 60);

      // Simulate the user logging RPE on the phone for that set.
      final ex0 = stored!.exercises.first;
      stored = stored!.copyWith(
        exercises: [
          ex0.copyWith(sets: [ex0.sets.first.copyWith(rpe: 9)]),
        ],
      );

      // A newer snapshot reconciles the set; the watch sends no RPE, so the
      // phone-entered value must survive instead of being wiped.
      await handler.handleWatchSession(snapshot(3000));
      expect(stored!.exercises.first.sets.first.rpe, 9);

      // A current Watch marks RPE as known. With no numeric value, that is an
      // intentional clear and must not be mistaken for a legacy omission.
      await handler.handleWatchSession(
        const WatchSession(
          id: 'watch-rpe',
          startedAtMs: 1000,
          inProgress: true,
          snapshotMs: 4000,
          exercises: [
            WatchSessionExercise(
              name: 'Bench',
              sets: [WatchSessionSet(weight: 60, reps: 8, rpeKnown: true)],
            ),
          ],
        ),
      );
      expect(stored!.exercises.first.sets.first.rpe, isNull);
    },
  );

  test(
    'finish handoff preserves phone-entered rpe on the adopted session',
    () async {
      final repo = MockWorkoutRepository();
      final restTimer = MockRestTimerService();
      final notifications = MockNotificationService();

      WorkoutSession? stored;
      when(
        () => repo.getWorkoutSession('watch-rpe-finish'),
      ).thenAnswer((_) async => stored);
      when(() => repo.createWorkoutSession(any())).thenAnswer((inv) async {
        stored = inv.positionalArguments.first as WorkoutSession;
        return stored!;
      });
      when(
        () => repo.updateWorkoutSession(
          any(),
          markDirty: any(named: 'markDirty'),
        ),
      ).thenAnswer((inv) async {
        stored = inv.positionalArguments.first as WorkoutSession;
        return stored!;
      });

      final handler = WatchBridgeHandler(
        workoutRepository: repo,
        restTimerService: restTimer,
        notificationService: notifications,
      );

      // Adopt the in-progress watch workout (one set).
      await handler.handleWatchSession(
        const WatchSession(
          id: 'watch-rpe-finish',
          startedAtMs: 1000,
          inProgress: true,
          snapshotMs: 2000,
          exercises: [
            WatchSessionExercise(
              name: 'Bench',
              sets: [WatchSessionSet(weight: 60, reps: 8, isCompleted: false)],
            ),
          ],
        ),
      );

      // Phone logs RPE on that set.
      final ex0 = stored!.exercises.first;
      stored = stored!.copyWith(
        exercises: [
          ex0.copyWith(sets: [ex0.sets.first.copyWith(rpe: 9)]),
        ],
      );

      // The watch FINISHES — guaranteed-delivery final payload, no RPE on the
      // wire. The completion handoff must MERGE (preserve phone RPE), not rebuild
      // a fresh tree that wipes it.
      await handler.handleWatchSession(
        const WatchSession(
          id: 'watch-rpe-finish',
          startedAtMs: 1000,
          inProgress: false,
          snapshotMs: 4000,
          endedAtMs: 5000,
          exercises: [
            WatchSessionExercise(
              name: 'Bench',
              sets: [WatchSessionSet(weight: 60, reps: 8)],
            ),
          ],
        ),
      );

      expect(stored!.isCompleted, isTrue);
      expect(stored!.exercises.first.sets.first.rpe, 9);
    },
  );
}
