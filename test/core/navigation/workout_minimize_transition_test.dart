import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/navigation/app_shell.dart';
import 'package:hustl_app/app/navigation/shell_bottom_nav.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/core/navigation/workout_minimize_intent.dart';
import 'package:hustl_app/core/navigation/workout_minimize_sheet_controller.dart';
import 'package:hustl_app/core/navigation/workout_minimize_transition.dart';
import 'package:hustl_app/core/navigation/route_observer.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/active/workout_minimize_drag_handle.dart';
import 'package:hustl_app/features/ai_proposals/services/proposal_events_service.dart';
import 'package:hustl_app/features/ai_proposals/presentation/widgets/pending_proposal_banner.dart';
import 'package:mocktail/mocktail.dart';

class _MockWorkoutRepository extends Mock implements WorkoutRepository {}

Widget _harness({
  required AnimationController controller,
  double width = 390,
  bool reduceMotion = false,
  bool expandFromMiniPlayer = false,
  TextScaler textScaler = TextScaler.noScaling,
  double? desktopTopChromeHeight,
  Widget? child,
}) {
  final transition = Positioned.fill(
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => WorkoutMinimizeTransition(
        animation: controller,
        expandFromMiniPlayer: expandFromMiniPlayer,
        child:
            child ??
            const ColoredBox(
              color: Color(0xFF102030),
              child: Center(child: Text('workout')),
            ),
      ),
    ),
  );

  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 780),
        disableAnimations: reduceMotion,
        textScaler: textScaler,
      ),
      child: Stack(
        children: [
          if (desktopTopChromeHeight != null)
            SizedBox(
              key: AppShell.desktopTopChromeKey,
              height: desktopTopChromeHeight,
            ),
          transition,
        ],
      ),
    ),
  );
}

