import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/widgets/glass_panel.dart';

Widget _host(
  Widget child, {
  Brightness brightness = Brightness.dark,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('renders its child', (tester) async {
    await tester.pumpWidget(_host(const GlassPanel(child: Text('Live'))));

    expect(find.text('Live'), findsOneWidget);
  });

  testWidgets('uses a blur filter on the default (non-web) path', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const GlassPanel(child: SizedBox(width: 40, height: 40))),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('falls back to an opaque surface when forced', (tester) async {
    await tester.pumpWidget(
      _host(
        const GlassPanel(
          forceOpaque: true,
          child: SizedBox(width: 40, height: 40),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('falls back to opaque when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const GlassPanel(child: SizedBox(width: 40, height: 40)),
        disableAnimations: true,
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('applies the requested blur sigma', (tester) async {
    await tester.pumpWidget(
      _host(
        const GlassPanel(blurSigma: 8, child: SizedBox(width: 40, height: 40)),
      ),
    );

    final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(filter.filter, isA<ImageFilter>());
  });
}
