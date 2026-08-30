import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hustl_app/core/widgets/active_workout_banner.dart';
import 'package:hustl_app/core/navigation/route_observer.dart';
import 'package:hustl_app/core/navigation/workout_minimize_intent.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/services/workout_events_service.dart';

class _MockWorkoutRepository extends Mock implements WorkoutRepository {}

/// The card's outline lives on the only bordered, 16-radius [BoxDecoration] in
/// the banner (the icon disc uses a circle shape, so it never matches).
BorderSide _cardOutline(WidgetTester tester) {
  final deco = tester
      .widgetList<DecoratedBox>(find.byType(DecoratedBox))
      .map((d) => d.decoration)
      .whereType<BoxDecoration>()
      .singleWhere(
        (d) =>
            d.border is Border && d.borderRadius == BorderRadius.circular(16),
      );
  return (deco.border! as Border).top;
}

void main() {
  final getIt = GetIt.instance;
  late _MockWorkoutRepository repository;
  late WorkoutEventsService events;
  WorkoutSession? activeSession;

  setUp(() async {
    await getIt.reset(dispose: true);
    repository = _MockWorkoutRepository();
    events = WorkoutEventsService();
    activeSession = null;

    getIt.registerSingleton<WorkoutRepository>(repository);
    getIt.registerSingleton<WorkoutEventsService>(events);

    when(
      () => repository.getLatestActiveSession(),
    ).thenAnswer((_) async => activeSession);
  });

  tearDown(() async {
    await getIt.reset(dispose: true);
  });

  testWidgets('ActiveWorkoutBanner refreshes on workout events', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ActiveWorkoutBanner())),
    );

    await tester.pumpAndSettle();
    expect(find.text('Resume'), findsNothing);

    activeSession = WorkoutSession(
      id: 'session-1',
      name: 'Workout',
      startTime: DateTime.now().subtract(const Duration(minutes: 1)),
      exercises: const [],
    );

    events.emit(
      const WorkoutChange(
        kind: WorkoutChangeKind.created,
        sessionId: 'session-1',
      ),
    );

    // Allow debounce + async load without waiting for a running Ticker to settle.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Resume'), findsOneWidget);
  });

  testWidgets(
    'Resume transfers canonical ownership and preserves the shell origin',
    (WidgetTester tester) async {
      activeSession = WorkoutSession(
        id: 'session-1',
        name: 'Workout',
        startTime: DateTime.now().subtract(const Duration(minutes: 1)),
        exercises: const [],
      );
      Map<String, dynamic>? receivedExtra;
      final router = GoRouter(
        initialLocation: '/history?range=30',
        routes: [
          GoRoute(
            path: '/history',
            builder: (_, __) => const Scaffold(body: ActiveWorkoutBanner()),
          ),
          GoRoute(
            path: '/workout_session',
            builder: (_, state) {
              receivedExtra = state.extra as Map<String, dynamic>?;
              return const Scaffold(body: Text('canonical workout screen'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Resume'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        router.routeInformationProvider.value.uri.path,
        '/workout_session',
      );
      expect(
        receivedExtra?[workoutReturnLocationExtraKey],
        '/history?range=30',
      );
    },
  );

  testWidgets('Resume preserves a visible route pushed over the shell', (
    WidgetTester tester,
  ) async {
    activeSession = WorkoutSession(
      id: 'session-1',
      name: 'Workout',
      startTime: DateTime.now().subtract(const Duration(minutes: 1)),
      exercises: const [],
    );
    Map<String, dynamic>? receivedExtra;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/templates'),
              child: const Text('Open templates'),
            ),
          ),
        ),
        GoRoute(
          path: '/templates',
          builder: (_, __) => const Scaffold(body: ActiveWorkoutBanner()),
        ),
        GoRoute(
          path: '/workout_session',
          builder: (_, state) {
            receivedExtra = state.extra as Map<String, dynamic>?;
            return const Scaffold(body: Text('canonical workout screen'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Open templates'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      router.routeInformationProvider.value.uri.path,
      '/',
      reason: 'go_router does not reflect imperative pushes in the URL',
    );
    expect(find.text('Resume'), findsOneWidget);

    await tester.tap(find.text('Resume'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(router.routeInformationProvider.value.uri.path, '/workout_session');
    expect(receivedExtra?[workoutReturnLocationExtraKey], '/templates');
  });

  testWidgets(
    'a newly created workout appears while the shell route is covered',
    (WidgetTester tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [routeObserver],
          home: const Scaffold(body: ActiveWorkoutBanner()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Resume'), findsNothing);

      navigatorKey.currentState!.push(
        PageRouteBuilder<void>(
          opaque: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) =>
              const ColoredBox(color: Colors.transparent),
        ),
      );
      await tester.pump();

      activeSession = WorkoutSession(
        id: 'new-session',
        name: 'New workout',
        startTime: DateTime.now(),
        exercises: const [],
      );
      ActiveWorkoutBanner.synchronizeSession(activeSession!);
      await tester.pump();

      expect(find.text('New workout'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
    },
  );

  testWidgets(
    'preparing a covered long-running workout refreshes its elapsed time',
    (WidgetTester tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      activeSession = WorkoutSession(
        id: 'long-session',
        name: 'Long workout',
        startTime: DateTime.now().subtract(const Duration(minutes: 65)),
        exercises: const [],
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [routeObserver],
          home: const Scaffold(body: ActiveWorkoutBanner()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1h 05m'), findsOneWidget);

      navigatorKey.currentState!.push(
        PageRouteBuilder<void>(
          opaque: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) =>
              const ColoredBox(color: Colors.transparent),
        ),
      );
      await tester.pump();
      expect(
        find.text('1h 05m'),
        findsOneWidget,
        reason: 'the covered destination remains muted until minimize begins',
      );

      activeSession = activeSession!.copyWith(
        startTime: DateTime.now().subtract(const Duration(minutes: 67)),
      );

      ActiveWorkoutBanner.synchronizeSession(activeSession!);
      ActiveWorkoutBanner.prepareForMinimizeDestination();
      await tester.pump();

      expect(find.text('1h 07m'), findsOneWidget);
    },
  );

  testWidgets(
    'a stale in-flight load cannot undo a rename published before drag',
    (WidgetTester tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      activeSession = WorkoutSession(
        id: 'renamed-session',
        name: 'Old workout name',
        startTime: DateTime.now().subtract(const Duration(minutes: 12)),
        exercises: const [],
      );
      final staleLoad = Completer<WorkoutSession?>();
      when(
        () => repository.getLatestActiveSession(),
      ).thenAnswer((_) => staleLoad.future);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [routeObserver],
          home: const Scaffold(body: ActiveWorkoutBanner()),
        ),
      );
      await tester.pump();
      ActiveWorkoutBanner.synchronizeSession(activeSession!);
      await tester.pump();

      navigatorKey.currentState!.push(
        PageRouteBuilder<void>(
          opaque: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) =>
              const ColoredBox(color: Colors.transparent),
        ),
      );
      await tester.pump();

      final renamed = activeSession!.copyWith(name: 'Renamed workout');
      ActiveWorkoutBanner.synchronizeSession(renamed);
      ActiveWorkoutBanner.prepareForMinimizeDestination();
      staleLoad.complete(activeSession);
      await tester.pump();
      await tester.pump();

      expect(find.text('Renamed workout'), findsOneWidget);
      expect(find.text('Old workout name'), findsNothing);
    },
  );

  testWidgets('centers the play icon, details, and Resume action', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 150));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    activeSession = WorkoutSession(
      id: 'session-1',
      name: 'Upper body strength',
      startTime: DateTime.now().subtract(const Duration(minutes: 18)),
      exercises: const [],
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ActiveWorkoutBanner())),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final content = tester.getRect(
      find.byKey(const Key('activeWorkoutBannerContent')),
    );
    final details = tester.getRect(
      find.byKey(const Key('activeWorkoutBannerDetails')),
    );
    final play = tester.getRect(find.byIcon(Icons.play_arrow));
    final resume = tester.getRect(find.text('Resume'));

    expect(content.height, lessThanOrEqualTo(48));
    expect(details.height, lessThan(content.height));
    expect(details.center.dy, closeTo(content.center.dy, 0.5));
    expect(play.center.dy, closeTo(content.center.dy, 0.5));
    expect(resume.center.dy, closeTo(content.center.dy, 0.5));
  });

  testWidgets('mobile landing height covers accessibility-scaled banner', (
    WidgetTester tester,
  ) async {
    activeSession = WorkoutSession(
      id: 'session-1',
      name: 'Upper body strength',
      startTime: DateTime.now().subtract(const Duration(minutes: 18)),
      exercises: const [],
    );

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              mainAxisSize: MainAxisSize.min,
              children: [ActiveWorkoutBanner(includeBottomSafeArea: false)],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final context = tester.element(find.byType(ActiveWorkoutBanner));
    final actualHeight = tester
        .getSize(find.byKey(const Key('activeWorkoutBannerSurface')))
        .height;
    expect(
      ActiveWorkoutBanner.mobileLandingHeight(context),
      greaterThanOrEqualTo(actualHeight),
    );
  });

  testWidgets('the MiniPlayer remains visually stable while mounted', (
    WidgetTester tester,
  ) async {
    activeSession = WorkoutSession(
      id: 'session-1',
      name: 'Workout',
      startTime: DateTime.now().subtract(const Duration(minutes: 1)),
      exercises: const [],
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ActiveWorkoutBanner())),
    );
    // Let the async load surface the banner (running Ticker precludes settle).
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Resume'), findsOneWidget);

    final colors = Theme.of(
      tester.element(find.byType(ActiveWorkoutBanner)),
    ).colorScheme;

    // The route sheet reveals this already-mounted card. It does not run an
    // independent landing/glow timeline that could fight the sheet motion.
    final atRest = _cardOutline(tester);
    expect(atRest.color, colors.outlineVariant);
    expect(atRest.width, 1.0);
    expect(find.byKey(const Key('minimizeLandingOpacity')), findsNothing);

    await tester.pump(const Duration(milliseconds: 800));
    final settled = _cardOutline(tester);
    expect(settled.color, colors.outlineVariant);
    expect(settled.width, 1.0);
  });
}
