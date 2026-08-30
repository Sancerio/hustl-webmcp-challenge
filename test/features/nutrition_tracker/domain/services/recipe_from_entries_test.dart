import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/services/recipe_from_entries.dart';

FoodLogEntry _entry({
  String? foodName,
  double servingGrams = 100,
  double calories = 0,
  double proteinGrams = 0,
  double carbsGrams = 0,
  double fatGrams = 0,
  double? fiberGrams,
  double? sugarGrams,
  double? sodiumMg,
}) {
  return FoodLogEntry(
    id: 'entry',
    date: DateTime(2026, 6, 16),
    loggedAt: DateTime(2026, 6, 16, 12),
    servingGrams: servingGrams,
    calories: calories,
    proteinGrams: proteinGrams,
    carbsGrams: carbsGrams,
    fatGrams: fatGrams,
    fiberGrams: fiberGrams,
    sugarGrams: sugarGrams,
    sodiumMg: sodiumMg,
    foodName: foodName,
  );
}

void main() {
  test('maps each entry to a recipe item, copying macros through', () {
    final recipe = recipeFromEntries(
      name: 'Lunch bowl',
      servings: 2,
      entries: [
        _entry(
          foodName: 'Chicken breast',
          servingGrams: 150,
          calories: 250,
          proteinGrams: 35,
          carbsGrams: 0,
          fatGrams: 5,
          fiberGrams: 1,
          sugarGrams: 2,
          sodiumMg: 120,
        ),
        _entry(
          foodName: 'Rice',
          servingGrams: 100,
          calories: 130,
          proteinGrams: 3,
          carbsGrams: 28,
          fatGrams: 0,
        ),
      ],
    );

    expect(recipe.id, '');
    expect(recipe.name, 'Lunch bowl');
    expect(recipe.servings, 2);
    expect(recipe.items, hasLength(2));

    final first = recipe.items.first;
    expect(first.foodName, 'Chicken breast');
    expect(first.servingGrams, 150);
    expect(first.calories, 250);
    expect(first.proteinGrams, 35);
    expect(first.carbsGrams, 0);
    expect(first.fatGrams, 5);
    expect(first.fiberGrams, 1);
    expect(first.sugarGrams, 2);
    expect(first.sodiumMg, 120);

    // Optional macros stay null rather than collapsing to zero.
    expect(recipe.items[1].fiberGrams, isNull);
    expect(recipe.items[1].sugarGrams, isNull);
    expect(recipe.items[1].sodiumMg, isNull);
  });

  test('defaults servings to 1 and gives each item a distinct id', () {
    final recipe = recipeFromEntries(
      name: 'Snack',
      entries: [
        _entry(foodName: 'Apple'),
        _entry(foodName: 'Banana'),
      ],
    );

    expect(recipe.servings, 1);
    expect(recipe.items.map((i) => i.id).toSet(), hasLength(2));
  });

  test('falls back to an empty food name when none is present', () {
    final recipe = recipeFromEntries(name: 'Mystery', entries: [_entry()]);

    expect(recipe.items.single.foodName, '');
  });

  test('empty entries yield a recipe with no items', () {
    final recipe = recipeFromEntries(name: 'Empty', entries: const []);

    expect(recipe.items, isEmpty);
  });
}
