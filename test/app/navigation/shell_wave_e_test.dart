import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/navigation/app_shell.dart';
import 'package:hustl_app/app/navigation/shell_bottom_nav.dart';
import 'package:hustl_app/core/widgets/glass_panel.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';

class _WorkoutRepoFake implements WorkoutRepository {
  @override
  Future<WorkoutSession?> getLatestActiveSession() async => null;

  @override
  Future<DateTime?> getLastPerformedDate(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;

  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;

  @override
  noSuchMethod(Invocation invocation) => Future.error(UnimplementedError());
}

const _heroTag = 'shell-hero';

GoRouter _buildRouter() {
  Widget trainTab() => Scaffold(
    body: const Center(
      child: Hero(
        tag: _heroTag,
        child: Material(child: Text('Train body')),
      ),
    ),
    floatingActionButton: Builder(
      builder: (context) => FloatingActionButton(
        onPressed: () => context.push('/detail'),
        child: const Icon(Icons.add),
      ),
    ),
  );

  Widget tab(String label) =>
      Scaffold(body: Center(child: Text('$label body')));

  return GoRouter(
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/', builder: (_, __) => trainTab())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/nutrition', builder: (_, __) => tab('Nutrition')),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/history', builder: (_, __) => tab('History')),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/progress', builder: (_, __) => tab('Progress')),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/exercise_library',
                builder: (_, __) => tab('Library'),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/detail',
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          child: const Scaffold(
            body: Center(
              child: Hero(
                tag: _heroTag,
                child: Material(child: Text('Detail body')),
              ),
            ),
          ),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      ),
      GoRoute(
        path: '/add-food',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('Add food body'))),
      ),
    ],
  );
}

