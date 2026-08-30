import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/notification_service.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/watch_bridge/watch_bridge_service.dart';
import 'package:hustl_app/core/navigation/workout_minimize_sheet_controller.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/exercise_library/domain/repositories/exercise_repository.dart';
import 'package:hustl_app/features/workout_logging/data/repositories/mock_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/services/rest_timer_service.dart';
import 'package:hustl_app/features/workout_logging/domain/services/inactivity_service.dart';
import 'package:hustl_app/features/workout_logging/presentation/screens/active_workout_screen.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/active_workout_header.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/active/live_elapsed_label.dart';
import 'package:hustl_app/features/workout_templates/domain/repositories/template_repository.dart';
import '../../../../test_utils/template_repository_fake.dart';

class _SpyNotificationService implements NotificationService {
  @override
  Future<void> showAutoLoggedProposal({
    required String id,
    required bool isFood,
    required String body,
  }) async {}

  @override
  Future<void> handleAppLaunchNotification() async {}
  int requests = 0;
  int workoutOngoingCalls = 0;
  DateTime? startTime;
  bool workoutOngoingCanceled = false;

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
  Future<bool> ensurePermissionsForWorkout() async {
    requests++;
    return true;
  }

  @override
  Future<void> showRestOngoing(int seconds, {String? exerciseName}) async {}

  @override
  Future<void> cancelRestOngoing() async {}

  @override
  Future<void> showWorkoutOngoing({
    required DateTime startTime,
    String? currentExerciseName,
  }) async {
    workoutOngoingCalls++;
    this.startTime = startTime;
  }

  @override
  Future<void> cancelWorkoutOngoing() async {
    workoutOngoingCanceled = true;
  }

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

class _FakeExerciseRepository implements ExerciseRepository {
  final _exercises = const [
    Exercise(name: 'Push Up', muscles: ['chest']),
    Exercise(
      name: 'Plank',
      muscles: ['core'],
      loggingMode: ExerciseLoggingMode.durationOnly,
    ),
  ];

  @override
  Future<List<Exercise>> getAllExercises() async => _exercises;

  @override
  Future<List<Exercise>> getExercisesByMuscle(String muscle) async => _exercises
      .where((exercise) => exercise.muscles.contains(muscle))
      .toList();

  @override
  Future<List<Exercise>> searchExercises(String query) async => _exercises
      .where(
        (exercise) => exercise.name.toLowerCase().contains(query.toLowerCase()),
      )
      .toList();

  @override
  Future<String?> regenerateThumbnail(Exercise exercise) async => null;

  @override
  Future<String?> regenerateThumbnailDebug(
    Exercise exercise, {
    String? steerImageUrl,
    String? steerImageDataUrl,
  }) async => null;

  @override
  Future<Exercise> generateOverviewDebug(Exercise exercise) async => exercise;

  @override
  Future<Exercise> generateHowToDebug(Exercise exercise) async => exercise;

  @override
  Future<List<Exercise>> getCustomExercises() async => const [];

  @override
  Future<List<Exercise>> getSharedExercises({String? search}) async => const [];

  @override
  Future<Exercise> addCustomExercise(Exercise exercise) async => exercise;

  @override
  Future<void> removeCustomExercise(Exercise exercise) async {}
}

class _SpyWatchBridgeService extends WatchBridgeService {
  _SpyWatchBridgeService({required PreferencesService preferences})
    : super(preferences: preferences);

  int stopRequests = 0;
  int startRequests = 0;
  int publishRequests = 0;
  int completionRequests = 0;
  String? lastSessionId;
  String? lastStartedSessionId;

  @override
  bool get isEnabled => true;

  @override
  void schedulePublish() {
    publishRequests += 1;
  }

  @override
  Future<void> requestStopRecording({required String sessionId}) async {
    stopRequests += 1;
    lastSessionId = sessionId;
  }

  @override
  Future<void> requestStartRecording({required String sessionId}) async {
    startRequests += 1;
    lastStartedSessionId = sessionId;
  }

  @override
  void cancelWorkout({
    required String sessionId,
    String? hkWorkoutUuid,
    WatchCancelReason reason = WatchCancelReason.discarded,
  }) {
    if (reason == WatchCancelReason.completed) {
      completionRequests += 1;
    }
    lastSessionId = sessionId;
  }
}

class _FakeWatchBridgeService extends WatchBridgeService {
  _FakeWatchBridgeService({required PreferencesService preferences})
    : super(preferences: preferences);

