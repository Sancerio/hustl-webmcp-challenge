import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/active_workout_app_bar_actions.dart';

void main() {
  Widget harness({required double width, double textScale = 1}) {
    return MediaQuery(
      data: MediaQueryData(
        size: Size(width, 780),
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            actions: [
              ActiveWorkoutAppBarActions(
                restControl: const SizedBox(width: 120, height: 40),
                hasNotes: true,
                onMinimize: () {},
                onOpenNotes: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> pumpAt(
    WidgetTester tester, {
    required double width,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 780);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(width: width, textScale: textScale));
  }

  for (final width in <double>[320, 375, 390, 899]) {
    testWidgets('touch layout at ${width.toInt()}px uses icon-only minimize', (
      tester,
    ) async {
      await pumpAt(tester, width: width);
      expect(find.text('Hide'), findsNothing);
      expect(find.text('Minimize'), findsNothing);
      expect(find.byTooltip('Minimize workout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('touch layout remains compact at large text scale', (
    tester,
  ) async {
    await pumpAt(tester, width: 390, textScale: 1.8);
    expect(find.text('Hide'), findsNothing);
    expect(find.text('Minimize'), findsNothing);
    expect(find.byTooltip('Minimize workout'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[900, 1200]) {
    testWidgets('desktop layout at ${width.toInt()}px labels Minimize', (
      tester,
    ) async {
      await pumpAt(tester, width: width);
      expect(find.text('Hide'), findsNothing);
      expect(find.text('Minimize'), findsOneWidget);
      expect(find.byTooltip('Minimize workout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
