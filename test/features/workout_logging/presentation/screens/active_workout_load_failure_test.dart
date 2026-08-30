import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/notification_service.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/workout_logging/data/repositories/mock_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/services/inactivity_service.dart';
import 'package:hustl_app/features/workout_logging/domain/services/rest_timer_service.dart';
import 'package:hustl_app/features/workout_logging/presentation/screens/active_workout_screen.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/active_workout_skeleton.dart';

/// A repository that throws on `getLatestActiveSession` (the "no sessionId,
/// resume-latest-active" path `_loadOrCreateSession` takes) while [failLoad]
/// is set, then falls through to the real mock behaviour once healed —
/// exercising the "Try again" retry path.
class _FlakyLoadRepo extends MockWorkoutRepository {
  bool failLoad = true;

  @override
  Future<WorkoutSession?> getLatestActiveSession() async {
    if (failLoad) {
      throw Exception('simulated load failure');
    }
    return super.getLatestActiveSession();
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

Widget _routedApp() {
  final router = GoRouter(
    initialLocation: '/active',
    routes: [
      GoRoute(
        path: '/active',
        builder: (context, state) => const ActiveWorkoutScreen(),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  final getIt = GetIt.instance;
  late _FlakyLoadRepo repo;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    await prefs.setHapticsEnabled(false);
    getIt.registerSingleton<PreferencesService>(prefs);
    repo = _FlakyLoadRepo();
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

  testWidgets(
    'a failed load shows a retryable error state instead of an endless '
    'skeleton, and Try again recovers',
    (tester) async {
      await tester.pumpWidget(_routedApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(ActiveWorkoutSkeleton), findsNothing);
      expect(find.text('We couldn\'t load your workout'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      repo.failLoad = false;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('We couldn\'t load your workout'), findsNothing);
      expect(find.byType(ActiveWorkoutSkeleton), findsNothing);
      expect(find.text('No exercises yet'), findsOneWidget);
    },
  );
}
