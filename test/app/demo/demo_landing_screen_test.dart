import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/demo/demo_landing_screen.dart';
import 'package:hustl_app/app/theme/app_theme.dart';

void main() {
  testWidgets('explains collaboration and enters the product demo', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/demo',
      routes: [
        GoRoute(
          path: '/demo',
          builder: (context, state) => const DemoLandingScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Text('Demo product')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
    );

    expect(find.text('Hustl WebMCP evaluator'), findsOneWidget);
    expect(find.textContaining('AI proposes, you review'), findsOneWidget);
    expect(find.text('A collaborative coaching loop'), findsOneWidget);
    expect(find.text('Training'), findsOneWidget);
    expect(find.text('Recovery'), findsOneWidget);
    expect(find.text('Nutrition'), findsOneWidget);
    expect(find.text('Coach'), findsOneWidget);

    await tester.tap(find.text('Try the demo'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('Demo product'), findsOneWidget);
  });

  testWidgets('renders without overflow on a narrow evaluator viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const DemoLandingScreen()),
    );

    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Try the demo'), findsOneWidget);
  });
}
