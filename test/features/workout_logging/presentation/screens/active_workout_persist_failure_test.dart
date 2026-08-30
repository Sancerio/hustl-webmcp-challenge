import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/notification_service.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/webmcp/active_workout_web_mcp_controller.dart';
import 'package:hustl_app/core/webmcp/web_mcp_access_gate.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/data/repositories/mock_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/services/inactivity_service.dart';
import 'package:hustl_app/features/workout_logging/domain/services/rest_timer_service.dart';
import 'package:hustl_app/features/workout_logging/presentation/screens/active_workout_screen.dart';

/// A repository that can be made to fail `updateWorkoutSession` on demand so the
/// screen's serialized persist chain records a failure instead of swallowing it.
/// It records every session it was asked to persist so tests can assert the full
/// current UI truth was written (retry / paused-flush).
class _FlakyRepo extends MockWorkoutRepository {
  bool failUpdates = false;
  final List<WorkoutSession> updates = [];

  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession session, {
    bool markDirty = true,
  }) async {
    if (failUpdates) {
      throw Exception('simulated storage write failure');
    }
    updates.add(session);
    return super.updateWorkoutSession(session, markDirty: markDirty);
  }
}

class _DeferredSessionRepo extends _FlakyRepo {
  final Completer<WorkoutSession?> load = Completer<WorkoutSession?>();
  WorkoutSession? currentSession;
  int readCount = 0;

  @override
  Future<WorkoutSession?> getWorkoutSession(String id) {
    readCount += 1;
    if (readCount == 1) return load.future;
    return Future.value(currentSession);
  }
}

/// A no-op notification service so mounting the screen never touches platform
/// notification channels.
class _NoopNotificationService implements NotificationService {
  @override
  Future<void> cancelWorkoutOngoing() async {}
  @override
  Future<void> showAutoLoggedProposal({
    required String id,
    required bool isFood,
    required String body,
  }) async {}
  @override
  Future<void> handleAppLaunchNotification() async {}
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
  }) async {}
  @override
  Future<void> scheduleRestComplete(
    int seconds, {
    String? exerciseName,
    bool isNextSet = false,
  }) async {}
  @override
  Future<void> cancelRestComplete() async {}
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
  Future<bool> isRestCompleteNotificationPending() async => false;
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

