import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/services/token_storage.dart';
import 'package:hustl_app/features/nutrition_tracker/data/datasources/hustl_backend_nutrition_api.dart';
import 'package:hustl_app/features/nutrition_tracker/data/repositories/recipes_repository_impl.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/recipe.dart';

class _FakeTokenStorage extends TokenStorage {
  @override
  Future<String?> getAccessToken() async => null;
}

class _FakeNutritionApi extends HustlBackendNutritionApi {
  _FakeNutritionApi({required this.updateResponse})
    : super(tokens: _FakeTokenStorage(), baseUrl: 'https://example.test');

  final Map<String, dynamic> updateResponse;
  String? updateId;
  Map<String, dynamic>? updatePayload;

  @override
  Future<Map<String, dynamic>> updateRecipe(
    String id,
    Map<String, dynamic> payload,
  ) async {
    updateId = id;
    updatePayload = payload;
    return updateResponse;
  }
}

void main() {
  test('updateRecipe sends payload and maps response', () async {
    final api = _FakeNutritionApi(
      updateResponse: {
        'id': 'recipe-1',
        'name': 'Edited chicken bowl',
        'servings': 1,
        'recipe_items': [
          {
            'id': 'item-1',
            'food_name': 'Chicken breast',
            'serving_grams': 150,
            'calories': 250,
            'protein_grams': 35,
            'carbs_grams': 0,
            'fat_grams': 5,
          },
        ],
      },
    );
    final repo = RecipesRepositoryImpl(api: api);

    const recipe = Recipe(
      id: 'recipe-1',
      name: 'Edited chicken bowl',
      servings: 1,
      items: [
        RecipeItem(
          id: 'item-1',
          foodName: 'Chicken breast',
          servingGrams: 150,
          calories: 250,
          proteinGrams: 35,
          carbsGrams: 0,
          fatGrams: 5,
        ),
      ],
    );

    final updated = await repo.updateRecipe(recipe);

    expect(api.updateId, 'recipe-1');
    expect(api.updatePayload, isNotNull);
    expect(api.updatePayload!['name'], 'Edited chicken bowl');
    final payloadItems = api.updatePayload!['items'] as List;
    expect(payloadItems, hasLength(1));
    expect((payloadItems.first as Map)['foodName'], 'Chicken breast');

    expect(updated.id, 'recipe-1');
    expect(updated.name, 'Edited chicken bowl');
    expect(updated.items, hasLength(1));
    expect(updated.items.first.foodName, 'Chicken breast');
  });
}
