import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/meal_scan_target_compare.dart';

Future<void> _pump(
  WidgetTester tester, {
  required double target,
  required double consumedBefore,
  required double meal,
  VoidCallback? onAdjustPortion,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MealScanTargetCompare(
            targetCalories: target,
            consumedBeforeCalories: consumedBefore,
            mealCalories: meal,
            onAdjustPortion: onAdjustPortion,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the day total against the target for a fixed fixture', (
    tester,
  ) async {
    await _pump(tester, target: 2340, consumedBefore: 1100, meal: 620);

    // consumed = 1100 + 620 = 1720, against the 2340 target.
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('1720 / 2340 kcal'), findsOneWidget);
    // +meal added, remaining = 2340 - 1720 = 620, on track.
    expect(
      find.text('+620 kcal added · 620 kcal left — on track'),
      findsOneWidget,
    );
    expect(
      find.text("Your coach factors this into tomorrow's targets."),
      findsOneWidget,
    );
  });

  testWidgets('flags going over the target', (tester) async {
    await _pump(tester, target: 2000, consumedBefore: 1800, meal: 400);

    // consumed = 2200, over by 200.
    expect(find.text('2200 / 2000 kcal'), findsOneWidget);
    expect(find.text('+400 kcal added · 200 kcal over'), findsOneWidget);
  });

  testWidgets('shows the adjust-portion affordance only when wired', (
    tester,
  ) async {
    var tapped = false;
    await _pump(
      tester,
      target: 2340,
      consumedBefore: 1100,
      meal: 620,
      onAdjustPortion: () => tapped = true,
    );

    final adjust = find.text('Looks off? Adjust portion');
    expect(adjust, findsOneWidget);
    await tester.tap(adjust);
    expect(tapped, isTrue);
  });

  testWidgets('hides the adjust-portion affordance when not wired', (
    tester,
  ) async {
    await _pump(tester, target: 2340, consumedBefore: 1100, meal: 620);
    expect(find.text('Looks off? Adjust portion'), findsNothing);
  });
}
