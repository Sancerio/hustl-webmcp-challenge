import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/app/demo/demo_experience_frame.dart';
import 'package:hustl_app/app/theme/app_theme.dart';

void main() {
  testWidgets('labels demo data and invokes the injected reset callback', (
    tester,
  ) async {
    var resetCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: DemoExperienceFrame(
          onReset: () => resetCount += 1,
          child: const Scaffold(body: Text('Overlay route content')),
        ),
      ),
    );

    expect(find.text('Demo data'), findsOneWidget);
    expect(find.text('Reset demo'), findsOneWidget);
    expect(find.text('Overlay route content'), findsOneWidget);

    await tester.tap(find.text('Reset demo'));
    expect(resetCount, 1);
  });

  testWidgets('fits the evaluator controls on a narrow viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: DemoExperienceFrame(
          onReset: () {},
          child: const SizedBox.expand(),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Demo data'), findsOneWidget);
    expect(find.text('Reset demo'), findsOneWidget);
  });
}
