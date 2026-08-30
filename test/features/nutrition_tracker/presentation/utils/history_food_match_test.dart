import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/utils/history_food_match.dart';

FoodLogEntry _entry(
  String name, {
  double servingGrams = 100,
  double calories = 100,
  double protein = 5,
  double carbs = 10,
  double fat = 2,
  Food? food,
}) => FoodLogEntry(
  id: 'e-$name',
  date: DateTime(2026, 1, 23),
  loggedAt: DateTime(2026, 1, 23, 8),
  servingGrams: servingGrams,
  calories: calories,
  proteinGrams: protein,
  carbsGrams: carbs,
  fatGrams: fat,
  foodName: name,
  food: food,
  source: 'self',
);

Food _catalog(String id, String name) => Food(
  id: id,
  name: name,
  source: 'off',
  caloriesPer100g: 50,
  proteinPer100g: 1,
  carbsPer100g: 2,
  fatPer100g: 3,
);

void main() {
  group('historyEntryToFood', () {
    test('backs out per-100g macros from the logged serving', () {
      // 200 g serving with 300 kcal -> 150 kcal/100g, and so on.
      final food = historyEntryToFood(
        _entry(
          'Greek yogurt',
          servingGrams: 200,
          calories: 300,
          protein: 40,
          carbs: 20,
          fat: 10,
        ),
      );
      expect(food.caloriesPer100g, 150);
      expect(food.proteinPer100g, 20);
      expect(food.carbsPer100g, 10);
      expect(food.fatPer100g, 5);
    });

    test('carries the user last-used serving as servingSizeGrams', () {
      final food = historyEntryToFood(_entry('Oats', servingGrams: 80));
      expect(food.servingSizeGrams, 80);
    });

    test('tags the row as a recent so it shows the provenance hint', () {
      expect(historyEntryToFood(_entry('Oats')).trustTier, 'recent');
    });

    test('a zero serving degrades to a per-100g read without dividing by 0', () {
      final food = historyEntryToFood(
        _entry('Mystery', servingGrams: 0, calories: 123),
      );
      expect(food.caloriesPer100g, 123);
      expect(food.servingSizeGrams, isNull);
    });
  });

  group('historyMatches', () {
    test('matches the query by name, case-insensitively (substring)', () {
      final out = historyMatches(
        'chick',
        suggested: const [],
        latest: [_entry('Grilled Chicken'), _entry('Banana')],
      );
      expect(out.map((f) => f.name), ['Grilled Chicken']);
    });

    test('suggestions rank ahead of recents, deduped by food', () {
      // The same food appears as a suggestion and a recent: it should appear
      // once, kept as the (higher-ranked) suggestion which leads the list.
      final out = historyMatches(
        'yogurt',
        suggested: [_entry('Greek yogurt')],
        latest: [_entry('Greek yogurt'), _entry('Vanilla yogurt')],
      );
      expect(out.map((f) => f.name), ['Greek yogurt', 'Vanilla yogurt']);
    });

    test('an empty query matches nothing', () {
      expect(
        historyMatches('  ', suggested: const [], latest: [_entry('Oats')]),
        isEmpty,
      );
    });
  });

  group('mergeCatalogAfterHistory', () {
    test('history leads; catalog-only rows follow', () {
      final history = [historyEntryToFood(_entry('Greek yogurt'))];
      final catalog = [_catalog('c1', 'Protein bar')];
      final merged = mergeCatalogAfterHistory(
        history: history,
        catalog: catalog,
      );
      expect(merged.map((f) => f.name), ['Greek yogurt', 'Protein bar']);
    });

    test('a food in BOTH appears once, kept as the history row', () {
      // History "Greek yogurt" carries the user serving; the catalog dup is
      // dropped, so the surviving row keeps the user's last-used serving.
      final history = [
        historyEntryToFood(_entry('Greek yogurt', servingGrams: 170)),
      ];
      final catalog = [
        _catalog('c-dup', 'Greek yogurt'), // 100g-default catalog dup
        _catalog('c2', 'Almonds'),
      ];
      final merged = mergeCatalogAfterHistory(
        history: history,
        catalog: catalog,
      );
      expect(merged.map((f) => f.name), ['Greek yogurt', 'Almonds']);
      // The single Greek yogurt row is the HISTORY one (user serving + recent).
      final yogurt = merged.firstWhere((f) => f.name == 'Greek yogurt');
      expect(yogurt.servingSizeGrams, 170);
      expect(yogurt.trustTier, 'recent');
    });

    test('with no history, the catalog passes through unchanged', () {
      final catalog = [_catalog('c1', 'Apple'), _catalog('c2', 'Pear')];
      expect(
        mergeCatalogAfterHistory(history: const [], catalog: catalog),
        catalog,
      );
    });
  });
}
