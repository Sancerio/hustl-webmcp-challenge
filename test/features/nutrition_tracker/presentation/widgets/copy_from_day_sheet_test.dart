import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/copy_from_day_sheet.dart';

FoodLogEntry _entry(
  DateTime date, {
  required String id,
  String name = 'Food',
}) => FoodLogEntry(
  id: id,
  date: date,
  loggedAt: date,
  servingGrams: 100,
  calories: 100,
  proteinGrams: 5,
  carbsGrams: 10,
  fatGrams: 3,
  foodName: name,
);

/// Builds a one-route GoRouter (so the sheet's `context.pop` resolves like it
/// does in-app) whose only screen opens the sheet and captures its result.
Future<void> _pumpAndOpen(
  WidgetTester tester, {
  required DateTime target,
  required Future<List<FoodLogEntry>> Function(DateTime) loadDay,
  required void Function(CopyFromDayResult?) onResult,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              onResult(
                await CopyFromDaySheet.show(
                  context,
                  targetDate: target,
                  loadDay: loadDay,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  Future<List<FoodLogEntry>> Function(DateTime) twoFoodsOn(int day) =>
      (d) async => d.day == day
      ? [_entry(d, id: 'a', name: 'Oats'), _entry(d, id: 'b', name: 'Eggs')]
      : <FoodLogEntry>[];

  testWidgets('lists recent days, opens a day, and returns the checked items', (
    tester,
  ) async {
    CopyFromDayResult? result;
    await _pumpAndOpen(
      tester,
      target: DateTime(2026, 1, 23),
      loadDay: twoFoodsOn(22),
      onResult: (r) => result = r,
    );

    // Stage 1: only the day before the target has entries (a trailing "Pick a
    // date" row reaches any earlier day).
    expect(find.text('2 items'), findsOneWidget);
    expect(find.text('Pick a date'), findsOneWidget);
    await tester.tap(find.text('2 items'));
    await tester.pumpAndSettle();

    // Stage 2: both foods, all checked by default, action copies both.
    expect(find.text('Oats'), findsOneWidget);
    expect(find.text('Eggs'), findsOneWidget);
    expect(find.text('Copy 2 items'), findsOneWidget);

    // Uncheck the first item (tap its row) → only the second remains.
    await tester.tap(find.text('Oats'));
    await tester.pumpAndSettle();
    expect(find.text('Copy 1 item'), findsOneWidget);

    await tester.tap(find.text('Copy 1 item'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.sourceDate, DateTime(2026, 1, 22));
    expect(result!.entries.single.id, 'b');
  });

  testWidgets('Pick a date reaches a day beyond the recent window', (
    tester,
  ) async {
    CopyFromDayResult? result;
    // Only a far-back day (well outside the ~30-day quick-pick probe) has food.
    await _pumpAndOpen(
      tester,
      target: DateTime(2026, 6, 12),
      loadDay: (d) async => d.year == 2025 && d.month == 1 && d.day == 5
          ? [_entry(d, id: 'x', name: 'Stew')]
          : <FoodLogEntry>[],
      onResult: (r) => result = r,
    );

    // No recent days, but "Pick a date" is always available.
    expect(find.text('No recent days with food to copy.'), findsOneWidget);
    await tester.tap(find.text('Pick a date'));
    await tester.pumpAndSettle();

    // A calendar opens; type a far-back date via its input mode, then confirm.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '01/05/2025');
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Stage 2 opens on that day; copy its single food.
    expect(find.text('Stew'), findsOneWidget);
    await tester.tap(find.text('Copy 1 item'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.sourceDate, DateTime(2025, 1, 5));
    expect(result!.entries.single.id, 'x');
  });

  testWidgets('Select all / Clear toggles the whole day', (tester) async {
    await _pumpAndOpen(
      tester,
      target: DateTime(2026, 1, 23),
      loadDay: twoFoodsOn(22),
      onResult: (_) {},
    );

    await tester.tap(find.text('2 items'));
    await tester.pumpAndSettle();

    // Everything starts checked → the toggle offers Clear and Copy is enabled.
    expect(find.text('Clear'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    // Now nothing is checked → toggle flips to Select all, Copy is disabled.
    expect(find.text('Select all'), findsOneWidget);
    expect(find.text('Copy 0 items'), findsOneWidget);
    final copyButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(copyButton.onPressed, isNull);
  });
}
