import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/navigation/deep_links.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';

/// Fake repo whose active-session lookup is fully controllable, including a
/// never-completing variant to exercise the launch screen's timeout fallback.
class _FakeWorkoutRepo implements WorkoutRepository {
  _FakeWorkoutRepo(this._active);
  final Future<WorkoutSession?> Function() _active;

  @override
  Future<WorkoutSession?> getLatestActiveSession() => _active();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<dynamic>.error(UnimplementedError());
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/widget/workouts',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: '/widget/workouts',
        builder: (_, __) => const WidgetWorkoutLaunchScreen(),
      ),
      GoRoute(
        path: '/workout_session',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return Scaffold(body: Text('session:${extra?['sessionId']}'));
        },
      ),
    ],
  );
}

void main() {
  setUp(() => GetIt.I.reset());
  tearDown(() => GetIt.I.reset());

  testWidgets('proposal cold-start link waits for the router before pushing', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/proposals/:id',
          builder: (context, state) =>
              Scaffold(body: Text('proposal:${state.pathParameters['id']}')),
        ),
      ],
    );

    var linkHandled = false;
    final linkFuture = handleExternalDeepLink(
      router,
      Uri.parse('hustl://proposal/72819602-bad7-4a52-b37c-4233017b70a8'),
    ).whenComplete(() => linkHandled = true);

    await tester.pump(const Duration(seconds: 3));
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(linkHandled, isFalse);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(milliseconds: 100));
    await linkFuture;
    await tester.pumpAndSettle();

    expect(
      find.text('proposal:72819602-bad7-4a52-b37c-4233017b70a8'),
      findsOneWidget,
    );
    expect(find.text('home'), findsNothing);

    expect(router.canPop(), isTrue);
    router.pop();
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('no active session redirects the launch screen to home', (
    tester,
  ) async {
    GetIt.I.registerSingleton<WorkoutRepository>(
      _FakeWorkoutRepo(() async => null),
    );
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('an active session resumes /workout_session', (tester) async {
    final active = WorkoutSession(
      id: 'sess-1',
      name: 'Push day',
      startTime: DateTime(2026, 1, 1),
      exercises: const [],
    );
    GetIt.I.registerSingleton<WorkoutRepository>(
      _FakeWorkoutRepo(() async => active),
    );
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/workout_session');
    expect(find.text('session:sess-1'), findsOneWidget);
  });

  testWidgets('a stalled lookup times out and still reaches home', (
    tester,
  ) async {
    // A lookup that never resolves (seen on warm resume) must not strand the
    // user on the skeleton — the launch screen times out and falls back to home.
    GetIt.I.registerSingleton<WorkoutRepository>(
      _FakeWorkoutRepo(() => Completer<WorkoutSession?>().future),
    );
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(); // run the post-frame callback -> start the lookup

    // Still on the skeleton route while the lookup hangs.
    expect(router.routeInformationProvider.value.uri.path, '/widget/workouts');

    // Advance past the resolve timeout; the screen must redirect anyway.
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('home'), findsOneWidget);
  });
}
