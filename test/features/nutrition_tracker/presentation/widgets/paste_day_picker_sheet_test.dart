import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/paste_day_picker_sheet.dart';

/// Opens the paste picker from a one-route GoRouter (so `context.pop` resolves)
/// and captures the chosen dates.
Future<void> _pumpAndOpen(
  WidgetTester tester, {
  required DateTime fromDate,
  required void Function(List<DateTime>?) onResult,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              onResult(
                await PasteDayPickerSheet.show(
                  context,
                  fromDate: fromDate,
                  foodCount: 2,
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
  testWidgets('offers PAST days (yesterday) as well as future days', (
    tester,
  ) async {
    // A tall viewport so the long day list lays out for tapping.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    List<DateTime>? result;
    await _pumpAndOpen(tester, fromDate: today, onResult: (r) => result = r);

    // Yesterday (a PAST day — previously impossible) sits in the list. Scroll
    // it into view; Tomorrow proves future days are still offered too.
    await tester.scrollUntilVisible(
      find.text('Yesterday'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Yesterday'), findsOneWidget);

    // Tick Yesterday and paste.
    await tester.tap(find.text('Yesterday'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Paste to 1 day'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.single, today.subtract(const Duration(days: 1)));
  });
}
