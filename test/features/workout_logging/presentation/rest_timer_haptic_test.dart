import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart'
    as ex;
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/rest_timer_dialog_content.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/exercise_card.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/rest_timer_picker.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/rest_timer_widget.dart';
import 'package:hustl_app/features/workout_logging/domain/services/rest_timer_service.dart';
import 'package:hustl_app/core/services/notification_service.dart';

class _FakeNotificationService implements NotificationService {

  @override
  Future<void> showAutoLoggedProposal({required String id, required bool isFood, required String body}) async {}


  @override
  Future<void> handleAppLaunchNotification() async {}
  @override
  Future<void> cancelRestComplete() async {}

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
  }) async {}

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
  Widget dialog(RestTimerService service, {VoidCallback? onClose}) {
    return MaterialApp(
      home: Scaffold(
        body: RestTimerDialogContent(
          restTimerService: service,
          onClose: onClose ?? () {},
        ),
      ),
    );
  }

  WorkoutExercise makeExercise({int? restSeconds}) {
    return WorkoutExercise(
      id: 'ex1',
      exercise: const ex.Exercise(
        name: 'Back Squat',
        muscles: ['Quads', 'Glutes'],
      ),
      sets: const [WorkoutSet(id: 's1', weight: 100, reps: 5)],
      previousSessionSets: const [],
      restTimerSeconds: restSeconds,
    );
  }

  Widget wrapWithRouter(Widget child) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Material(child: child),
            ),
          ),
        ),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  setUp(() async {
    GetIt.I.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    GetIt.I.registerSingleton<PreferencesService>(prefs);
  });

  tearDown(GetIt.I.reset);

  testWidgets('emits haptic feedback on rest completion in dialog', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall methodCall,
        ) async {
          calls.add(methodCall);
          return null;
        });

    DateTime now = DateTime(2024, 1, 1, 12, 0, 0);
    final service = RestTimerService(
      now: () => now,
      notificationService: _FakeNotificationService(),
    );

    bool closed = false;
    await tester.pumpWidget(dialog(service, onClose: () => closed = true));

    // Start a very short timer
    service.startTimer(durationInSeconds: 1, exerciseName: 'Bench');
    await tester.pump();

    now = now.add(const Duration(seconds: 2));
    service.refreshNow();
    await tester.pump();

    final vibrates = calls
        .where((m) => m.method == 'HapticFeedback.vibrate')
        .toList();
    expect(vibrates.length, equals(1));
    expect(
      vibrates.first.arguments,
      anyOf(
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.vibrate',
      ),
    );
    expect(closed, isTrue);
  });

  testWidgets('does not emit haptic feedback when disabled', (tester) async {
    final prefs = GetIt.I<PreferencesService>();
    await prefs.setHapticsEnabled(false);

    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall methodCall,
        ) async {
          calls.add(methodCall);
          return null;
        });

    DateTime now = DateTime(2024, 1, 1, 12, 0, 0);
    final service = RestTimerService(
      now: () => now,
      notificationService: _FakeNotificationService(),
    );

    await tester.pumpWidget(dialog(service));

    service.startTimer(durationInSeconds: 1);
    await tester.pump();

    now = now.add(const Duration(seconds: 2));
    service.refreshNow();
    await tester.pump();

    final vibrates = calls.where((m) => m.method == 'HapticFeedback.vibrate');
    expect(vibrates, isEmpty);
  });

  testWidgets('rest timer widget uses soft default colors for low light', (
    tester,
  ) async {
    final service = RestTimerService(
      notificationService: _FakeNotificationService(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: RestTimerWidget(restTimerService: service, onClose: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final timeFinder = find.text(
      RestTimerService.formatTime(service.remainingSeconds),
    );
    expect(timeFinder, findsOneWidget);
    final timeText = tester.widget<Text>(timeFinder);
    final theme = Theme.of(tester.element(timeFinder));
    expect(
      timeText.style?.color,
      theme.colorScheme.onSurface.withValues(alpha: 0.95),
    );
    expect(timeText.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('rest timer catches up after background and shows 00:00', (
    tester,
  ) async {
    DateTime fakeNow = DateTime(2024, 1, 1, 12, 0, 0);
    final service = RestTimerService(
      now: () => fakeNow,
      notificationService: _FakeNotificationService(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: RestTimerWidget(restTimerService: service, onClose: () {}),
        ),
      ),
    );

    service.startTimer(durationInSeconds: 2, exerciseName: 'Bench');
    await tester.pump();

    fakeNow = fakeNow.add(const Duration(seconds: 3));
    service.refreshNow();
    await tester.pump();
    await tester.pump();

    expect(find.text('00:00'), findsOneWidget);
    expect(service.status, TimerStatus.completed);

    service.dispose();
  });

  testWidgets('rest timer stroke diminishes from full over time', (
    tester,
  ) async {
    var now = DateTime(2024, 1, 1);
    final service = RestTimerService(
      now: () => now,
      notificationService: _FakeNotificationService(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: RestTimerWidget(restTimerService: service, onClose: () {}),
        ),
      ),
    );

    service.startTimer(durationInSeconds: 5, exerciseName: 'Bench');
    await tester.pump();

    final context = tester.element(find.byType(RestTimerWidget));
    var indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, 0);
    expect(indicator.strokeWidth, 5);
    expect(indicator.backgroundColor, Theme.of(context).colorScheme.error);

    now = now.add(const Duration(seconds: 2));
    service.refreshNow();
    await tester.pumpAndSettle();
    indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, greaterThan(0));
    service.stopTimer();
  });

  testWidgets('rest timer dialog shows title, time and controls', (
    tester,
  ) async {
    final service = RestTimerService(
      notificationService: _FakeNotificationService(),
    );

    await tester.pumpWidget(dialog(service));

    expect(find.text('Rest timer'), findsOneWidget);
    expect(find.text('01:30'), findsOneWidget);
    expect(find.text('-30s'), findsOneWidget);
    expect(find.text('+30s'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets('rest timer dialog shows current exercise name if set', (
    tester,
  ) async {
    final service = RestTimerService(
      notificationService: _FakeNotificationService(),
    );
    service.startTimer(
      durationInSeconds: 30,
      exerciseName: 'Squat',
      notificationNextExerciseName: 'Bench',
    );

    await tester.pumpWidget(dialog(service));

    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('Bench'), findsNothing);

    service.stopTimer();
    await tester.pumpAndSettle();
  });

  testWidgets('opens rest timer picker and selects a preset', (tester) async {
    WorkoutExercise? updated;

    await tester.pumpWidget(
      wrapWithRouter(
        ExerciseCard(
          exercise: makeExercise(restSeconds: 90),
          onExerciseUpdated: (exercise) => updated = exercise,
          onStartRestTimer: (_) {},
        ),
      ),
    );

    final timerChip = find.byKey(const ValueKey('chip-rest-timer'));
    expect(timerChip, findsOneWidget);
    await tester.tap(timerChip);
    await tester.pumpAndSettle();

    expect(find.text('Set Rest Timer'), findsOneWidget);
    await tester.tap(find.text('1m'));
    await tester.pumpAndSettle();

    expect(updated, isNotNull);
    expect(updated!.restTimerSeconds, 60);
  });

  testWidgets('enters a custom rest time via custom picker', (tester) async {
    WorkoutExercise? updated;

    await tester.pumpWidget(
      wrapWithRouter(
        ExerciseCard(
          exercise: makeExercise(restSeconds: 90),
          onExerciseUpdated: (exercise) => updated = exercise,
          onStartRestTimer: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('chip-rest-timer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom...'));
    await tester.pumpAndSettle();

    final secWheel = find.byKey(const Key('custom_sec_picker'));
    expect(secWheel, findsOneWidget);
    await tester.drag(secWheel, const Offset(0, 96));
    await tester.pumpAndSettle();

    final applyButton = find.byKey(const Key('custom_apply'));
    await tester.ensureVisible(applyButton);
    await tester.tap(applyButton);
    await tester.pumpAndSettle();

    expect(updated, isNotNull);
    expect(updated!.restTimerSeconds, 75);
  });

  testWidgets('saves selected rest time to preferences', (tester) async {
    final prefs = GetIt.instance<PreferencesService>();

    await tester.pumpWidget(
      wrapWithRouter(
        ExerciseCard(
          exercise: makeExercise(restSeconds: 90),
          onExerciseUpdated: (_) {},
          onStartRestTimer: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('chip-rest-timer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1m'));
    await tester.pumpAndSettle();

    expect(await prefs.getExerciseRestTimer('Back Squat'), 60);
  });

  test('setExerciseRestTimer clamps values between 1 and 600', () async {
    final prefs = GetIt.instance<PreferencesService>();
    await prefs.setExerciseRestTimer('Back Squat', 700);
    expect(await prefs.getExerciseRestTimer('Back Squat'), 600);
    await prefs.setExerciseRestTimer('Back Squat', 0);
    expect(await prefs.getExerciseRestTimer('Back Squat'), 1);
  });

  testWidgets('warm-up chip generates and clears warm-up sets', (tester) async {
    WorkoutExercise current = const WorkoutExercise(
      id: 'ex1',
      exercise: ex.Exercise(name: 'Back Squat', muscles: ['Quads', 'Glutes']),
      sets: [
        WorkoutSet(id: 's1', weight: 100, reps: 5),
        WorkoutSet(id: 's2', weight: 105, reps: 3),
      ],
      previousSessionSets: [],
    );

    late StateSetter stateSetter;

    await tester.pumpWidget(
      wrapWithRouter(
        StatefulBuilder(
          builder: (context, setState) {
            stateSetter = setState;
            return ExerciseCard(
              exercise: current,
              onExerciseUpdated: (updated) {
                current = updated;
                stateSetter(() {});
              },
              onStartRestTimer: (_) {},
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('chip-warmup')));
    await tester.pumpAndSettle();

    final applyButton = find.byType(FilledButton);
    expect(applyButton, findsOneWidget);
    await tester.tap(applyButton);
    await tester.pumpAndSettle();

    final warmUpCount = current.sets
        .where((set) => set.setType == SetType.warmup)
        .length;
    expect(warmUpCount, greaterThan(0));
    expect(current.sets.first.setType, SetType.warmup);

    await tester.tap(find.byKey(const ValueKey('chip-warmup')));
    await tester.pumpAndSettle();
    // The revamped sheet is taller; ensure the secondary action is on-screen
    // before tapping (the host viewport is only 600px tall in this test).
    await tester.ensureVisible(find.text('Remove existing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove existing'));
    await tester.pumpAndSettle();

    expect(current.sets.where((set) => set.setType == SetType.warmup), isEmpty);
  });

  testWidgets('rest timer picker renders header and presets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () {
                  showRestTimerPicker(context, initialSeconds: 90);
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Set Rest Timer'), findsOneWidget);
    expect(find.text('Custom...'), findsOneWidget);
    expect(find.text('1m'), findsWidgets);
    expect(find.text('2m'), findsWidgets);
  });

  testWidgets('Skip rest stops the timer and dismisses', (tester) async {
    DateTime now = DateTime(2024, 1, 1, 12, 0, 0);
    final service = RestTimerService(
      now: () => now,
      notificationService: _FakeNotificationService(),
    );
    service.startTimer(durationInSeconds: 60, exerciseName: 'Bench');

    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RestTimerWidget(
            restTimerService: service,
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    expect(service.status, TimerStatus.running);

    await tester.tap(find.text('Skip rest'));
    await tester.pump();

    expect(service.status, TimerStatus.idle);
    expect(closed, isTrue);
  });

  testWidgets('-15s trims the remaining rest', (tester) async {
    DateTime now = DateTime(2024, 1, 1, 12, 0, 0);
    final service = RestTimerService(
      now: () => now,
      notificationService: _FakeNotificationService(),
    );
    service.startTimer(durationInSeconds: 60, exerciseName: 'Bench');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RestTimerWidget(restTimerService: service, onClose: () {}),
        ),
      ),
    );

    await tester.tap(find.text('-15s'));
    await tester.pump();

    expect(service.remainingSeconds, 45);

    // Stop the freshly-restarted timer so no real Timer leaks past teardown.
    service.stopTimer();
  });
}
