import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/widgets/staggered_entrance.dart';

Widget _host(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: child),
    ),
  );
}

List<Widget> _items(int n) =>
    List.generate(n, (i) => Text('item $i', key: ValueKey('item$i')));

/// Effective paint opacity applied to [f] by any ancestor [Opacity] /
/// [FadeTransition]. 1.0 means fully painted; 0.0 means invisible.
double _effectiveOpacity(WidgetTester tester, Finder f) {
  var opacity = 1.0;
  f.first.evaluate().first.visitAncestorElements((ancestor) {
    final w = ancestor.widget;
    if (w is Opacity) opacity *= w.opacity;
    if (w is FadeTransition) opacity *= w.opacity.value;
    return true;
  });
  return opacity;
}

void main() {
  setUp(StaggeredEntrance.resetForTest);

  testWidgets('renders all children', (tester) async {
    await tester.pumpWidget(
      _host(StaggeredEntrance(animationKey: 'a', children: _items(3))),
    );
    await tester.pumpAndSettle();

    expect(find.text('item 0'), findsOneWidget);
    expect(find.text('item 1'), findsOneWidget);
    expect(find.text('item 2'), findsOneWidget);
  });

  testWidgets('animates on first build, static on session revisit', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(StaggeredEntrance(animationKey: 'screen', children: _items(2))),
    );
    // First build schedules entrance animations; let the controller spin up.
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();

    // Rebuild with the same key in the same session: rendered statically, so
    // there is nothing to settle.
    await tester.pumpWidget(
      _host(StaggeredEntrance(animationKey: 'screen', children: _items(2))),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('does not animate under reduce-motion', (tester) async {
    await tester.pumpWidget(
      _host(
        StaggeredEntrance(animationKey: 'b', children: _items(3)),
        disableAnimations: true,
      ),
    );

    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('item 2'), findsOneWidget);
  });

  testWidgets(
    'paints content immediately when tickers are muted (entrance must never '
    'gate visibility)',
    (tester) async {
      // A muted ticker (e.g. a subtree the shell keeps alive but not ticking)
      // means flutter_animate controllers can never advance past opacity 0.
      // Regression for the Biology "blank at the bottom": sections that reserve
      // scroll space but never paint. The entrance must fall back to the static
      // (fully visible) column instead.
      await tester.pumpWidget(
        _host(
          const TickerMode(
            enabled: false,
            child: StaggeredEntrance(
              animationKey: 'muted',
              children: [
                Text('top', key: ValueKey('top')),
                Text('middle', key: ValueKey('middle')),
                Text('bottom', key: ValueKey('bottom')),
              ],
            ),
          ),
        ),
      );

      // No animation is scheduled, and every child is painted at full opacity
      // on the very first frame — even the last one.
      expect(tester.hasRunningAnimations, isFalse);
      for (final key in const ['top', 'middle', 'bottom']) {
        expect(
          _effectiveOpacity(tester, find.byKey(ValueKey(key))),
          1.0,
          reason: '"$key" must be painted (opacity 1) under a muted ticker',
        );
      }
    },
  );

  testWidgets(
    'stays visible after tickers re-enable (does not remount into a stuck '
    'animation)',
    (tester) async {
      final enabled = ValueNotifier<bool>(false);
      addTearDown(enabled.dispose);

      await tester.pumpWidget(
        _host(
          ValueListenableBuilder<bool>(
            valueListenable: enabled,
            builder: (context, on, _) => TickerMode(
              enabled: on,
              child: StaggeredEntrance(
                animationKey: 'gated',
                children: _items(3),
              ),
            ),
          ),
        ),
      );

      // Muted first: static, visible, nothing running.
      expect(tester.hasRunningAnimations, isFalse);
      expect(
        _effectiveOpacity(tester, find.byKey(const ValueKey('item2'))),
        1.0,
      );

      // Enabling tickers rebuilds (TickerMode is inherited). Because the key was
      // recorded as played while muted, the content stays static and visible —
      // it must not flip into an animation that could leave it stuck at 0.
      enabled.value = true;
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpAndSettle();
      expect(
        _effectiveOpacity(tester, find.byKey(const ValueKey('item2'))),
        1.0,
      );
    },
  );

  testWidgets('caps animated items but still renders the overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(StaggeredEntrance(animationKey: 'c', children: _items(12))),
    );
    await tester.pumpAndSettle();

    // All 12 are present even though only the first 8 animate.
    expect(find.text('item 0'), findsOneWidget);
    expect(find.text('item 11'), findsOneWidget);
  });
}
