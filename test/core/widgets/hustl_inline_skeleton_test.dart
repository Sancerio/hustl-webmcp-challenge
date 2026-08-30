import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/widgets/hustl_inline_skeleton.dart';

void main() {
  testWidgets('exposes a loading semantics label', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HustlInlineSkeleton())),
    );

    final node = tester.getSemantics(find.byType(HustlInlineSkeleton));
    expect(node, matchesSemantics(label: 'Loading content'));
    expect(
      node,
      isNot(matchesSemantics(label: 'Loading content', isLiveRegion: true)),
    );

    semanticsHandle.dispose();
  });

  testWidgets('can opt into live-region announcements', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HustlInlineSkeleton(liveRegion: true)),
      ),
    );

    final node = tester.getSemantics(find.byType(HustlInlineSkeleton));
    expect(
      node,
      matchesSemantics(label: 'Loading content', isLiveRegion: true),
    );

    semanticsHandle.dispose();
  });
}
