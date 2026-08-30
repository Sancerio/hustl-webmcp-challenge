import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _SettingsPage extends StatelessWidget {
  const _SettingsPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('settings')));
  }
}

class _WidgetWorkoutsPage extends StatelessWidget {
  const _WidgetWorkoutsPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => context.push('/settings'),
          child: const Text('open-settings'),
        ),
      ),
    );
  }
}

class _NutritionPage extends StatelessWidget {
  const _NutritionPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => context.push('/settings'),
          child: const Text('open-settings'),
        ),
      ),
    );
  }
}

class _RestSkipPage extends StatelessWidget {
  const _RestSkipPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => context.push('/settings'),
          child: const Text('open-settings'),
        ),
      ),
    );
  }
}

class _ErrorLandingPage extends StatelessWidget {
  const _ErrorLandingPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => context.push('/settings'),
          child: const Text('open-settings'),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('Without alias, hustl://widget/workouts lands in errorBuilder', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: 'hustl://widget/workouts',
      errorBuilder: (context, state) => const _ErrorLandingPage(),
      routes: [
        GoRoute(
          path: '/widget/workouts',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: _WidgetWorkoutsPage()),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const _SettingsPage(),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // We should be on the error page because the deep link parses as `/workouts`.
    expect(router.routeInformationProvider.value.uri.path, '/workouts');
    expect(find.byType(_ErrorLandingPage), findsOneWidget);
  });

  testWidgets(
    'Widget deep link alias resolves to /widget/workouts and allows push navigation',
    (tester) async {
      final router = GoRouter(
        initialLocation: 'hustl://widget/workouts',
        errorBuilder: (context, state) => const _ErrorLandingPage(),
        routes: [
          GoRoute(
            path: '/workouts',
            redirect: (context, state) => '/widget/workouts',
          ),
          GoRoute(
            path: '/widget/workouts',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: _WidgetWorkoutsPage()),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const _SettingsPage(),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.path,
        '/widget/workouts',
      );
      expect(find.byType(_WidgetWorkoutsPage), findsOneWidget);

      await tester.tap(find.text('open-settings'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('settings'), findsOneWidget);
    },
  );

  testWidgets('Path-based hustl:///widget/workouts resolves without alias', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: 'hustl:///widget/workouts',
      errorBuilder: (context, state) => const _ErrorLandingPage(),
      routes: [
        GoRoute(
          path: '/widget/workouts',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: _WidgetWorkoutsPage()),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/widget/workouts');
    expect(find.byType(_WidgetWorkoutsPage), findsOneWidget);
  });

  testWidgets('Host-based hustl://widget/nutrition resolves to /nutrition', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: 'hustl://widget/nutrition',
      errorBuilder: (context, state) => const _ErrorLandingPage(),
      routes: [
        GoRoute(
          path: '/nutrition',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: _NutritionPage()),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/nutrition');
    expect(find.byType(_NutritionPage), findsOneWidget);
  });

  testWidgets(
    'Path-based hustl:///widget/nutrition resolves via alias and allows push navigation',
    (tester) async {
      final router = GoRouter(
        initialLocation: 'hustl:///widget/nutrition',
        errorBuilder: (context, state) => const _ErrorLandingPage(),
        routes: [
          GoRoute(
            path: '/widget/nutrition',
            redirect: (context, state) => '/nutrition',
          ),
          GoRoute(
            path: '/nutrition',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: _NutritionPage()),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const _SettingsPage(),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/nutrition');
      expect(find.byType(_NutritionPage), findsOneWidget);

      await tester.tap(find.text('open-settings'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('settings'), findsOneWidget);
    },
  );

  testWidgets('Without alias, hustl://rest/skip lands in errorBuilder', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: 'hustl://rest/skip',
      errorBuilder: (context, state) => const _ErrorLandingPage(),
      routes: [
        GoRoute(
          path: '/rest/skip',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: _RestSkipPage()),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // We should be on the error page because the deep link parses as `/skip`.
    expect(router.routeInformationProvider.value.uri.path, '/skip');
    expect(find.byType(_ErrorLandingPage), findsOneWidget);
  });

  testWidgets(
    'Rest skip deep link resolves to /skip and allows push navigation',
    (tester) async {
      final router = GoRouter(
        initialLocation: 'hustl://rest/skip',
        errorBuilder: (context, state) => const _ErrorLandingPage(),
        routes: [
          GoRoute(
            path: '/skip',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: _RestSkipPage()),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const _SettingsPage(),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/skip');
      expect(find.byType(_RestSkipPage), findsOneWidget);

      await tester.tap(find.text('open-settings'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('settings'), findsOneWidget);
    },
  );

  testWidgets('Path-based hustl:///rest/skip resolves without alias', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: 'hustl:///rest/skip',
      errorBuilder: (context, state) => const _ErrorLandingPage(),
      routes: [
        GoRoute(
          path: '/rest/skip',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: _RestSkipPage()),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/rest/skip');
    expect(find.byType(_RestSkipPage), findsOneWidget);
  });
}
