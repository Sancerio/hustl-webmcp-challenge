import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';
import 'package:hustl_app/core/widgets/hustl_inline_skeleton.dart';

Widget _host(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('shimmers while mounted with motion enabled', (tester) async {
    await tester.pumpWidget(_host(const AppSkeleton(width: 120)));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.hasRunningAnimations, isTrue);
    expect(find.byType(RepaintBoundary), findsWidgets);
  });

  testWidgets('does not animate when reduce-motion is set', (tester) async {
    await tester.pumpWidget(
      _host(const AppSkeleton(width: 120), disableAnimations: true),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('can render a static placeholder on a dense loading surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const AppSkeleton(width: 120, animate: false)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('exposes a loading semantics label', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_host(const AppSkeleton(width: 80)));

    final node = tester.getSemantics(find.byType(AppSkeleton));
    expect(node.label, 'Loading');

    handle.dispose();
  });

  testWidgets('lines() delegates to HustlInlineSkeleton', (tester) async {
    await tester.pumpWidget(_host(AppSkeleton.lines(rows: 3)));

    expect(find.byType(HustlInlineSkeleton), findsOneWidget);
  });

  testWidgets('circle constructor produces a circular box', (tester) async {
    await tester.pumpWidget(_host(const AppSkeleton.circle(size: 48)));
    await tester.pump(const Duration(milliseconds: 50));

    final box = tester.widget<SizedBox>(
      find.descendant(
        of: find.byType(AppSkeleton),
        matching: find.byType(SizedBox),
      ),
    );
    expect(box.width, 48);
    expect(box.height, 48);
  });
}
