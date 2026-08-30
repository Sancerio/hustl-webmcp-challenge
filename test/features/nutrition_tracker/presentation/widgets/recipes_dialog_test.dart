import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/recipe.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/recipes_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/recipes_dialog.dart';

class _FakeRecipesRepository implements RecipesRepository {
  _FakeRecipesRepository(this._recipes);

  final List<Recipe> _recipes;
  Recipe? lastUpdatedRecipe;

  @override
  Future<List<Recipe>> listRecipes() async => List<Recipe>.from(_recipes);

  @override
  Future<Recipe> createRecipe(Recipe recipe) async {
    _recipes.insert(0, recipe);
    return recipe;
  }

  @override
  Future<Recipe> updateRecipe(Recipe recipe) async {
    lastUpdatedRecipe = recipe;
    final index = _recipes.indexWhere((item) => item.id == recipe.id);
    if (index >= 0) _recipes[index] = recipe;
    return recipe;
  }

  @override
  Future<void> deleteRecipe(String id) async {
    _recipes.removeWhere((item) => item.id == id);
  }
}

void main() {
  final getIt = GetIt.instance;

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('RecipesDialog allows editing recipe name', (tester) async {
    final repo = _FakeRecipesRepository([
      const Recipe(
        id: 'recipe-1',
        name: 'Chicken bowl',
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
      ),
    ]);
    getIt.registerSingleton<RecipesRepository>(repo);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => NoTransitionPage(
            child: RecipesDialog(date: DateTime(2026, 2, 2)),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Chicken bowl'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit recipe'));
    await tester.pumpAndSettle();

    // The full recipe editor opens; rename via its name field and save.
    expect(find.text('Edit recipe'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Recipe name'),
      'Edited chicken bowl',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.lastUpdatedRecipe, isNotNull);
    expect(repo.lastUpdatedRecipe!.name, 'Edited chicken bowl');
    expect(find.text('Edited chicken bowl'), findsOneWidget);
  });
}