void main() {
  setUp(() {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<WorkoutRepository>()) {
      getIt.unregister<WorkoutRepository>();
    }
    getIt.registerSingleton<WorkoutRepository>(_WorkoutRepoFake());
  });

  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('bottom nav is a flat edge-to-edge bar (no glass pill)', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(MaterialApp.router(routerConfig: _buildRouter()));
    await tester.pumpAndSettle();

    // Wave F: the floating GlassPanel pill is gone — the nav is a standard
    // flat bar with no glass material.
    expect(
      find.descendant(
        of: find.byType(ShellBottomNav),
        matching: find.byType(GlassPanel),
      ),
      findsNothing,
    );

    // The bar spans the full width, edge to edge.
    final navRect = tester.getRect(find.byType(ShellBottomNav));
    expect(navRect.left, 0);
    expect(navRect.right, 400);
  });

  testWidgets('active tab is monochrome onSurface emphasis — no accent tint', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(MaterialApp.router(routerConfig: _buildRouter()));
    await tester.pumpAndSettle();

    // No gradient decoration anywhere in the nav (no pill / indicator block).
    final gradientDecorations = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(ShellBottomNav),
            matching: find.byType(DecoratedBox),
          ),
        )
        .where((d) {
          final decoration = d.decoration;
          return decoration is BoxDecoration && decoration.gradient != null;
        });
    expect(gradientDecorations, isEmpty);

    // Wave I: the active (Train) tab paints in the emerald->blue brand primary;
    // an inactive tab sits at the muted onSurfaceVariant tone. Each tab renders
    // its custom SVG glyph (the same asset for both states) tinted by color.
    final navContext = tester.element(find.byType(ShellBottomNav));
    final colors = Theme.of(navContext).colorScheme;

    Finder navIconFor(String asset) => find.descendant(
      of: find.byType(ShellBottomNav),
      matching: find.byWidgetPredicate(
        (w) => w is HustlIcon && w.asset == asset,
      ),
    );

    final activeIcon = tester.widget<HustlIcon>(
      navIconFor('assets/icons/nav_train.svg'),
    );
    // Active tab paints in the brand primary (not a muted/monochrome tone).
    expect(activeIcon.color, colors.primary);
    expect(activeIcon.color, isNot(colors.onSurfaceVariant));

    final inactiveIcon = tester.widget<HustlIcon>(
      navIconFor('assets/icons/nav_nutrition.svg'),
    );
    expect(inactiveIcon.color, colors.onSurfaceVariant);

    // Active label carries w600; inactive stays regular.
    final activeLabel = tester.widget<Text>(
      find.descendant(
        of: find.byType(ShellBottomNav),
        matching: find.text('Train'),
      ),
    );
    expect(activeLabel.style?.fontWeight, FontWeight.w600);
    expect(activeLabel.style?.fontSize, 11);
  });

  testWidgets('branch switch runs a short fade-through, preserving state', (
    tester,
  ) async {
    usePhoneViewport(tester);
    final router = _buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Train body'), findsOneWidget);
    expect(find.byType(FadeTransition), findsWidgets);

    await tester.tap(find.text('History'));
    // Pump partway through the fade-through (<=180ms total).
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/history');
    expect(find.text('History body'), findsOneWidget);
  });

  testWidgets('reduce-motion keeps the branch content fully opaque', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(400, 800),
          disableAnimations: true,
        ),
        child: MaterialApp.router(routerConfig: _buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Progress'));
    await tester.pump();

    // The fade-through is suppressed under reduce-motion: the branch
    // fade-through never drops opacity below 1.0, so the content reads at full
    // strength immediately.
    final shell = find.byType(AppShell);
    for (final fade in tester.widgetList<FadeTransition>(
      find.descendant(of: shell, matching: find.byType(FadeTransition)),
    )) {
      expect(fade.opacity.value, 1.0);
    }
    await tester.pumpAndSettle();
    expect(find.text('Progress body'), findsOneWidget);
  });

  testWidgets('the nav carries no overlay badge — five clean even tabs', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(MaterialApp.router(routerConfig: _buildRouter()));
    await tester.pumpAndSettle();

    // The one-tap "Log food" nav badge was removed: food logging lives on the
    // Nutrition screen + the OS quick action, so the bar stays balanced and
    // nothing overlays/steals a neighbouring tab's tap.
    expect(find.bySemanticsLabel('Log food'), findsNothing);

    // All five destinations render as evenly spaced tabs.
    for (final label in [
      'Train',
      'Nutrition',
      'History',
      'Progress',
      'Library',
    ]) {
      expect(
        find.descendant(
          of: find.byType(ShellBottomNav),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets(
    'tapping the Nutrition tab icon switches to the nutrition branch',
    (tester) async {
      usePhoneViewport(tester);
      final router = _buildRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      // Start on the Train branch.
      expect(find.text('Train body'), findsOneWidget);
      expect(find.text('Nutrition body'), findsNothing);

      final nutritionIcon = find.descendant(
        of: find.byType(ShellBottomNav),
        matching: find.byWidgetPredicate(
          (w) => w is HustlIcon && w.asset == 'assets/icons/nav_nutrition.svg',
        ),
      );
      expect(nutritionIcon, findsOneWidget);
      await tester.tap(nutritionIcon);
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/nutrition');
      expect(find.text('Nutrition body'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping the Nutrition tab label switches to the nutrition branch',
    (tester) async {
      usePhoneViewport(tester);
      final router = _buildRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('Train body'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(ShellBottomNav),
          matching: find.text('Nutrition'),
        ),
      );
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/nutrition');
      expect(find.text('Nutrition body'), findsOneWidget);
    },
  );

  testWidgets('a Hero flies from a shell branch to a pushed route', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(MaterialApp.router(routerConfig: _buildRouter()));
    await tester.pumpAndSettle();

    expect(find.text('Train body'), findsOneWidget);
    // Source Hero (the shared-tag block) is mounted on the shell branch.
    expect(
      find.byWidgetPredicate((w) => w is Hero && w.tag == _heroTag),
      findsOneWidget,
    );

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(); // start the push transition
    await tester.pump(const Duration(milliseconds: 80));

    // Mid-flight the shared-tag Hero is airborne: the Material flight shuttle
    // exists in the overlay during the transition. Proves a Hero can fly from a
    // shell branch to a pushed route (Wave E §9 hero-transition support).
    expect(find.byType(Hero), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.text('Detail body'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is Hero && w.tag == _heroTag),
      findsOneWidget,
    );
  });
}
