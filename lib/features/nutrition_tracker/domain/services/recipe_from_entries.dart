import '../models/food_log_entry.dart';
import '../models/recipe.dart';

/// Builds an unsaved [Recipe] (`id: ''`) from a list of logged entries.
///
/// Pure: no I/O, no `BuildContext`. Each [FoodLogEntry] becomes a [RecipeItem]
/// with its absolute macros copied through unchanged — the entry's snapshot is
/// authoritative, so nothing is rescaled here. Reused by the plate "save as
/// recipe" action and the diary timeline multi-select.
Recipe recipeFromEntries({
  required String name,
  double servings = 1,
  required List<FoodLogEntry> entries,
}) {
  // Stable index-based ids keep rows distinct without depending on the clock,
  // which keeps the result deterministic for callers and tests.
  final base = DateTime.now().microsecondsSinceEpoch;
  final items = List<RecipeItem>.generate(entries.length, (index) {
    final entry = entries[index];
    return RecipeItem(
      id: 'recipe-item-$base-$index',
      foodName: entry.foodName ?? entry.food?.name ?? '',
      servingGrams: entry.servingGrams,
      calories: entry.calories,
      proteinGrams: entry.proteinGrams,
      carbsGrams: entry.carbsGrams,
      fatGrams: entry.fatGrams,
      fiberGrams: entry.fiberGrams,
      sugarGrams: entry.sugarGrams,
      sodiumMg: entry.sodiumMg,
    );
  }, growable: false);

  return Recipe(id: '', name: name, servings: servings, items: items);
}
