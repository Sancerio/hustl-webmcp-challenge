import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hustl_app/core/services/notification_service.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/main.dart';
import 'package:go_router/go_router.dart';

class MockWorkoutRepository implements WorkoutRepository {
  final WorkoutSession? mockActiveSession;

  MockWorkoutRepository({this.mockActiveSession});

  @override
  Future<WorkoutSession?> getLatestActiveSession() async {
    return mockActiveSession;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;
}

void main() {
  group('NotificationService', () {
    late NotificationService notificationService;

    setUp(() {
      // Reset GetIt
      GetIt.instance.reset();
      notificationService = NotificationService();
    });

    testWidgets(
      'notification tap navigates to active workout when session exists',
      (WidgetTester tester) async {
        // Setup mock active session
        final mockSession = WorkoutSession(
          id: 'test-session-id',
          name: 'Test Workout',
          startTime: DateTime.now(),
          exercises: [],
        );

        // Register mock repository
        GetIt.instance.registerSingleton<WorkoutRepository>(
          MockWorkoutRepository(mockActiveSession: mockSession),
        );

        // Build test app with navigator key
        final router = GoRouter(
          navigatorKey: navigatorKey,
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const Scaffold(body: Text('Home')),
            ),
            GoRoute(
              path: '/workout_session',
              builder: (context, state) {
                final args = state.extra as Map<String, dynamic>?;
                return Scaffold(
                  body: Text('Active Workout: ${args?['sessionId']}'),
                );
              },
            ),
            GoRoute(
              path: '/workout',
              builder: (context, state) =>
                  const Scaffold(body: Text('Workout Home')),
            ),
          ],
        );
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));

        // Trigger navigation
        await notificationService.navigateToActiveWorkout();
        await tester.pumpAndSettle();

        // Verify navigation to active workout with session ID
        expect(find.text('Active Workout: test-session-id'), findsOneWidget);
      },
    );

    testWidgets(
      'notification tap starts on the canonical route when no session exists',
      (WidgetTester tester) async {
        // Register mock repository with no active session
        GetIt.instance.registerSingleton<WorkoutRepository>(
          MockWorkoutRepository(mockActiveSession: null),
        );

        // Build test app
        final router = GoRouter(
          navigatorKey: navigatorKey,
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const Scaffold(body: Text('Home')),
            ),
            GoRoute(
              path: '/workout_session',
              builder: (context, state) =>
                  const Scaffold(body: Text('Active Workout')),
            ),
          ],
        );
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));

        // Trigger navigation
        await notificationService.navigateToActiveWorkout();
        await tester.pumpAndSettle();

        // Verify navigation to the sole active-workout route.
        expect(find.text('Active Workout'), findsOneWidget);
      },
    );
  });
}