  final List<String> stopRequests = [];

  @override
  Future<void> requestStopRecording({required String sessionId}) async {
    stopRequests.add(sessionId);
  }
}

class _AutoPop<T> extends StatelessWidget {
  const _AutoPop(this.result);

  final T result;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Navigator.of(context).canPop()) {
        context.pop<T>(result);
      }
    });
    return const Scaffold(body: SizedBox.shrink());
  }
}

/// Pumps a bounded number of frames. Use after actions that leave a periodic
/// animation running (e.g. the rest timer started when a set is completed via
/// the reps keyboard's "Done"), where `pumpAndSettle` would wait forever.
Future<void> _pumpFrames(
  WidgetTester tester, [
  int frames = 24,
  Duration step = const Duration(milliseconds: 50),
]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    getIt.registerSingleton<PreferencesService>(prefs);
    getIt.registerLazySingleton<WorkoutRepository>(
      () => MockWorkoutRepository(),
    );
    final spy = _SpyNotificationService();
    getIt.registerSingleton<NotificationService>(spy);
    getIt.registerSingleton<RestTimerService>(
      RestTimerService(notificationService: getIt<NotificationService>()),
    );
    getIt.registerFactory<InactivityService>(
      () => InactivityService(
        notificationService: getIt<NotificationService>(),
        preferencesService: getIt<PreferencesService>(),
      ),
    );
    getIt.registerSingleton<TemplateRepository>(TemplateRepositoryFake());
    getIt.registerLazySingleton<ExerciseRepository>(
      () => _FakeExerciseRepository(),
    );
  });

  tearDown(() async {
    await getIt.reset(dispose: true);
  });

  testWidgets('requests notification permission when workout starts', (
    tester,
  ) async {
    final spy = getIt<NotificationService>() as _SpyNotificationService;

    await tester.pumpWidget(const MaterialApp(home: ActiveWorkoutScreen()));

    // Let initState complete
    await tester.pump();

    expect(spy.requests, 1);
  });

  testWidgets(
    'reduced-motion mobile layout does not reserve an empty drag rail',
    (tester) async {
      final sheetController = WorkoutMinimizeSheetController(
        canDrag: (context) =>
            !(MediaQuery.maybeDisableAnimationsOf(context) ?? false),
        dragBy: (_, __) {},
        release: (_, __) async {},
        cancel: (_) async {},
        minimize: (_) async {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 780),
              disableAnimations: true,
            ),
            child: WorkoutMinimizeSheetScope(
              controller: sheetController,
              child: const ActiveWorkoutScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
      expect(appBar.toolbarHeight, 56);
      expect(find.byKey(const Key('workoutMinimizeDragHandle')), findsNothing);
    },
  );

  testWidgets('haptic feedback on workout completion when enabled', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: ActiveWorkoutScreen(
          initialExercises: [
            {'name': 'Push Up'},
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(ActiveWorkoutScreen));
    await (state as dynamic).finishWorkoutForTest();

    final vibrates = calls
        .where((call) => call.method == 'HapticFeedback.vibrate')
        .toList();
    expect(vibrates.length, 1);
    expect(
      vibrates.first.arguments,
      anyOf(
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.vibrate',
      ),
    );
  });

  testWidgets('no haptic feedback on workout completion when disabled', (
    tester,
  ) async {
    await getIt<PreferencesService>().setHapticsEnabled(false);

    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: ActiveWorkoutScreen(
          initialExercises: [
            {'name': 'Push Up'},
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(ActiveWorkoutScreen));
    await (state as dynamic).finishWorkoutForTest();

    final vibrates = calls.where(
      (call) => call.method == 'HapticFeedback.vibrate',
    );
    expect(vibrates, isEmpty);
  });

  testWidgets(
    'finish workout requests watch stop when watch recording is active',
    (tester) async {
      final repo = getIt<WorkoutRepository>() as MockWorkoutRepository;
      final prefs = getIt<PreferencesService>();
      await prefs.setHapticsEnabled(false);
      final watchBridge = _SpyWatchBridgeService(preferences: prefs);
      getIt.registerSingleton<WatchBridgeService>(watchBridge);

      final existing = await repo.createWorkoutSession(
        WorkoutSession(
          id: 'watch-active-session',
          name: 'Session',
          startTime: DateTime(2024, 1, 1),
          exercises: const [
            WorkoutExercise(
              id: 'ex1',
              exercise: Exercise(name: 'Push Up', muscles: ['chest']),
              sets: [
                WorkoutSet(id: 'set1', weight: 0, reps: 12, isCompleted: true),
              ],
            ),
          ],
          watchRecordingActive: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: ActiveWorkoutScreen(sessionId: existing.id)),
      );
      await tester.pumpAndSettle();

      final state = tester.state(find.byType(ActiveWorkoutScreen));
      await (state as dynamic).finishWorkoutForTest();

      expect(watchBridge.stopRequests, 1);
      expect(watchBridge.lastSessionId, existing.id);
    },
  );

  testWidgets(
    'phone set completion schedules an event-driven Watch state update',
    (tester) async {
      final prefs = getIt<PreferencesService>();
      final watchBridge = _SpyWatchBridgeService(preferences: prefs);
      getIt.registerSingleton<WatchBridgeService>(watchBridge);

      await tester.pumpWidget(
        const MaterialApp(
          home: ActiveWorkoutScreen(
            initialExercises: [
              {'name': 'Push Up', 'sets': 1},
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      watchBridge.publishRequests = 0;

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.tap(fields.at(1));
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('repsKeyboardClear')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('repsKeyboardDigit8')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('repsKeyboardDone')));
      await _pumpFrames(tester);

      expect(watchBridge.publishRequests, greaterThanOrEqualTo(1));

      getIt<RestTimerService>().stopTimer();
      await tester.pump();
    },
  );

  testWidgets('Send again issues a distinct Watch recording start command', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final prefs = getIt<PreferencesService>();
    final watchBridge = _SpyWatchBridgeService(preferences: prefs);
    getIt.registerSingleton<WatchBridgeService>(watchBridge);
    final repo = getIt<WorkoutRepository>() as MockWorkoutRepository;
    final existing = await repo.createWorkoutSession(
      WorkoutSession(
        id: 'watch-retry-session',
        name: 'Session',
        startTime: DateTime(2024, 1, 1),
        exercises: const [],
        watchRecordingRequested: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ActiveWorkoutScreen(sessionId: existing.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 23));
    await tester.pump(const Duration(milliseconds: 400));
    debugDefaultTargetPlatformOverride = null;

    final sendAgain = find.widgetWithText(FilledButton, 'Send again');
    expect(sendAgain, findsOneWidget);
    await tester.tap(sendAgain);
    await tester.pump();

    expect(watchBridge.startRequests, 1);
    expect(watchBridge.lastStartedSessionId, existing.id);
  });

  testWidgets(
    'finishing a phone-only workout clears a connected passive Watch',
    (tester) async {
      final prefs = getIt<PreferencesService>();
      final watchBridge = _SpyWatchBridgeService(preferences: prefs);
      getIt.registerSingleton<WatchBridgeService>(watchBridge);
      final repo = getIt<WorkoutRepository>() as MockWorkoutRepository;
      final existing = await repo.createWorkoutSession(
        WorkoutSession(
          id: 'phone-only-session',
          name: 'Session',
          startTime: DateTime(2024, 1, 1),
          exercises: const [],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: ActiveWorkoutScreen(sessionId: existing.id)),
      );
      await tester.pumpAndSettle();

      final state = tester.state(find.byType(ActiveWorkoutScreen));
      await (state as dynamic).finishWorkoutForTest();

      expect(watchBridge.stopRequests, 0);
      expect(watchBridge.completionRequests, 1);
      expect(watchBridge.lastSessionId, existing.id);
    },
  );

  testWidgets(
    'initializes ongoing notification when loading existing session',
    (tester) async {
      final repo = getIt<WorkoutRepository>() as MockWorkoutRepository;
      final existing = await repo.createWorkoutSession(
        WorkoutSession(
          id: 'sess1',
          name: 'Session',
          startTime: DateTime(2024, 1, 1),
          exercises: const [],
        ),
      );
      final spy = getIt<NotificationService>() as _SpyNotificationService;

      await tester.pumpWidget(
        MaterialApp(home: ActiveWorkoutScreen(sessionId: existing.id)),
      );
      await tester.pump();

      expect(spy.workoutOngoingCalls, 1);
      expect(spy.startTime, existing.startTime);
    },
  );

  testWidgets('finishing a watch-recorded workout requests watch stop first', (
    tester,
  ) async {
    final repo = getIt<WorkoutRepository>() as MockWorkoutRepository;
    final prefs = getIt<PreferencesService>();
    await prefs.setHapticsEnabled(false);
    final watchBridge = _FakeWatchBridgeService(preferences: prefs);
    getIt.registerSingleton<WatchBridgeService>(watchBridge);

    final existing = await repo.createWorkoutSession(
      WorkoutSession(
        id: 'watch-recorded-session',
        name: 'Session',
        startTime: DateTime(2024, 1, 1),
        exercises: const [],
        watchRecordingActive: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: ActiveWorkoutScreen(sessionId: existing.id)),
    );
    await tester.pump();

    final state = tester.state(find.byType(ActiveWorkoutScreen));
    await (state as dynamic).finishWorkoutForTest();

    expect(watchBridge.stopRequests, [existing.id]);
  });

  test('rest timer stops when stopped', () {
    final service = getIt<RestTimerService>();
    service.startTimer();
    expect(service.status, TimerStatus.running);
    service.stopTimer();
    expect(service.status, TimerStatus.idle);
  });

  testWidgets('rest timer stops when workout is canceled', (tester) async {
    final router = GoRouter(
      initialLocation: '/active',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SizedBox()),
        GoRoute(
          path: '/active',
          builder: (context, state) => const ActiveWorkoutScreen(),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    final service = getIt<RestTimerService>();
    service.startTimer();
    expect(service.status, TimerStatus.running);

    // Empty workout collapses to the State B "Cancel workout" ghost button.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.tap(find.text('Cancel Workout'));
    await tester.pump();

    expect(service.status, TimerStatus.idle);
  });

  testWidgets('canceling empty workout clears persistent notif and exits', (
    tester,
  ) async {
    final spy = getIt<NotificationService>() as _SpyNotificationService;

    final router = GoRouter(
      initialLocation: '/workout',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox()),
        GoRoute(
          path: '/workout',
          builder: (_, __) => const ActiveWorkoutScreen(),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // Empty workout collapses to the State B "Cancel workout" ghost button.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.tap(find.text('Cancel Workout'));
    await tester.pumpAndSettle();

    expect(find.byType(ActiveWorkoutScreen), findsNothing);
    expect(spy.workoutOngoingCanceled, isTrue);
  });

  testWidgets('system back from a go-owned workout restores its shell origin', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/history?range=30',
      routes: [
        GoRoute(
          path: '/history',
          builder: (_, __) => const Scaffold(body: Text('history')),
        ),
        GoRoute(
          path: '/workout_session',
          builder: (_, __) =>
              const ActiveWorkoutScreen(returnLocation: '/history?range=30'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    router.go('/workout_session');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/history?range=30',
    );
    expect(find.text('history'), findsOneWidget);
  });

  testWidgets('cancelling empty workout closes screen', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SizedBox()),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    router.routerDelegate.navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (_) => const ActiveWorkoutScreen()),
    );
    await tester.pumpAndSettle();

    // Empty workout collapses to the State B "Cancel workout" ghost button.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.tap(find.text('Cancel Workout'));
    await tester.pumpAndSettle();

    expect(find.byType(ActiveWorkoutScreen), findsNothing);
  });

  testWidgets('body header hosts the editable name without a duration badge', (
    tester,
  ) async {
    final session = WorkoutSession(
      id: 's1',
      name: 'Test Workout',
      startTime: DateTime.now(),
      exercises: const <WorkoutExercise>[],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: ActiveWorkoutHeader(session: session, onNameChanged: (_) {}),
        ),
      ),
    );
    await tester.pump();

    // The editable workout name is still present.
    expect(find.text('Test Workout'), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsOneWidget);

    // The duplicate duration badge moved to the fixed app bar; the body header
    // no longer renders a timer glyph or its tonal badge.
    expect(find.byIcon(Icons.timer_outlined), findsNothing);
    expect(find.byType(AnimatedContainer), findsNothing);
  });

  testWidgets('live elapsed label uses emerald dot + tabular onSurface time', (
    tester,
  ) async {
    final start = DateTime.now().subtract(const Duration(seconds: 75));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LiveElapsedLabel(startTime: start)),
      ),
    );
    await tester.pump();

    final textFinder = find.descendant(
      of: find.byType(LiveElapsedLabel),
      matching: find.byType(Text),
    );
    expect(textFinder, findsOneWidget);

    final text = tester.widget<Text>(textFinder);
    final theme = Theme.of(tester.element(textFinder));
    // MM:SS for sub-hour elapsed, onSurface, tabular figures.
    expect(text.data, '01:15');
    expect(text.style?.color, theme.colorScheme.onSurface);
    expect(text.style?.fontWeight, FontWeight.w600);
    expect(
      text.style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });

  testWidgets('replacing exercise refreshes previous and set rows', (
    tester,
  ) async {
    const bench = Exercise(name: 'Bench Press', muscles: ['Chest']);
    const benchPrev = [WorkoutSet(id: 'p1', weight: 100.0, reps: 5)];
    final initialExercises = [
      {
        'name': bench.name,
        'sets': 2,
        'previousSets': benchPrev.map((set) => set.toMap()).toList(),
      },
    ];

    const incline = Exercise(name: 'Incline DB Press', muscles: ['Chest']);
    const inclinePrev = [WorkoutSet(id: 'ip1', weight: 30.0, reps: 10)];
    const replacementExercise = WorkoutExercise(
      id: 'temp',
      exercise: incline,
      sets: [WorkoutSet(id: 'tmp', weight: 0, reps: 0)],
      previousSessionSets: inclinePrev,
      restTimerSeconds: 90,
    );

    final router = GoRouter(
      initialLocation: '/workout',
      routes: [
        GoRoute(
          path: '/workout',
          builder: (_, __) => ActiveWorkoutScreen(
            initialName: 'Test',
            initialExercises: initialExercises,
          ),
        ),
        GoRoute(
          path: '/exercise_select',
          builder: (_, __) =>
              const _AutoPop<WorkoutExercise>(replacementExercise),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Bench Press'), findsOneWidget);
    // Last session's value both shows in the Previous column AND ghosts faintly
    // inside the entry fields (the field prefill). The first bench set prefills
    // 100 kg.
    final benchWeight = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.suffixText == 'kg',
    );
    expect(tester.widget<TextField>(benchWeight.first).controller?.text, '100');

    await tester.tap(find.byKey(const ValueKey('chip-swap')).first);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Incline DB Press'), findsOneWidget);
    // After the swap, the Incline previous-session values (30 kg x 10) refresh
    // into the row as the faint field ghost.
    final inclineWeight = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.suffixText == 'kg',
    );
    expect(
      tester.widget<TextField>(inclineWeight.first).controller?.text,
      '30',
    );
    expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(2));
  });

  testWidgets(
    'template zero-load targets do not mask weighted previous session',
    (tester) async {
      final repo = getIt<WorkoutRepository>() as MockWorkoutRepository;
      final previousStart = DateTime(2026, 1, 1, 8);
      await repo.createWorkoutSession(
        WorkoutSession(
          id: 'previous-session',
          name: 'Previous pull',
          startTime: previousStart,
          endTime: previousStart.add(const Duration(hours: 1)),
          isCompleted: true,
          exercises: const [
            WorkoutExercise(
              id: 'previous-cable-crossover',
              exercise: Exercise(name: 'Cable Crossover', muscles: ['Chest']),
              sets: [
                WorkoutSet(
                  id: 'previous-set-1',
                  weight: 13.75,
                  reps: 8,
                  isCompleted: true,
                ),
              ],
            ),
          ],
        ),
      );

      final templateTargets = List.generate(
        4,
        (index) =>
            WorkoutSet(id: 'template-set-$index', weight: 0, reps: 15).toMap(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ActiveWorkoutScreen(
            initialName: 'Cable day',
            initialExercises: [
              {
                'name': 'Cable Crossover',
                'sets': 4,
                'previousSets': templateTargets,
                'previousSetsAreTemplateTargets': true,
              },
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final active = await repo.getLatestActiveSession();
      final previousSets = active!.exercises.single.previousSessionSets!;
      expect(previousSets.single.weight, 13.75);
      expect(previousSets.single.reps, 8);
      expect(find.text('13.75 kg × 8'), findsOneWidget);
      expect(find.text('0 kg × 15'), findsNothing);
    },
  );

  testWidgets(
    'template zero-load targets show no previous value when no history exists',
    (tester) async {
      final repo = getIt<WorkoutRepository>() as MockWorkoutRepository;
      final templateTargets = List.generate(
        4,
        (index) =>
            WorkoutSet(id: 'template-set-$index', weight: 0, reps: 15).toMap(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ActiveWorkoutScreen(
            initialName: 'Cable day',
            initialExercises: [
              {
                'name': 'Cable Crossover',
                'sets': 4,
                'previousSets': templateTargets,
                'previousSetsAreTemplateTargets': true,
              },
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final active = await repo.getLatestActiveSession();
      expect(active!.exercises.single.previousSessionSets, isNull);
      expect(find.text('0 kg × 15'), findsNothing);
    },
  );

  testWidgets(
    'duration template targets are preserved when marked as template targets',
    (tester) async {
      final repo = getIt<WorkoutRepository>() as MockWorkoutRepository;
      final previousStart = DateTime(2026, 1, 1, 8);
      await repo.createWorkoutSession(
        WorkoutSession(
          id: 'previous-plank-session',
          name: 'Previous core',
          startTime: previousStart,
          endTime: previousStart.add(const Duration(hours: 1)),
          isCompleted: true,
          exercises: const [
            WorkoutExercise(
              id: 'previous-plank',
              exercise: Exercise(
                name: 'Plank',
                muscles: ['core'],
                loggingMode: ExerciseLoggingMode.durationOnly,
              ),
              sets: [
                WorkoutSet(
                  id: 'previous-plank-set',
                  weight: 0,
                  reps: 30,
                  isCompleted: true,
                ),
              ],
            ),
          ],
        ),
      );
      final templateTargets = [
        const WorkoutSet(id: 'template-plank-set', weight: 0, reps: 60).toMap(),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ActiveWorkoutScreen(
            initialName: 'Core day',
            initialExercises: [
              {
                'name': 'Plank',
                'sets': 1,
                'previousSets': templateTargets,
                'previousSetsAreTemplateTargets': true,
              },
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final active = await repo.getLatestActiveSession();
      final previousSets = active!.exercises.single.previousSessionSets!;
      expect(previousSets.single.reps, 60);
      expect(find.text('01:00'), findsWidgets);
      expect(find.text('00:30'), findsNothing);
    },
  );

  testWidgets('replacing exercise preserves entered set values', (
    tester,
  ) async {
    const bench = Exercise(name: 'Bench Press', muscles: ['Chest']);
    const benchPrev = [WorkoutSet(id: 'p1', weight: 95.0, reps: 5)];
    final initialExercises = [
      {
        'name': bench.name,
        'sets': 1,
        'previousSets': benchPrev.map((set) => set.toMap()).toList(),
      },
    ];

    const replacementExercise = WorkoutExercise(
      id: 'temp',
      exercise: Exercise(name: 'Incline DB Press', muscles: ['Chest']),
      sets: [WorkoutSet(id: 'tmp', weight: 0, reps: 0)],
      previousSessionSets: [WorkoutSet(id: 'ip1', weight: 27.5, reps: 10)],
      restTimerSeconds: 90,
    );

    final router = GoRouter(
      initialLocation: '/workout',
      routes: [
        GoRoute(
          path: '/workout',
          builder: (_, __) => ActiveWorkoutScreen(
            initialName: 'Test',
            initialExercises: initialExercises,
          ),
        ),
        GoRoute(
          path: '/exercise_select',
          builder: (_, __) =>
              const _AutoPop<WorkoutExercise>(replacementExercise),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(2));

    // Weight and reps are both read-only and entered via the shared custom
    // keyboard — tapping a field re-targets the keyboard to it. "Done" on weight
    // commits the value; "Done" on reps commits and completes the set, which
    // starts the rest timer, so pump fixed durations afterwards rather than
    // pumpAndSettle (which would wait on that timer forever).
    await tester.tap(textFields.at(0));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('repsKeyboardDigit6')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('repsKeyboardDigit0')));
    await tester.pump();
    // Tap reps while the keyboard is open: it stays up and re-targets to reps
    // (native-keyboard switching). The weight stays a draft and is committed
    // when "Done" completes the set.
    await tester.tap(textFields.at(1));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('repsKeyboardClear')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('repsKeyboardDigit8')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('repsKeyboardDone')));
    await _pumpFrames(tester);

    await tester.tap(find.byKey(const ValueKey('chip-swap')).first);
    await _pumpFrames(tester);

    expect(find.text('Incline DB Press'), findsOneWidget);

    final textFieldsAfter = find.byType(TextField);
    expect(textFieldsAfter, findsNWidgets(2));
    final weightText = tester
        .widget<TextField>(textFieldsAfter.at(0))
        .controller!
        .text;
    expect(double.tryParse(weightText), 60.0);
    expect(
      tester.widget<TextField>(textFieldsAfter.at(1)).controller!.text,
      '8',
    );

    // Completing the set via the keyboard started the rest timer; stop it so no
    // Timer outlives the test (the framework asserts none are pending).
    getIt<RestTimerService>().stopTimer();
    await tester.pump();
  });

  testWidgets('replacing exercise expands rows to fit new template sets', (
    tester,
  ) async {
    const bench = Exercise(name: 'Bench Press', muscles: ['Chest']);
    const benchPrev = [WorkoutSet(id: 'p1', weight: 92.5, reps: 5)];
    final initialExercises = [
      {
        'name': bench.name,
        'sets': 1,
        'previousSets': benchPrev.map((set) => set.toMap()).toList(),
      },
    ];

    const replacementExercise = WorkoutExercise(
      id: 'temp',
      exercise: Exercise(name: 'Incline DB Press', muscles: ['Chest']),
      sets: [
        WorkoutSet(id: 'nw1', weight: 0, reps: 0, setType: SetType.warmup),
        WorkoutSet(id: 'nw2', weight: 0, reps: 0),
        WorkoutSet(id: 'nw3', weight: 0, reps: 0),
      ],
      previousSessionSets: [
        WorkoutSet(id: 'ip1', weight: 20.0, reps: 12, setType: SetType.warmup),
        WorkoutSet(id: 'ip2', weight: 32.5, reps: 10),
        WorkoutSet(id: 'ip3', weight: 32.5, reps: 8),
      ],
      restTimerSeconds: 75,
    );

    final router = GoRouter(
      initialLocation: '/workout',
      routes: [
        GoRoute(
          path: '/workout',
          builder: (_, __) => ActiveWorkoutScreen(
            initialName: 'Test',
            initialExercises: initialExercises,
          ),
        ),
        GoRoute(
          path: '/exercise_select',
          builder: (_, __) =>
              const _AutoPop<WorkoutExercise>(replacementExercise),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final initialFields = find.byType(TextField);
    expect(initialFields, findsNWidgets(2));
    // Weight and reps are both read-only and entered via the shared custom
    // keyboard — tapping a field re-targets the keyboard to it. "Done" on weight
    // commits the value; "Done" on reps commits and completes the set, which
    // starts the rest timer, so pump fixed durations afterwards rather than
    // pumpAndSettle (which would wait on that timer forever).
    await tester.tap(initialFields.at(0));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('repsKeyboardDigit6')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('repsKeyboardDigit0')));
    await tester.pump();
    // Tap reps while the keyboard is open: it stays up and re-targets to reps
    // (native-keyboard switching). Weight stays a draft, committed when "Done"
    // completes the set.
    await tester.tap(initialFields.at(1));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('repsKeyboardClear')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('repsKeyboardDigit8')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('repsKeyboardDone')));
    await _pumpFrames(tester);

    await tester.tap(find.byKey(const ValueKey('chip-swap')).first);
    await _pumpFrames(tester);

    expect(find.text('Incline DB Press'), findsOneWidget);
    // The entered set (now completed via the keyboard's Done) is preserved as
    // the first row; the two appended template rows stay uncompleted, so only
    // two of the three rows show the empty-circle "complete" affordance.
    expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(2));

    final fieldsAfter = find.byType(TextField);
    expect(fieldsAfter, findsNWidgets(6));

    final firstWeightText = tester
        .widget<TextField>(fieldsAfter.at(0))
        .controller!
        .text;
    expect(double.tryParse(firstWeightText), 60.0);
    expect(tester.widget<TextField>(fieldsAfter.at(1)).controller!.text, '8');
    expect(
      tester.widget<TextField>(fieldsAfter.at(2)).controller!.text,
      '32.5',
    );
    expect(tester.widget<TextField>(fieldsAfter.at(3)).controller!.text, '10');

    // Completing the set via the keyboard started the rest timer; stop it so no
    // Timer outlives the test (the framework asserts none are pending).
    getIt<RestTimerService>().stopTimer();
    await tester.pump();
  });
}
