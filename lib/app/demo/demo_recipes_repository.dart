import '../../features/nutrition_tracker/domain/models/recipe.dart';
import '../../features/nutrition_tracker/domain/repositories/recipes_repository.dart';

/// Deterministic in-memory [RecipesRepository] for demo mode.
///
/// Seeds one saved recipe so the recipes surface is populated offline.
class DemoRecipesRepository implements RecipesRepository {
  DemoRecipesRepository() : _recipes = {for (final r in _seed) r.id: r};

  final Map<String, Recipe> _recipes;

  static const List<Recipe> _seed = [
    Recipe(
      id: 'demo-recipe-overnight-oats',
      name: 'High-protein overnight oats',
      description: 'Alex\'s reliable breakfast prep.',
      servings: 1,
      items: [
        RecipeItem(
          id: 'demo-recipe-oats-item-1',
          foodId: 'demo-food-oats',
          foodName: 'Rolled oats, dry',
          servingGrams: 60,
          calories: 227,
          proteinGrams: 8,
          carbsGrams: 40,
          fatGrams: 4,
        ),
        RecipeItem(
          id: 'demo-recipe-oats-item-2',
          foodId: 'demo-food-yogurt',
          foodName: 'Greek yogurt, plain',
          servingGrams: 170,
          calories: 100,
          proteinGrams: 17,
          carbsGrams: 6,
          fatGrams: 0.7,
        ),
        RecipeItem(
          id: 'demo-recipe-oats-item-3',
          foodId: 'demo-food-banana',
          foodName: 'Banana',
          servingGrams: 118,
          calories: 105,
          proteinGrams: 1.3,
          carbsGrams: 27,
          fatGrams: 0.4,
        ),
      ],
    ),
  ];

  @override
  Future<List<Recipe>> listRecipes() async => _recipes.values.toList();

  @override
  Future<Recipe> createRecipe(Recipe recipe) async {
    _recipes[recipe.id] = recipe;
    return recipe;
  }

  @override
  Future<Recipe> updateRecipe(Recipe recipe) async {
    _recipes[recipe.id] = recipe;
    return recipe;
  }

  @override
  Future<void> deleteRecipe(String id) async {
    _recipes.remove(id);
  }
}
