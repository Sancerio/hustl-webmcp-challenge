import '../../domain/models/recipe.dart';
import '../../domain/repositories/recipes_repository.dart';
import '../datasources/hustl_backend_nutrition_api.dart';

class RecipesRepositoryImpl implements RecipesRepository {
  RecipesRepositoryImpl({required this.api});

  final HustlBackendNutritionApi api;

  @override
  Future<List<Recipe>> listRecipes() async {
    final items = await api.listRecipes();
    return items.map(Recipe.fromMap).toList(growable: false);
  }

  @override
  Future<Recipe> createRecipe(Recipe recipe) async {
    final created = await api.createRecipe(recipe.toPayload());
    return Recipe.fromMap(created);
  }

  @override
  Future<Recipe> updateRecipe(Recipe recipe) async {
    final updated = await api.updateRecipe(recipe.id, recipe.toPayload());
    return Recipe.fromMap(updated);
  }

  @override
  Future<void> deleteRecipe(String id) async {
    await api.deleteRecipe(id);
  }
}
