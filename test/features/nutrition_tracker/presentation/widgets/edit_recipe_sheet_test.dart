import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/recipe.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/recipes_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/edit_recipe_sheet.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/ingredient_picker_sheet.dart';

class _FakeRecipesRepository implements RecipesRepository {
  Recipe? lastCreatedRecipe;
  Recipe? lastUpdatedRecipe;

  @override
  Future<List<Recipe>> listRecipes() async => const [];

  @override
  Future<Recipe> createRecipe(Recipe recipe) async {
    lastCreatedRecipe = recipe;
    return recipe;
  }

  @override
  Future<Recipe> updateRecipe(Recipe recipe) async {
    lastUpdatedRecipe = recipe;
    return recipe;
  }

  @override
  Future<void> deleteRecipe(String id) async {}
}

Recipe _recipe({List<RecipeItem>? items}) => Recipe(
  id: 'recipe-1',
  name: 'Chicken bowl',
  servings: 1,
  items:
      items ??
      const [
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

Future<void> _openNewEditor(WidgetTester tester, {required Recipe seed}) async {
  // EditRecipeSheet treats a blank id as create-mode. Seed it with ingredients
  // so the test exercises the create branch without driving the food picker.
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => EditRecipeSheet.show(context, recipe: seed),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _openEditor(WidgetTester tester, Recipe recipe) async {
  // Tall surface so every ingredient row (and the Add affordance below them)
  // renders without scrolling in the default 800×600 test window.
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => EditRecipeSheet.show(context, recipe: recipe),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  final getIt = GetIt.instance;

  tearDown(() async => getIt.reset());

  test('recipeItemFromFood scales per-100g macros by grams/100', () {
    const food = Food(
      id: 'food-9',
      name: 'Greek yogurt',
      servingSizeGrams: 170,
      caloriesPer100g: 200,
      proteinPer100g: 20,
      carbsPer100g: 10,
      fatPer100g: 5,
      fiberPer100g: 3,
      sugarPer100g: 4,
      sodiumMgPer100g: 100,
    );

    final item = recipeItemFromFood(food, 150);

    expect(item.foodId, 'food-9');
    expect(item.foodName, 'Greek yogurt');
    expect(item.servingGrams, 150);
    // grams/100 = 1.5×.
    expect(item.calories, closeTo(300, 1e-9));
    expect(item.proteinGrams, closeTo(30, 1e-9));
    expect(item.carbsGrams, closeTo(15, 1e-9));
    expect(item.fatGrams, closeTo(7.5, 1e-9));
    expect(item.fiberGrams, closeTo(4.5, 1e-9));
    expect(item.sugarGrams, closeTo(6, 1e-9));
    expect(item.sodiumMg, closeTo(150, 1e-9));
  });

  test('recipeItemFromFood keeps missing macros null, not zero', () {
    const food = Food(id: 'food-10', name: 'Mystery', caloriesPer100g: 90);

    final item = recipeItemFromFood(food, 200);

    expect(item.calories, closeTo(180, 1e-9));
    expect(item.proteinGrams, 0);
    expect(item.fiberGrams, isNull);
    expect(item.sugarGrams, isNull);
    expect(item.sodiumMg, isNull);
  });

  testWidgets('editing grams rescales the ingredient and totals', (
    tester,
  ) async {
    getIt.registerSingleton<RecipesRepository>(_FakeRecipesRepository());
    await _openEditor(tester, _recipe());

    // Doubling 150 g -> 300 g doubles every macro. Tapping the row (its grams
    // pill) opens the amount editor.
    await tester.tap(find.text('150 g'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '300',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Update'));
    await tester.pumpAndSettle();

    expect(find.text('300 g'), findsOneWidget);
    expect(find.text('500 Cal · 70P · 10F · 0C'), findsOneWidget);
    expect(find.text('Recipe total 500 Cal · 70P · 10F · 0C'), findsOneWidget);
  });

  testWidgets('removing an ingredient updates the totals', (tester) async {
    getIt.registerSingleton<RecipesRepository>(_FakeRecipesRepository());
    await _openEditor(
      tester,
      _recipe(
        items: const [
          RecipeItem(
            id: 'item-1',
            foodName: 'Chicken breast',
            servingGrams: 150,
            calories: 250,
            proteinGrams: 35,
            carbsGrams: 0,
            fatGrams: 5,
          ),
          RecipeItem(
            id: 'item-2',
            foodName: 'Rice',
            servingGrams: 100,
            calories: 130,
            proteinGrams: 3,
            carbsGrams: 28,
            fatGrams: 0,
          ),
        ],
      ),
    );

    expect(find.text('Recipe total 380 Cal · 38P · 5F · 28C'), findsOneWidget);

    // Remove the second ingredient (Rice) by swiping its row away.
    await tester.drag(find.text('Rice'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Recipe total 250 Cal · 35P · 5F · 0C'), findsOneWidget);
  });

  testWidgets('save persists the edited name, servings, and items', (
    tester,
  ) async {
    final repo = _FakeRecipesRepository();
    getIt.registerSingleton<RecipesRepository>(repo);
    await _openEditor(tester, _recipe());

    await tester.enterText(
      find.widgetWithText(TextField, 'Recipe name'),
      'Grilled chicken bowl',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Makes how many servings'),
      '2',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final saved = repo.lastUpdatedRecipe;
    expect(saved, isNotNull);
    expect(saved!.name, 'Grilled chicken bowl');
    expect(saved.servings, 2);
    expect(saved.items, hasLength(1));
    expect(saved.id, 'recipe-1');
  });

  testWidgets('the ingredients section offers an Add affordance', (
    tester,
  ) async {
    getIt.registerSingleton<RecipesRepository>(_FakeRecipesRepository());
    await _openEditor(tester, _recipe());

    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets('a blank recipe shows the New recipe title and creates on save', (
    tester,
  ) async {
    final repo = _FakeRecipesRepository();
    getIt.registerSingleton<RecipesRepository>(repo);
    await _openNewEditor(
      tester,
      seed: const Recipe(
        id: '',
        name: '',
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
    );

    expect(find.text('New recipe'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Recipe name'),
      'Lunch bowl',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Makes how many servings'),
      '3',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Create-mode routes through createRecipe, never updateRecipe.
    expect(repo.lastUpdatedRecipe, isNull);
    final created = repo.lastCreatedRecipe;
    expect(created, isNotNull);
    expect(created!.id, '');
    expect(created.name, 'Lunch bowl');
    expect(created.servings, 3);
    expect(created.items, hasLength(1));
  });
}
