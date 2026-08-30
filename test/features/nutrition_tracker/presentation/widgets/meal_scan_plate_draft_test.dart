import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/meal_scan_result.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/meal_scan_plate_draft.dart';

MealScanItem _item({
  required String name,
  double? grams,
  double? calories,
  double? protein,
  double? carbs,
  double? fat,
  String? macroSource,
  String? matchedName,
}) {
  return MealScanItem(
    name: name,
    quantity: null,
    unit: null,
    grams: grams,
    caloriesKcal: calories,
    proteinGrams: protein,
    carbsGrams: carbs,
    fatGrams: fat,
    macroSource: macroSource,
    matchedName: matchedName,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<MealScanItem> items,
  required ValueChanged<List<MealScanItem>> onChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MealScanPlateDraft(items: items, onChanged: onChanged),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders one editable row per item', (tester) async {
    await _pump(
      tester,
      items: [
        _item(name: 'Chicken breast', grams: 100, calories: 165),
        _item(name: 'White rice', grams: 150, calories: 200),
      ],
      onChanged: (_) {},
    );

    // One grams field (each row owns exactly one) per item.
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Chicken breast'), findsOneWidget);
    expect(find.text('White rice'), findsOneWidget);
  });

  testWidgets('shows Matched vs AI estimate provenance per row', (
    tester,
  ) async {
    await _pump(
      tester,
      items: [
        _item(
          name: 'Chicken breast',
          grams: 100,
          calories: 165,
          macroSource: 'db',
          matchedName: 'Chicken breast, grilled',
        ),
        _item(name: 'Mystery sauce', grams: 30, calories: 90),
      ],
      onChanged: (_) {},
    );

    // DB-matched row carries the "Matched" badge with the resolved food name.
    expect(find.textContaining('Matched'), findsOneWidget);
    expect(find.textContaining('Chicken breast, grilled'), findsOneWidget);
    // Fabricated row carries the "AI estimate" badge.
    expect(find.text('AI estimate'), findsOneWidget);
  });

  testWidgets('removing an item drops its row and reports the new list', (
    tester,
  ) async {
    List<MealScanItem>? reported;
    await _pump(
      tester,
      items: [
        _item(name: 'Chicken breast', grams: 100, calories: 165),
        _item(name: 'White rice', grams: 150, calories: 200),
      ],
      onChanged: (items) => reported = items,
    );

    // Remove the first row.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();

    expect(reported, isNotNull);
    expect(reported!.map((i) => i.name), ['White rice']);
    expect(find.byType(TextField), findsNWidgets(1));
  });

  testWidgets('editing grams rescales macros and updates the reported total', (
    tester,
  ) async {
    List<MealScanItem>? reported;
    await _pump(
      tester,
      items: [
        _item(
          name: 'Chicken breast',
          grams: 100,
          calories: 200,
          protein: 40,
          carbs: 0,
          fat: 5,
        ),
      ],
      onChanged: (items) => reported = items,
    );

    // Double the grams: macros should scale linearly (100g -> 200g).
    await tester.enterText(find.byType(TextField), '200');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(reported, isNotNull);
    final item = reported!.single;
    expect(item.grams, 200);
    expect(item.caloriesKcal, 400);
    expect(item.proteinGrams, 80);
    expect(item.fatGrams, 10);

    // The rescaled calories show on both the row and the running total
    // (single item, so the two values match) — proving the total updated.
    expect(find.textContaining('400 Cal'), findsNWidgets(2));
  });

  testWidgets('removing the last item shows the empty-state copy', (
    tester,
  ) async {
    await _pump(
      tester,
      items: [_item(name: 'Chicken breast', grams: 100, calories: 165)],
      onChanged: (_) {},
    );

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.textContaining('No items left'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
