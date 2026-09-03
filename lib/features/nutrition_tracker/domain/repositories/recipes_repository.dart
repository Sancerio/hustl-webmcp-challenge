import '../models/recipe.dart';

abstract class RecipesRepository {
  Future<List<Recipe>> listRecipes();
  Future<Recipe> createRecipe(Recipe recipe);
  Future<Recipe> updateRecipe(Recipe recipe);
  Future<void> deleteRecipe(String id);
}
