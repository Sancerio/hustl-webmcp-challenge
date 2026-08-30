import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/edit_food_entry_sheet.dart';

/// Give the test a tall viewport so the bottom sheet (which the app shows with
/// isScrollControlled) lays out without a flex overflow.
void _sizeView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

FoodLogEntry _entry() {
  final day = DateTime(2026, 6, 12, 8, 30);
  return FoodLogEntry(
    id: 'e1',
    date: DateTime(2026, 6, 12),
    loggedAt: day,
    servingGrams: 100,
    calories: 200,
    proteinGrams: 20,
    carbsGrams: 10,
    fatGrams: 5,
    foodName: 'Oats',
  );
}

/// A food-backed entry: macros derive from the linked [Food]'s per-100g values
/// (100/20/10/5 per 100g) rather than editable fields.
FoodLogEntry _foodEntry() {
  final day = DateTime(2026, 6, 12, 8, 30);
  return FoodLogEntry(
    id: 'e2',
    date: DateTime(2026, 6, 12),
    loggedAt: day,
    servingGrams: 100,
    calories: 100,
    proteinGrams: 20,
    carbsGrams: 10,
    fatGrams: 5,
    food: const Food(
      id: 'food-1',
      name: 'Rice',
      caloriesPer100g: 100,
      proteinPer100g: 20,
      carbsPer100g: 10,
      fatPer100g: 5,
    ),
  );
}

/// Opens the sheet inside a one-route GoRouter (so `context.pop` resolves) and
/// returns a getter for the patch captured from [EditFoodEntrySheet.onSave].
/// Unlike [_pumpSheet] this returns BEFORE save so the test can edit fields and
/// tap "Save changes" itself.
Future<Map<String, dynamic>? Function()> _openSheet(
  WidgetTester tester,
  FoodLogEntry entry,
) async {
  Map<String, dynamic>? saved;
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => EditFoodEntrySheet(
                  entry: entry,
                  onSave: (patch) => saved = patch,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => saved;
}

/// Pumps the sheet inside a one-route GoRouter (so its `context.pop` resolves)
/// and captures the patch passed to [EditFoodEntrySheet.onSave].
Future<Map<String, dynamic>?> _pumpSheet(
  WidgetTester tester,
  FoodLogEntry entry,
) async {
  Map<String, dynamic>? saved;
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => EditFoodEntrySheet(
                  entry: entry,
                  onSave: (patch) => saved = patch,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return saved;
}

void main() {
  testWidgets('keeps the original date in the patch when it is unchanged', (
    tester,
  ) async {
    _sizeView(tester);
    Map<String, dynamic>? saved;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => EditFoodEntrySheet(
                    entry: _entry(),
                    onSave: (patch) => saved = patch,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The sheet shows the logged-on date with a "Change date" action.
    expect(find.text('Change date'), findsOneWidget);
    expect(find.textContaining('Logged on'), findsOneWidget);

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    // _submit always sends an explicit date so the backend recomputes the day.
    expect(saved!['date'], '2026-06-12');
  });

  testWidgets('Change date re-dates the entry and sends the new patch date', (
    tester,
  ) async {
    _sizeView(tester);
    Map<String, dynamic>? saved;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => EditFoodEntrySheet(
                    entry: _entry(),
                    onSave: (patch) => saved = patch,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Open the calendar (June 2026 is shown because the entry's day is 6/12),
    // tap an earlier day in the grid, and confirm.
    await tester.tap(find.text('Change date'));
    await tester.pumpAndSettle();
    // Pick the 10th in the month grid (scope to the CalendarDatePicker so the
    // grid cell is unambiguous).
    await tester.tap(
      find.descendant(
        of: find.byType(CalendarDatePicker),
        matching: find.text('10'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // The sheet now shows the new day and submitting carries it in the patch.
    expect(find.textContaining('Jun 10'), findsOneWidget);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!['date'], '2026-06-10');
  });

  testWidgets('the sheet can be opened (smoke)', (tester) async {
    _sizeView(tester);
    final patch = await _pumpSheet(tester, _entry());
    // Nothing saved until the user submits.
    expect(patch, isNull);
    expect(find.text('Edit entry'), findsOneWidget);
  });

  testWidgets('no-food entry: changing serving grams scales calories + macros', (
    tester,
  ) async {
    _sizeView(tester);
    // 100g entry: 200 cal / 20p / 10c / 5f. Doubling the serving to 200g should
    // double every macro on save.
    final entry = FoodLogEntry(
      id: 'm1',
      date: DateTime(2026, 6, 12),
      loggedAt: DateTime(2026, 6, 12, 8, 30),
      servingGrams: 100,
      calories: 200,
      proteinGrams: 10,
      carbsGrams: 20,
      fatGrams: 5,
      foodName: 'Trail mix',
    );
    final getPatch = await _openSheet(tester, entry);

    final gramsField = find.widgetWithText(TextField, 'Serving (g)');
    expect(gramsField, findsOneWidget);
    await tester.enterText(gramsField, '200');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final patch = getPatch();
    expect(patch, isNotNull);
    expect(patch!['servingGrams'], 200);
    expect(patch['calories'], 400);
    expect(patch['proteinGrams'], 20);
    expect(patch['carbsGrams'], 40);
    expect(patch['fatGrams'], 10);
  });

  testWidgets('food-backed entry: changing grams recomputes from per-100g', (
    tester,
  ) async {
    _sizeView(tester);
    // Rice is 100 cal / 20p / 10c / 5f per 100g. At 250g the patch should carry
    // 2.5x the per-100g values.
    final getPatch = await _openSheet(tester, _foodEntry());

    // Food-backed entries show no editable macro fields, only the live preview.
    expect(find.widgetWithText(TextField, 'Calories'), findsNothing);
    expect(find.textContaining('cal'), findsWidgets);

    final gramsField = find.widgetWithText(TextField, 'Serving (g)');
    await tester.enterText(gramsField, '250');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final patch = getPatch();
    expect(patch, isNotNull);
    expect(patch!['servingGrams'], 250);
    expect(patch['calories'], 250);
    expect(patch['proteinGrams'], 50);
    expect(patch['carbsGrams'], 25);
    expect(patch['fatGrams'], 12.5);
  });
}
