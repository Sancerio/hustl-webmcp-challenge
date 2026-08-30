import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/widgets/app_progress_ring.dart';

Widget _host(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('exposes percentage value via semantics', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      _host(const AppProgressRing(progress: 0.42, semanticsLabel: 'Calories')),
    );
    await tester.pumpAndSettle();

    final node = tester.getSemantics(find.byType(AppProgressRing));
    expect(node.label, 'Calories');
    expect(node.value, '42%');

    handle.dispose();
  });

  testWidgets('clamps out-of-range progress and exposes clamped value', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      _host(const AppProgressRing(progress: 1.8, semanticsLabel: 'Calories')),
    );
    await tester.pumpAndSettle();

    final node = tester.getSemantics(find.byType(AppProgressRing));
    expect(node.value, '100%');

    handle.dispose();
  });

  testWidgets('omitting semanticsLabel excludes ring from semantics tree', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_host(const AppProgressRing(progress: 0.5)));
    await tester.pumpAndSettle();

    // No semanticsLabel means the ring is decorative — the semantics node
    // should carry neither label nor value.
    final node = tester.getSemantics(find.byType(AppProgressRing));
    expect(node.label, isEmpty);
    expect(node.value, isEmpty);

    handle.dispose();
  });

  testWidgets('wraps painter in a RepaintBoundary', (tester) async {
    await tester.pumpWidget(_host(const AppProgressRing(progress: 0.5)));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppProgressRing),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('renders centre child', (tester) async {
    await tester.pumpWidget(
      _host(const AppProgressRing(progress: 0.5, child: Text('72%'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('72%'), findsOneWidget);
  });

  testWidgets('snaps instantly when animations are disabled', (tester) async {
    await tester.pumpWidget(
      _host(const AppProgressRing(progress: 0.6), disableAnimations: true),
    );
    // No pumpAndSettle needed: with disableAnimations the tween has zero
    // duration, so a single pump reaches the target without pending frames.
    await tester.pump();

    expect(tester.hasRunningAnimations, isFalse);
  });
}
