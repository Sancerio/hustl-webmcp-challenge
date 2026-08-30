import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/notification_service.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/data/repositories/mock_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/services/inactivity_service.dart';
import 'package:hustl_app/features/workout_logging/domain/services/rest_timer_service.dart';
import 'package:hustl_app/features/workout_logging/presentation/screens/active_workout_screen.dart';

/// A notification service whose `cancelWorkoutOngoing` fails the same way the
/// real `flutter_local_notifications` plugin does on minified Android release
/// builds: a `PlatformException(error, TypeToken must be ...)` thrown from its
/// Gson-backed scheduled-notification cache. Finishing must survive this.
class _ThrowingNotificationService implements NotificationService {
  bool cancelAttempted = false;

  @override
  Future<void> cancelWorkoutOngoing() async {
    cancelAttempted = true;
    throw PlatformException(
      code: 'error',
      message:
          'TypeToken must be created with a type argument: class '
          'com.google.gson.reflect.TypeToken',
    );
  }

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
      GoRoute(
        path: '/summary/:id',
        builder: (context, state) =>
            const Scaffold(body: Text('summary-screen')),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  final getIt = GetIt.instance;
  late MockWorkoutRepository repo;
  late _ThrowingNotificationService notifications;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    await prefs.setHapticsEnabled(false);
    getIt.registerSingleton<PreferencesService>(prefs);
    repo = MockWorkoutRepository();
    getIt.registerSingleton<WorkoutRepository>(repo);
    notifications = _ThrowingNotificationService();
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
  });

  tearDown(() async {
    await getIt.reset(dispose: true);
  });

  testWidgets(
    'finishing succeeds when notification cancel throws a TypeToken '
    'PlatformException',
    (tester) async {
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

      await tester.pumpWidget(_routedApp(sessionId: seeded.id));
      await tester.pumpAndSettle();

      final state = tester.state(find.byType(ActiveWorkoutScreen));
      await (state as dynamic).finishWorkoutForTest();
      await tester.pumpAndSettle();

      // The failing platform call was actually exercised...
      expect(notifications.cancelAttempted, isTrue);

      // ...but the user never sees the finish-failed error, because the workout
      // was already persisted before the best-effort side-effect ran.
      expect(find.textContaining("couldn't finish your workout"), findsNothing);

      // The session is persisted as completed and we routed on to the summary.
      final persisted = await repo.getWorkoutSession('sess-1');
      expect(persisted?.isCompleted, isTrue);
      expect(find.text('summary-screen'), findsOneWidget);
    },
  );
}
