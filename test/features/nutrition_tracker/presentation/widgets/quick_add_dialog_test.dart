import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/quick_add_dialog.dart';

Future<FoodLogEntry?> _openAndSubmit(
  WidgetTester tester, {
  String? calories,
  required String protein,
  required String carbs,
  required String fat,
}) async {
  FoodLogEntry? result;
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<FoodLogEntry>(
                  context: context,
                  builder: (_) => QuickAddDialog(date: DateTime(2026, 6, 16)),
                );
              },
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

  if (calories != null) {
    await tester.enterText(
      find.widgetWithText(TextField, 'Calories (kcal)'),
      calories,
    );
  }
  await tester.enterText(find.widgetWithText(TextField, 'Protein (g)'), protein);
  await tester.enterText(find.widgetWithText(TextField, 'Carbs (g)'), carbs);
  await tester.enterText(find.widgetWithText(TextField, 'Fat (g)'), fat);
  await tester.tap(find.widgetWithText(FilledButton, 'Add'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('QuickAddDialog calorie defaults', () {
    testWidgets('derives calories from macros (4/4/9) when left blank', (
      tester,
    ) async {
      final entry = await _openAndSubmit(
        tester,
        protein: '30',
        carbs: '40',
        fat: '10',
      );
      // 30*4 + 40*4 + 10*9 = 370.
      expect(entry, isNotNull);
      expect(entry!.calories, 370);
    });

    testWidgets('uses an explicit calorie value over the derived one', (
      tester,
    ) async {
      final entry = await _openAndSubmit(
        tester,
        calories: '500',
        protein: '30',
        carbs: '40',
        fat: '10',
      );
      expect(entry, isNotNull);
      expect(entry!.calories, 500);
    });
  });
}
