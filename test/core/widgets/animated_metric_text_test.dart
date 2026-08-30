import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/widgets/animated_metric_text.dart';

Widget _host(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('formats value with prefix, suffix and fraction digits', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const AnimatedMetricText(
          value: 1234.5,
          fractionDigits: 1,
          prefix: '\$',
          suffix: ' kg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('\$1234.5 kg'), findsOneWidget);
  });

  testWidgets('applies tabular figures to the rendered text', (tester) async {
    await tester.pumpWidget(_host(const AnimatedMetricText(value: 42)));
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(find.text('42'));
    expect(
      text.style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });

  testWidgets('reaches the target instantly when animations disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const AnimatedMetricText(value: 99), disableAnimations: true),
    );
    await tester.pump();

    expect(find.text('99'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('exposes the formatted value via semantics', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      _host(
        const AnimatedMetricText(
          value: 12,
          suffix: ' reps',
          semanticsLabel: 'Reps',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final node = tester.getSemantics(find.byType(AnimatedMetricText));
    expect(node.label, 'Reps');
    expect(node.value, '12 reps');

    handle.dispose();
  });
}
