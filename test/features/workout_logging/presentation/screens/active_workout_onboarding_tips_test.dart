import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/core/services/notification_service.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/exercise_library/domain/repositories/exercise_repository.dart';
import 'package:hustl_app/features/workout_logging/data/repositories/mock_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/services/inactivity_service.dart';
import 'package:hustl_app/features/workout_logging/domain/services/rest_timer_service.dart';
import 'package:hustl_app/features/workout_logging/presentation/screens/active_workout_screen.dart';

class _MockNotificationService extends Mock implements NotificationService {}

class _MockExerciseRepository extends Mock implements ExerciseRepository {}

Future<void> _pumpFrames(
  WidgetTester tester, {
  int frames = 20,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final getIt = GetIt.instance;

  setUpAll(() async {
    final manifest =
        json.decode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    final preferences = PreferencesService();
    await preferences.init();
    getIt.registerSingleton<PreferencesService>(preferences);
    getIt.registerSingleton<WorkoutRepository>(MockWorkoutRepository());
    final notifications = _MockNotificationService();
    when(
      notifications.ensurePermissionsForWorkout,
    ).thenAnswer((_) async => true);
    when(notifications.cancelInactivityReminder).thenAnswer((_) async {});
    when(
      () => notifications.scheduleInactivityReminder(any()),
    ).thenAnswer((_) async {});
    when(
      () => notifications.showWorkoutOngoing(
        startTime: any(named: 'startTime'),
        currentExerciseName: any(named: 'currentExerciseName'),
      ),
    ).thenAnswer((_) async {});
    getIt.registerSingleton<NotificationService>(notifications);
    getIt.registerSingleton<RestTimerService>(
      RestTimerService(notificationService: getIt<NotificationService>()),
    );
    getIt.registerFactory<InactivityService>(
      () => InactivityService(
        notificationService: getIt<NotificationService>(),
        preferencesService: getIt<PreferencesService>(),
      ),
    );
    final exercises = _MockExerciseRepository();
    when(exercises.getAllExercises).thenAnswer(
      (_) async => const [
        Exercise(name: 'Push Up', muscles: ['chest']),
      ],
    );
    getIt.registerSingleton<ExerciseRepository>(exercises);
  });

  tearDown(() async {
    await getIt.reset(dispose: true);
  });

  testWidgets('empty workout relies on its single central add-exercise CTA', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const ActiveWorkoutScreen(enableOnboardingTipsInTests: true),
      ),
    );
    await _pumpFrames(tester);

    expect(find.text('No exercises yet'), findsOneWidget);
    expect(find.text('Add exercise'), findsOneWidget);
    expect(find.text('Add your first exercise to get started.'), findsNothing);
  });

  testWidgets('first-set guidance still appears once for a new lifter', (
    tester,
  ) async {
    const guidance =
        'Enter your weight and reps, then tap the check to log a set.';
    const screen = ActiveWorkoutScreen(
      initialExercises: [
        {'name': 'Push Up'},
      ],
      enableOnboardingTipsInTests: true,
    );

    await tester.pumpWidget(const MaterialApp(home: screen));
    await _pumpFrames(tester);

    expect(find.text(guidance), findsOneWidget);
    expect(
      await getIt<PreferencesService>()
          .getOnboardingV2SeenCoachmarkLogFirstSet(),
      isTrue,
    );

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: screen));
    await _pumpFrames(tester);

    expect(find.text(guidance), findsNothing);
  });

  testWidgets('seen first-set preference suppresses repeat guidance', (
    tester,
  ) async {
    await getIt<PreferencesService>().setOnboardingV2SeenCoachmarkLogFirstSet(
      true,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: ActiveWorkoutScreen(
          initialExercises: [
            {'name': 'Push Up'},
          ],
          enableOnboardingTipsInTests: true,
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(
      find.text('Enter your weight and reps, then tap the check to log a set.'),
      findsNothing,
    );
  });
}
