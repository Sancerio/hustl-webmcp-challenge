import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/navigation/app_shell.dart';
import 'package:hustl_app/app/navigation/shell_bottom_nav.dart';
import 'package:hustl_app/core/widgets/active_workout_banner.dart';
import 'package:hustl_app/core/widgets/main_scaffold.dart';
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

GoRouter _buildShellRouter() {
  Widget tab(String label) => MainScaffold(
    appBar: AppBar(title: Text(label)),
    child: Center(child: Text('$label body')),
  );

  return GoRouter(
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/', builder: (_, __) => tab('Train'))],
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

  testWidgets('Shell shows ShellBottomNav on narrow, no NavigationRail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: _buildShellRouter()),
    );
    await tester.pump();

    expect(find.byType(ShellBottomNav), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('Shell banner avoids duplicate bottom SafeArea inset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: _buildShellRouter()),
    );
    await tester.pump();

    final banner = tester.widget<ActiveWorkoutBanner>(
      find.byType(ActiveWorkoutBanner).first,
    );
    expect(banner.includeBottomSafeArea, isFalse);
  });

  testWidgets('Shell shows NavigationRail on wide, no ShellBottomNav', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: _buildShellRouter()),
    );
    await tester.pump();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(ShellBottomNav), findsNothing);
  });

  testWidgets('NavigationRail destinations stay top-aligned on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: _buildShellRouter()),
    );
    await tester.pump();

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.groupAlignment, -1);
  });

  testWidgets('Bottom nav switches between shell branches', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final router = _buildShellRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Train body'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/history');

    await tester.tap(find.text('Progress'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/progress');
  });
}