void main() {
  final getIt = GetIt.instance;
  late _MockWorkoutRepository repository;

  setUp(() async {
    await getIt.reset(dispose: true);
    repository = _MockWorkoutRepository();
    WorkoutMinimizeIntent.consume(WorkoutMinimizeDirection.push);
    WorkoutMinimizeIntent.consume(WorkoutMinimizeDirection.pop);
  });

  tearDown(() async {
    await getIt.reset(dispose: true);
  });

  test('minimize intent arms once and is then consumed', () {
    WorkoutMinimizeIntent.arm(WorkoutMinimizeDirection.pop);
    expect(WorkoutMinimizeIntent.consume(WorkoutMinimizeDirection.pop), isTrue);
    expect(
      WorkoutMinimizeIntent.consume(WorkoutMinimizeDirection.pop),
      isFalse,
    );
  });

  test('workout return locations stay internal and cannot self-loop', () {
    expect(
      workoutReturnLocationFromExtra({
        workoutReturnLocationExtraKey: '/history?range=30',
      }),
      '/history?range=30',
    );
    for (final candidate in [
      'https://example.com/history',
      '//example.com/history',
      '/workout',
      '/workout_session',
    ]) {
      expect(
        workoutReturnLocationFromExtra({
          workoutReturnLocationExtraKey: candidate,
        }),
        isNull,
      );
    }
  });

  test('a mismatched consume clears the minimize intent', () {
    WorkoutMinimizeIntent.arm(WorkoutMinimizeDirection.pop);
    expect(
      WorkoutMinimizeIntent.consume(WorkoutMinimizeDirection.push),
      isFalse,
    );
    expect(
      WorkoutMinimizeIntent.consume(WorkoutMinimizeDirection.pop),
      isFalse,
    );
  });

  testWidgets('armed narrow pop translates the expanded player downward', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: AppMotion.persistentSheet,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller: controller));

    controller.value = 1;
    await tester.pump();
    WorkoutMinimizeIntent.arm(WorkoutMinimizeDirection.pop);
    controller.reverse();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(
      find.byKey(const Key('workoutPlayerSheetTransition')),
      findsOneWidget,
    );
    final sheet = tester.widget<Transform>(
      find.byKey(const Key('workoutPlayerSheet')),
    );
    expect(sheet.transform.getTranslation().y, greaterThan(0));
    expect(
      tester
          .widget<AbsorbPointer>(
            find.byKey(const Key('workoutPlayerSheetInputBlocker')),
          )
          .absorbing,
      isTrue,
    );
    await tester.pumpAndSettle();
  });

  testWidgets(
    'MiniPlayer expansion keeps its full motion after a delayed first frame',
    (tester) async {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: AppMotion.persistentSheet,
        value: 1,
      );
      addTearDown(controller.dispose);

      // Simulate a costly destination build consuming the route's complete
      // animation interval before the first workout frame can paint.
      await tester.pumpWidget(
        _harness(
          controller: controller,
          expandFromMiniPlayer: true,
          child: const ColoredBox(
            key: Key('expandedWorkout'),
            color: Color(0xFF102030),
          ),
        ),
      );

      final firstFrame = tester.widget<Transform>(
        find.byKey(const Key('workoutPlayerSheet')),
      );
      final firstClip = tester
          .widget<ClipRect>(find.byKey(const Key('workoutPlayerLandingClip')))
          .clipper!
          .getClip(const Size(390, 780));
      expect(firstFrame.transform.getTranslation().y, closeTo(640, 0.01));
      expect(
        firstFrame.transform.getTranslation().y,
        closeTo(firstClip.bottom, 0.01),
        reason: 'the first visible tick must begin at the MiniPlayer boundary',
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final middleFrame = tester.widget<Transform>(
        find.byKey(const Key('workoutPlayerSheet')),
      );
      expect(middleFrame.transform.getTranslation().y, greaterThan(0));
      expect(middleFrame.transform.getTranslation().y, lessThan(640));

      await tester.pumpAndSettle();
      expect(find.byKey(const Key('workoutPlayerSheet')), findsNothing);
      expect(find.byKey(const Key('expandedWorkout')), findsOneWidget);
    },
  );

  testWidgets('marked MiniPlayer expansion consumes the legacy push intent', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: AppMotion.persistentSheet,
    );
    addTearDown(controller.dispose);
    WorkoutMinimizeIntent.arm(WorkoutMinimizeDirection.push);

    await tester.pumpWidget(
      _harness(controller: controller, expandFromMiniPlayer: true),
    );
    controller.forward();
    await tester.pump();

    expect(
      WorkoutMinimizeIntent.consume(WorkoutMinimizeDirection.push),
      isFalse,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('direct drag tracks the finger one-to-one', (tester) async {
    late WorkoutMinimizeSheetController sheetController;
    late BuildContext sheetContext;
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: AppMotion.persistentSheet,
      value: 1,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(
        controller: controller,
        child: Builder(
          builder: (context) {
            sheetContext = context;
            sheetController = WorkoutMinimizeSheetScope.maybeOf(context)!;
            return const ColoredBox(color: Color(0xFF102030));
          },
        ),
      ),
    );

    sheetController.dragBy(sheetContext, 0.25);
    await tester.pump();
    final sheet = tester.widget<Transform>(
      find.byKey(const Key('workoutPlayerSheet')),
    );
    expect(sheet.transform.getTranslation().y, closeTo(195, 0.01));

    final landingClip = tester.widget<ClipRect>(
      find.byKey(const Key('workoutPlayerLandingClip')),
    );
    final clip = landingClip.clipper!.getClip(const Size(390, 780));
    expect(
      clip.bottom,
      640,
      reason: 'the fixed player destination is fully revealed after 140px',
    );
  });

  testWidgets('partial drag returns over the full player settle duration', (
    tester,
  ) async {
    late WorkoutMinimizeSheetController sheetController;
    late BuildContext sheetContext;
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: AppMotion.persistentSheet,
      value: 1,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(
        controller: controller,
        child: Builder(
          builder: (context) {
            sheetContext = context;
            sheetController = WorkoutMinimizeSheetScope.maybeOf(context)!;
            return const ColoredBox(color: Color(0xFF102030));
          },
        ),
      ),
    );

    sheetController.dragBy(sheetContext, 0.25);
    await tester.pump();
    unawaited(sheetController.release(sheetContext, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final sheet = tester.widget<Transform>(
      find.byKey(const Key('workoutPlayerSheet')),
    );
    expect(
      sheet.transform.getTranslation().y,
      greaterThan(0),
      reason: 'a partial release must not compress the 300ms settle',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('cancelled drag restores the sheet and unblocks input', (
    tester,
  ) async {
    late WorkoutMinimizeSheetController sheetController;
    late BuildContext sheetContext;
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: AppMotion.persistentSheet,
      value: 1,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(
        controller: controller,
        child: Builder(
          builder: (context) {
            sheetContext = context;
            sheetController = WorkoutMinimizeSheetScope.maybeOf(context)!;
            return const ColoredBox(
              key: Key('cancelledDragWorkout'),
              color: Color(0xFF102030),
            );
          },
        ),
      ),
    );

    sheetController.dragBy(sheetContext, 0.55);
    await tester.pump();
    unawaited(sheetController.cancel(sheetContext));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('workoutPlayerSheet')), findsNothing);
    expect(
      find.byKey(const Key('workoutPlayerSheetInputBlocker')),
      findsNothing,
    );
    expect(find.byKey(const Key('cancelledDragWorkout')), findsOneWidget);
  });

  testWidgets('drag release still settles after crossing the wide breakpoint', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: AppMotion.persistentSheet,
      value: 1,
    );
    addTearDown(controller.dispose);

    Widget buildHarness(double width) => _harness(
      controller: controller,
      width: width,
      child: Builder(
        builder: (context) {
          final sheetController = WorkoutMinimizeSheetScope.maybeOf(context)!;
          return ColoredBox(
            key: const Key('breakpointDragWorkout'),
            color: const Color(0xFF102030),
            child: Align(
              alignment: Alignment.topCenter,
              child: sheetController.canDrag(context)
                  ? WorkoutMinimizeDragHandle(
                      onDragStart: (_) {},
                      onDragUpdate: (details) => sheetController.dragBy(
                        context,
                        details.delta.dy / 780,
                      ),
                      onDragEnd: (details) => unawaited(
                        sheetController.release(
                          context,
                          details.primaryVelocity ?? 0,
                        ),
                      ),
                      onDragCancel: () =>
                          unawaited(sheetController.cancel(context)),
                    )
                  : const SizedBox.shrink(),
            ),
          );
        },
      ),
    );

    await tester.pumpWidget(buildHarness(390));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('workoutMinimizeDragHandle'))),
    );
    await gesture.moveBy(const Offset(0, 195));
    await tester.pump();
    expect(find.byKey(const Key('workoutPlayerSheet')), findsOneWidget);

    await tester.pumpWidget(buildHarness(1200));
    await gesture.cancel();
    await tester.pump();

    expect(find.byKey(const Key('workoutDesktopDockClip')), findsNothing);
    expect(find.byKey(const Key('breakpointDragWorkout')), findsOneWidget);
  });

  testWidgets(
    'drag cancellation clears progress when motion becomes disabled',
    (tester) async {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: AppMotion.persistentSheet,
        value: 1,
      );
      addTearDown(controller.dispose);

      Widget buildHarness({required bool reduceMotion}) => _harness(
        controller: controller,
        reduceMotion: reduceMotion,
        child: Builder(
          builder: (context) {
            final sheetController = WorkoutMinimizeSheetScope.maybeOf(context)!;
            return ColoredBox(
              key: const Key('reducedMotionDragWorkout'),
              color: const Color(0xFF102030),
              child: Align(
                alignment: Alignment.topCenter,
                child: sheetController.canDrag(context)
                    ? WorkoutMinimizeDragHandle(
                        onDragStart: (_) {},
                        onDragUpdate: (details) => sheetController.dragBy(
                          context,
                          details.delta.dy / 780,
                        ),
                        onDragEnd: (details) => unawaited(
                          sheetController.release(
                            context,
                            details.primaryVelocity ?? 0,
                          ),
                        ),
                        onDragCancel: () =>
                            unawaited(sheetController.cancel(context)),
                      )
                    : const SizedBox.shrink(),
              ),
            );
          },
        ),
      );

      await tester.pumpWidget(buildHarness(reduceMotion: false));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('workoutMinimizeDragHandle'))),
      );
      await gesture.moveBy(const Offset(0, 195));
      await tester.pump();
      expect(find.byKey(const Key('workoutPlayerSheet')), findsOneWidget);

      await tester.pumpWidget(buildHarness(reduceMotion: true));
      await gesture.cancel();
      await tester.pumpWidget(buildHarness(reduceMotion: false));
      await tester.pump();

      expect(find.byKey(const Key('workoutPlayerSheet')), findsNothing);
      expect(find.byKey(const Key('reducedMotionDragWorkout')), findsOneWidget);
    },
  );

  testWidgets('early drag reveals landing chrome one-to-one with the finger', (
    tester,
  ) async {
    late WorkoutMinimizeSheetController sheetController;
    late BuildContext sheetContext;
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: AppMotion.persistentSheet,
      value: 1,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(
        controller: controller,
        child: Builder(
          builder: (context) {
            sheetContext = context;
            sheetController = WorkoutMinimizeSheetScope.maybeOf(context)!;
            return const ColoredBox(color: Color(0xFF102030));
          },
        ),
      ),
    );

    sheetController.dragBy(sheetContext, 0.10);
    await tester.pump();

    final landingClip = tester.widget<ClipRect>(
      find.byKey(const Key('workoutPlayerLandingClip')),
    );
    final clip = landingClip.clipper!.getClip(const Size(390, 780));
    expect(clip.bottom, 702);
    expect(
      find.ancestor(
        of: find.byKey(const Key('workoutPlayerSheet')),
        matching: find.byType(ClipRRect),
      ),
      findsNothing,
      reason:
          'persistent-player motion stays square instead of becoming a card',
    );
  });

  testWidgets('direct drag keeps workout content opaque through the exit', (
    tester,
  ) async {
    late WorkoutMinimizeSheetController sheetController;
    late BuildContext sheetContext;
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: AppMotion.persistentSheet,
      value: 1,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(
        controller: controller,
        child: Builder(
          builder: (context) {
            sheetContext = context;
            sheetController = WorkoutMinimizeSheetScope.maybeOf(context)!;
            return const ColoredBox(
              key: Key('opaqueWorkoutContent'),
              color: Color(0xFF102030),
            );
          },
        ),
      ),
    );

    sheetController.dragBy(sheetContext, 0.82);
    await tester.pump();

    expect(find.byKey(const Key('opaqueWorkoutContent')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const Key('opaqueWorkoutContent')),
        matching: find.byType(Opacity),
      ),
      findsNothing,
      reason: 'the workout must not dissolve into a blank surface mid-drag',
    );

    final landingClip = tester.widget<ClipRect>(
      find.byKey(const Key('workoutPlayerLandingClip')),
    );
    final clip = landingClip.clipper!.getClip(const Size(390, 780));
    expect(
      clip.bottom,
      640,
      reason:
          'the moving workout must tuck behind the 80px player and 60px nav',
    );
  });

  testWidgets('mobile landing clip grows with accessibility text scaling', (
    tester,
  ) async {
    late WorkoutMinimizeSheetController sheetController;
    late BuildContext sheetContext;
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: AppMotion.persistentSheet,
      value: 1,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(
        controller: controller,
        textScaler: const TextScaler.linear(2),
        child: Builder(
          builder: (context) {
            sheetContext = context;
            sheetController = WorkoutMinimizeSheetScope.maybeOf(context)!;
            return const ColoredBox(color: Colors.white);
          },
        ),
      ),
    );

    sheetController.dragBy(sheetContext, 0.82);
    await tester.pump();

    final landingClip = tester.widget<ClipRect>(
      find.byKey(const Key('workoutPlayerLandingClip')),
    );
    final clip = landingClip.clipper!.getClip(const Size(390, 780));
    expect(clip.bottom, lessThan(640));
  });

  testWidgets(
    'mobile landing clip includes the rendered pending-proposal banner',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final activeSession = WorkoutSession(
        id: 'session-with-proposal',
        name: 'Proposal-aware workout',
        startTime: DateTime.now().subtract(const Duration(minutes: 8)),
        exercises: const [],
      );
      getIt.registerSingleton<WorkoutRepository>(repository);
      final proposalEvents = ProposalEventsService()..setCount(2);
      getIt.registerSingleton<ProposalEventsService>(proposalEvents);
      addTearDown(proposalEvents.dispose);
      when(
        () => repository.getLatestActiveSession(),
      ).thenAnswer((_) async => activeSession);

      late WorkoutMinimizeSheetController sheetController;
      late BuildContext sheetContext;
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: AppMotion.persistentSheet,
        value: 1,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _harness(
          controller: controller,
          child: Builder(
            builder: (context) {
              sheetContext = context;
              sheetController = WorkoutMinimizeSheetScope.maybeOf(context)!;
              return const ColoredBox(color: Colors.white);
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      sheetController.dragBy(sheetContext, 0.82);
      await tester.pump();

      expect(find.text('2 changes to review'), findsOneWidget);
      final landingClip = tester.widget<ClipRect>(
        find.byKey(const Key('workoutPlayerLandingClip')),
      );
      final clip = landingClip.clipper!.getClip(const Size(390, 780));
      final proposalTop = tester
          .getTopLeft(find.byType(PendingProposalBanner))
          .dy;
      expect(
        clip.bottom,
        closeTo(proposalTop, 0.01),
        reason:
            'the workout must tuck behind proposal, MiniPlayer, and nav chrome',
      );
    },
  );

  testWidgets('wide minimize reveals the top dock without a mobile sheet', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: AppMotion.persistentSheet,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller: controller, width: 1200));

    controller.value = 1;
    await tester.pump();
    WorkoutMinimizeIntent.arm(WorkoutMinimizeDirection.pop);
    controller.reverse();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.byKey(const Key('workoutDesktopDockTransition')),
      findsOneWidget,
    );
    final dock = tester.widget<SlideTransition>(
      find.byKey(const Key('workoutDesktopDockTransition')),
    );
    expect(dock.position.value.dy, lessThan(0));
    expect(
      dock.child,
      isNot(isA<FadeTransition>()),
      reason: 'desktop uses the same spatial player handoff without a dissolve',
    );
    final dockClip = tester.widget<ClipRect>(
      find.byKey(const Key('workoutDesktopDockClip')),
    );
    final clip = dockClip.clipper!.getClip(const Size(1200, 780));
    expect(
      clip.top,
      greaterThan(0),
      reason: 'the moving route must stay behind the stationary top dock',
    );
    expect(find.byKey(const Key('workoutPlayerSheet')), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('wide dock clip follows the rendered shell chrome height', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: AppMotion.persistentSheet,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _harness(
        controller: controller,
        width: 1200,
        desktopTopChromeHeight: 184,
      ),
    );

    controller.value = 1;
    await tester.pump();
    WorkoutMinimizeIntent.arm(WorkoutMinimizeDirection.pop);
    controller.reverse();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final dockClip = tester.widget<ClipRect>(
      find.byKey(const Key('workoutDesktopDockClip')),
    );
    final clip = dockClip.clipper!.getClip(const Size(1200, 780));
    expect(
      clip.top,
      184,
      reason:
          'proposal and text-scale growth must move the clip below all chrome',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('unarmed navigation keeps the standard fade-slide', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: AppMotion.persistentSheet,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller: controller));

    controller.value = 1;
    await tester.pump();
    controller.reverse();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const Key('workoutPlayerSheetTransition')), findsNothing);
    expect(find.byType(SlideTransition), findsWidgets);
    await tester.pumpAndSettle();
  });

  testWidgets('reduce motion renders the workout directly', (tester) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: AppMotion.persistentSheet,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _harness(controller: controller, reduceMotion: true),
    );

    controller.value = 1;
    await tester.pump();
    WorkoutMinimizeIntent.arm(WorkoutMinimizeDirection.pop);
    controller.reverse();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const Key('workoutPlayerSheetTransition')), findsNothing);
    expect(find.byKey(const Key('workoutDesktopDockTransition')), findsNothing);
    expect(find.text('workout'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('reduce motion skips the delayed MiniPlayer expansion', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: AppMotion.persistentSheet,
      value: 1,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _harness(
        controller: controller,
        reduceMotion: true,
        expandFromMiniPlayer: true,
      ),
    );

    expect(find.byKey(const Key('workoutPlayerSheet')), findsNothing);
    expect(find.text('workout'), findsOneWidget);
  });

  testWidgets('go-owned workout minimizes to its explicit shell origin', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/history?range=30',
      routes: [
        GoRoute(
          path: '/history',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: Scaffold(body: Center(child: Text('history'))),
          ),
        ),
        GoRoute(
          path: '/workout_session',
          pageBuilder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            final returnLocation = workoutReturnLocationFromExtra(extra);
            return workoutMinimizePage(
              state,
              Scaffold(
                body: Center(
                  child: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => unawaited(
                        WorkoutMinimizeSheetScope.maybeOf(
                          context,
                        )!.minimize(context),
                      ),
                      child: const Text('minimize'),
                    ),
                  ),
                ),
              ),
              returnLocation: returnLocation,
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    router.go(
      '/workout_session',
      extra: {workoutReturnLocationExtraKey: '/history?range=30'},
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('minimize'));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/history?range=30',
    );
    expect(find.text('history'), findsOneWidget);
  });

  testWidgets(
    'reduced-motion route minimize reveals destination and blocks outgoing input',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/',
        observers: [routeObserver],
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => const CupertinoPage(
              name: appShellRouteName,
              child: Scaffold(body: Center(child: Text('home'))),
            ),
          ),
          GoRoute(
            path: '/workout',
            pageBuilder: (context, state) => workoutMinimizePage(
              state,
              Scaffold(
                body: Center(
                  child: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => unawaited(
                        WorkoutMinimizeSheetScope.maybeOf(
                          context,
                        )!.minimize(context),
                      ),
                      child: const Text('minimize'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      );

      router.push('/workout');
      await tester.pumpAndSettle();
      await tester.tap(find.text('minimize'));
      await tester.pump();

      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(find.text('home'), findsOneWidget);
      expect(find.text('minimize'), findsNothing);
      expect(
        tester
            .widget<AbsorbPointer>(
              find.byKey(const Key('workoutReducedMotionExitBlocker')),
            )
            .absorbing,
        isTrue,
      );

      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('home'), findsOneWidget);
      expect(find.text('minimize'), findsNothing);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('route control collapses before popping to its shell predecessor', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      observers: [routeObserver],
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => const CupertinoPage(
            name: appShellRouteName,
            child: Scaffold(body: Center(child: Text('home'))),
          ),
        ),
        GoRoute(
          path: '/workout',
          pageBuilder: (context, state) => workoutMinimizePage(
            state,
            Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => TextButton(
                    onPressed: () {
                      final controller = WorkoutMinimizeSheetScope.maybeOf(
                        context,
                      )!;
                      controller.dragBy(context, 0.40);
                      unawaited(controller.minimize(context));
                    },
                    child: const Text('minimize'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    router.push('/workout');
    await tester.pumpAndSettle();
    await tester.tap(find.text('minimize'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.byKey(const Key('workoutPlayerSheet')), findsOneWidget);
    final movingSheet = tester.widget<Transform>(
      find.byKey(const Key('workoutPlayerSheet')),
    );
    expect(movingSheet.transform.getTranslation().y, greaterThan(0));
    expect(
      movingSheet.transform.getTranslation().y,
      lessThan(780),
      reason: 'a partial collapse still receives the full 300ms settle',
    );
    expect(find.text('minimize'), findsOneWidget);
    expect(
      find.text('home'),
      findsOneWidget,
      reason: 'the non-opaque workout route must reveal the shell beneath it',
    );
    expect(
      find.byKey(const Key('workoutMinimizeDestinationBackdrop')),
      findsNothing,
      reason: 'a pushed workout must reveal the real destination, not a mock',
    );
    final homeTranslations = tester
        .widgetList<FractionalTranslation>(
          find.ancestor(
            of: find.text('home'),
            matching: find.byType(FractionalTranslation),
          ),
        )
        .map((widget) => widget.translation.dx)
        .toList();
    expect(homeTranslations, isNotEmpty);
    expect(
      homeTranslations,
      everyElement(0),
      reason:
          'the custom workout route must not trigger Cupertino secondary motion',
    );
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      find.byKey(const Key('workoutMinimizeDestinationBackdrop')),
      findsNothing,
      reason: 'the exit must keep revealing the real shell after pop begins',
    );
    expect(find.text('home'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('minimize'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets(
    'overlay-origin collapse paints fallback player before resetting home',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final activeSession = WorkoutSession(
        id: 'session-overlay',
        name: 'Overlay workout',
        startTime: DateTime.now().subtract(const Duration(minutes: 7)),
        exercises: const [],
      );
      getIt.registerSingleton<WorkoutRepository>(repository);
      when(
        () => repository.getLatestActiveSession(),
      ).thenAnswer((_) async => activeSession);

      final router = GoRouter(
        initialLocation: '/templates',
        observers: [routeObserver],
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: Scaffold(body: Center(child: Text('home'))),
            ),
          ),
          GoRoute(
            path: '/templates',
            name: '/templates',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: Scaffold(body: Center(child: Text('template overlay'))),
            ),
          ),
          GoRoute(
            path: '/workout',
            name: '/workout',
            pageBuilder: (context, state) => workoutMinimizePage(
              state,
              Scaffold(
                body: Center(
                  child: Builder(
                    builder: (context) => TextButton(
                      onPressed: () {
                        final controller = WorkoutMinimizeSheetScope.maybeOf(
                          context,
                        )!;
                        unawaited(controller.minimize(context));
                      },
                      child: const Text('minimize'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      router.push('/workout');
      await tester.pumpAndSettle();
      await tester.tap(find.text('minimize'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      await tester.pump();

      expect(
        find.byKey(const Key('workoutMinimizeDestinationBackdrop')),
        findsOneWidget,
      );
      expect(find.text('Overlay workout'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(find.text('home'), findsOneWidget);
      expect(find.text('template overlay'), findsNothing);
    },
  );

  testWidgets(
    'collapse from a direct route paints fallback MiniPlayer and lands home',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semanticsHandle = tester.ensureSemantics();

      final activeSession = WorkoutSession(
        id: 'session-1',
        name: 'Upper body strength',
        startTime: DateTime.now().subtract(const Duration(minutes: 11)),
        exercises: const [],
      );
      getIt.registerSingleton<WorkoutRepository>(repository);
      when(
        () => repository.getLatestActiveSession(),
      ).thenAnswer((_) async => activeSession);

      final router = GoRouter(
        initialLocation: '/workout',
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: Scaffold(body: Center(child: Text('home'))),
            ),
          ),
          GoRoute(
            path: '/workout',
            pageBuilder: (context, state) => workoutMinimizePage(
              state,
              Scaffold(
                body: Center(
                  child: Builder(
                    builder: (context) => TextButton(
                      onPressed: () {
                        final controller = WorkoutMinimizeSheetScope.maybeOf(
                          context,
                        )!;
                        unawaited(controller.minimize(context));
                      },
                      child: const Text('minimize'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Resume'), findsNothing);
      semanticsHandle.dispose();

      await tester.tap(find.text('minimize'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      await tester.pump();

      expect(
        find.byKey(const Key('workoutMinimizeDestinationBackdrop')),
        findsOneWidget,
      );
      expect(find.text('Upper body strength'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.byType(ShellBottomNav), findsOneWidget);
      final miniPlayerContent = tester.getRect(
        find.byKey(const Key('activeWorkoutBannerContent')),
      );
      final shellNavigation = tester.getRect(find.byType(ShellBottomNav));
      expect(
        miniPlayerContent.bottom,
        lessThanOrEqualTo(shellNavigation.top),
        reason: 'the compact player must land directly above real shell chrome',
      );
      expect(shellNavigation.bottom, 780);

      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(find.text('home'), findsOneWidget);
    },
  );

  testWidgets('wide direct route closes toward its fallback dock', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final activeSession = WorkoutSession(
      id: 'session-wide-direct',
      name: 'Wide direct workout',
      startTime: DateTime.now().subtract(const Duration(minutes: 5)),
      exercises: const [],
    );
    getIt.registerSingleton<WorkoutRepository>(repository);
    final proposalEvents = ProposalEventsService()..setCount(2);
    getIt.registerSingleton<ProposalEventsService>(proposalEvents);
    addTearDown(proposalEvents.dispose);
    when(
      () => repository.getLatestActiveSession(),
    ).thenAnswer((_) async => activeSession);

    final router = GoRouter(
      initialLocation: '/workout',
      observers: [routeObserver],
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: Scaffold(body: Center(child: Text('home'))),
          ),
        ),
        GoRoute(
          path: '/workout',
          name: '/workout',
          pageBuilder: (context, state) => workoutMinimizePage(
            state,
            Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => TextButton(
                    onPressed: () {
                      final controller = WorkoutMinimizeSheetScope.maybeOf(
                        context,
                      )!;
                      unawaited(controller.minimize(context));
                    },
                    child: const Text('minimize'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: const Size(1200, 780),
            textScaler: const TextScaler.linear(1.4),
          ),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('minimize'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.byKey(const Key('workoutDesktopDockTransition')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('workoutMinimizeDestinationBackdrop')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('workoutMinimizeFallbackRail')),
      findsOneWidget,
    );
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('2 changes to review'), findsOneWidget);
    expect(find.text('Wide direct workout'), findsOneWidget);
    final fallbackChrome = tester.getRect(
      find.byKey(const Key('workoutMinimizeFallbackTopChrome')),
    );
    final dockClip = tester.widget<ClipRect>(
      find.byKey(const Key('workoutDesktopDockClip')),
    );
    final visibleWorkoutBounds = dockClip.clipper!.getClip(
      const Size(1200, 780),
    );
    expect(
      visibleWorkoutBounds.top,
      closeTo(fallbackChrome.bottom, 0.01),
      reason: 'the workout must pass behind the full measured fallback chrome',
    );

    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('home'), findsOneWidget);
  });
}