Widget _routedApp({required String sessionId}) {
  final router = GoRouter(
    initialLocation: '/active',
    routes: [
      GoRoute(
        path: '/active',
        builder: (context, state) => ActiveWorkoutScreen(sessionId: sessionId),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  final getIt = GetIt.instance;
  late _FlakyRepo repo;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    await prefs.setHapticsEnabled(false);
    getIt.registerSingleton<PreferencesService>(prefs);
    repo = _FlakyRepo();
    getIt.registerSingleton<WorkoutRepository>(repo);
    getIt.registerSingleton<NotificationService>(_NoopNotificationService());
    getIt.registerSingleton<RestTimerService>(
      RestTimerService(notificationService: getIt<NotificationService>()),
    );
    getIt.registerFactory<InactivityService>(
      () => InactivityService(
        notificationService: getIt<NotificationService>(),
        preferencesService: getIt<PreferencesService>(),
      ),
    );
  });

  tearDown(() async {
    await getIt.reset(dispose: true);
  });

  Future<String> seedSession() async {
    final seeded = await repo.createWorkoutSession(
      WorkoutSession(
        id: 'sess-1',
        name: 'Workout',
        startTime: DateTime.now(),
        exercises: const [
          WorkoutExercise(
            id: 'a',
            exercise: Exercise(name: 'Bench Press', muscles: ['chest']),
            sets: [WorkoutSet(id: 'a-s0', weight: 40, reps: 8)],
          ),
        ],
      ),
    );
    return seeded.id;
  }

  const bannerText = "Changes couldn't be saved";

  // Edit the set via the reps keyboard's RPE picker — a plain onSetUpdated that
  // routes through the screen's persist chain WITHOUT completing the set (a set
  // completion auto-starts the rest timer, whose periodic ticker would keep
  // `pumpAndSettle` from ever settling). [rirKey1] -> rpe 9, [rirKey2] -> rpe 8.
  Future<void> editRpe(WidgetTester tester, String rirKey) async {
    await tester.tap(find.byKey(const Key('repsField-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(rirKey)));
    await tester.pumpAndSettle();
  }

  testWidgets('a failed set-persist surfaces the unsaved-changes banner', (
    tester,
  ) async {
    final id = await seedSession();
    await tester.pumpWidget(_routedApp(sessionId: id));
    await tester.pumpAndSettle();

    expect(find.text(bannerText), findsNothing);

    // The next write fails; the edit updates the session optimistically and
    // enqueues the (failing) persist.
    repo.failUpdates = true;
    await editRpe(tester, 'rirKey2');

    expect(find.text(bannerText), findsOneWidget);
  });

  testWidgets(
    'tapping Retry re-persists the full current session and clears the banner',
    (tester) async {
      final id = await seedSession();
      await tester.pumpWidget(_routedApp(sessionId: id));
      await tester.pumpAndSettle();

      repo.failUpdates = true;
      await editRpe(tester, 'rirKey2');
      expect(find.text(bannerText), findsOneWidget);

      // Heal the repository, then retry. The retry writes the current UI truth
      // (a full-session snapshot carrying the edited set).
      repo.failUpdates = false;
      repo.updates.clear();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text(bannerText), findsNothing);
      expect(repo.updates, isNotEmpty);
      final persisted = repo.updates.last;
      expect(persisted.id, 'sess-1');
      expect(persisted.exercises.single.sets.single.rpe, 8);
    },
  );

  testWidgets('a later successful edit clears the banner without Retry', (
    tester,
  ) async {
    final id = await seedSession();
    await tester.pumpWidget(_routedApp(sessionId: id));
    await tester.pumpAndSettle();

    repo.failUpdates = true;
    await editRpe(tester, 'rirKey2');
    expect(find.text(bannerText), findsOneWidget);

    // The repository heals; a subsequent edit persists a newer full-session
    // snapshot, which supersedes the failed write and clears the banner. The
    // reps keyboard is already open on this set, so change the RPE directly.
    repo.failUpdates = false;
    await tester.tap(find.byKey(const Key('rirKey1')));
    await tester.pumpAndSettle();

    expect(find.text(bannerText), findsNothing);
  });

  testWidgets(
    'backgrounding commits an open keyboard draft into the persisted session',
    (tester) async {
      final id = await seedSession();
      await tester.pumpWidget(_routedApp(sessionId: id));
      await tester.pumpAndSettle();

      // Open the reps keyboard and type a new value WITHOUT committing it (no
      // Done / Next / tap-outside) — it lives only as an in-progress draft.
      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('repsKeyboardDigit7')));
      await tester.pump();

      repo.updates.clear();

      // Backgrounding must flush the draft (close(commit: true)) and queue a
      // full-session persist.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();

      expect(repo.updates, isNotEmpty);
      final persisted = repo.updates.last;
      expect(persisted.exercises.single.sets.single.reps, 7);
    },
  );

  testWidgets('a load crossing an account generation never binds WebMCP', (
    tester,
  ) async {
    await getIt.unregister<WorkoutRepository>();
    final deferredRepo = _DeferredSessionRepo();
    getIt.registerSingleton<WorkoutRepository>(deferredRepo);
    final gate = WebMcpAccessGate()..setReady(true);
    final controller = ActiveWorkoutWebMcpController(accessGate: gate);
    getIt.registerSingleton<WebMcpAccessGate>(gate);
    getIt.registerSingleton<ActiveWorkoutWebMcpController>(
      controller,
      dispose: (value) => value.dispose(),
    );

    await tester.pumpWidget(_routedApp(sessionId: 'account-a-session'));
    await tester.pump();

    final nextGeneration = gate.closeForTransition();
    gate.openIfCurrent(nextGeneration);
    deferredRepo.load.complete(
      WorkoutSession(
        id: 'account-a-session',
        name: 'Account A workout',
        startTime: DateTime.now(),
        exercises: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.getActiveWorkout(), {
      'status': 'unavailable',
      'code': 'no_active_workout',
    });
    expect(deferredRepo.readCount, greaterThanOrEqualTo(2));
  });

  testWidgets('a cold load rebinds after production auth settlement', (
    tester,
  ) async {
    await getIt.unregister<WorkoutRepository>();
    final deferredRepo = _DeferredSessionRepo();
    getIt.registerSingleton<WorkoutRepository>(deferredRepo);
    final gate = WebMcpAccessGate();
    final controller = ActiveWorkoutWebMcpController(accessGate: gate);
    getIt.registerSingleton<WebMcpAccessGate>(gate);
    getIt.registerSingleton<ActiveWorkoutWebMcpController>(
      controller,
      dispose: (value) => value.dispose(),
    );

    await tester.pumpWidget(_routedApp(sessionId: 'cold-session'));
    await tester.pump();
    final session = WorkoutSession(
      id: 'cold-session',
      name: 'Cold start workout',
      startTime: DateTime.now(),
      exercises: const [],
    );
    deferredRepo.currentSession = session;
    deferredRepo.load.complete(session);
    await tester.pumpAndSettle();
    expect(controller.getActiveWorkout()['status'], 'unavailable');

    final settledGeneration = gate.closeForTransition();
    gate.openIfCurrent(settledGeneration);
    await tester.pumpAndSettle();

    expect(controller.getActiveWorkout()['status'], 'ready');
    expect(controller.getActiveWorkout()['sessionId'], 'cold-session');
    expect(deferredRepo.readCount, greaterThanOrEqualTo(2));
  });
}
