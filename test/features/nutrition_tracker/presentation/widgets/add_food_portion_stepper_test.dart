import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/add_food_portion_stepper.dart';

const _food = Food(
  id: 'apple',
  name: 'Apple',
  servingSizeGrams: 100,
  caloriesPer100g: 52,
  proteinPer100g: 0.3,
  carbsPer100g: 14,
  fatPer100g: 0.2,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

/// Pumps the stepper at a fixed physical width (devicePixelRatio 1) so we can
/// assert the layout fits the narrowest phone widths without a RenderFlex
/// overflow. The stepper is top-aligned so its intrinsic height is respected.
Future<void> _pumpAtWidth(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: AddFoodPortionStepper(
            food: _food,
            onAdd: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('stepper seeds from serving size and adds without a dialog', (
    tester,
  ) async {
    double? added;
    await _pump(
      tester,
      AddFoodPortionStepper(
        food: _food,
        onAdd: (g) => added = g,
        onCancel: () {},
      ),
    );

    // Live macro preview is shown inline (no AlertDialog involved).
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('kcal'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(added, 100);
  });

  testWidgets('the + button nudges grams up by the step', (tester) async {
    double? added;
    await _pump(
      tester,
      AddFoodPortionStepper(
        food: _food,
        onAdd: (g) => added = g,
        onCancel: () {},
      ),
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(added, 110);
  });

  testWidgets('cancel does not add', (tester) async {
    var added = false;
    await _pump(
      tester,
      AddFoodPortionStepper(
        food: _food,
        onAdd: (_) => added = true,
        onCancel: () {},
      ),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(added, isFalse);
  });

  testWidgets('the 2x quick multiplier presets grams off the serving', (
    tester,
  ) async {
    double? added;
    await _pump(
      tester,
      AddFoodPortionStepper(
        food: _food,
        onAdd: (g) => added = g,
        onCancel: () {},
      ),
    );

    // The 0.5x / 1x / 2x quick presets are all rendered.
    expect(find.text('0.5x'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.text('2x'), findsOneWidget);

    await tester.tap(find.text('2x'));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pump();
    // Base serving is 100g, so 2x presets 200g in one tap (no text editing).
    expect(added, 200);
  });

  testWidgets('the 0.5x quick multiplier halves the serving', (tester) async {
    double? added;
    await _pump(
      tester,
      AddFoodPortionStepper(
        food: _food,
        onAdd: (g) => added = g,
        onCancel: () {},
      ),
    );

    await tester.tap(find.text('0.5x'));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(added, 50);
  });

  testWidgets('the unit toggle flips grams to servings and back', (
    tester,
  ) async {
    final toggle = find.byKey(const Key('portionUnitToggle'));
    Finder toggleLabel(String text) =>
        find.descendant(of: toggle, matching: find.text(text));

    await _pump(
      tester,
      AddFoodPortionStepper(food: _food, onAdd: (_) {}, onCancel: () {}),
    );

    // Starts in grams; the toggle advertises the current unit.
    expect(toggleLabel('g'), findsOneWidget);
    expect(toggleLabel('serving'), findsNothing);

    await tester.tap(toggle);
    await tester.pump();

    // Now in serving mode: the chip reads "serving" and the field shows "1".
    expect(toggleLabel('serving'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    // Flip back to grams.
    await tester.tap(toggle);
    await tester.pump();
    expect(toggleLabel('g'), findsOneWidget);
  });

  testWidgets('the expanded stepper does not overflow at 320px width', (
    tester,
  ) async {
    await _pumpAtWidth(tester, 320);
    await tester.pump();

    // The action buttons live on their own row, so the stepper controls + the
    // Cancel/Add pair never contend for horizontal room — no RenderFlex
    // overflow at the narrowest supported phone width.
    expect(tester.takeException(), isNull);
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    // Stepper controls and multiplier pills remain intact alongside the actions.
    expect(find.byIcon(Icons.remove), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.byKey(const Key('portionUnitToggle')), findsOneWidget);
  });

  testWidgets('the expanded stepper does not overflow at 360px width', (
    tester,
  ) async {
    await _pumpAtWidth(tester, 360);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('the unit toggle does not switch when no serving size', (
    tester,
  ) async {
    const noServing = Food(
      id: 'banana',
      name: 'Banana',
      caloriesPer100g: 89,
      proteinPer100g: 1.1,
      carbsPer100g: 23,
      fatPer100g: 0.3,
    );
    final toggle = find.byKey(const Key('portionUnitToggle'));

    await _pump(
      tester,
      AddFoodPortionStepper(food: noServing, onAdd: (_) {}, onCancel: () {}),
    );

    // The unit chip still shows 'g' but tapping does not switch to servings
    // because the food carries no serving size.
    expect(
      find.descendant(of: toggle, matching: find.text('g')),
      findsOneWidget,
    );
    await tester.tap(toggle);
    await tester.pump();
    expect(
      find.descendant(of: toggle, matching: find.text('serving')),
      findsNothing,
    );
  });
}
