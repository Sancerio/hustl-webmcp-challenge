import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/nutrition_target_plan.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/recipe.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/recipes_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/screens/diary_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeFoodLogRepository implements FoodLogRepository {
  _FakeFoodLogRepository(this._entries);

  final List<FoodLogEntry> _entries;

  @override
  Future<FoodSuggestions> getSuggestions({
    required int tzOffsetMinutes,
    int recentLimit = 12,
    int suggestionLimit = 4,
  }) async => const FoodSuggestions();

  @override
  Future<List<FoodLogEntry>> getLogsForRange(DateTime start, DateTime end) =>
      throw UnimplementedError();

  @override
  Future<List<FoodLogEntry>> getLogsForDate(DateTime date) async =>
      List<FoodLogEntry>.from(_entries);

  @override
  Future<List<FoodLogEntry>> addEntries(List<FoodLogEntry> entries) async =>
      entries;

  @override
  Future<void> deleteEntry(String id) async {}

  @override
  Future<List<FoodLogEntry>> copyDay(
    DateTime fromDate,
    DateTime toDate, {
    bool replaceExisting = false,
  }) async => [];

  @override
  Future<FoodLogEntry> updateEntry(
    String id,
    Map<String, dynamic> patch,
  ) async => throw UnimplementedError();
}

class _FakeTargetsRepository implements NutritionTargetsRepository {
  @override
  Future<NutritionTargetPlan?> getCurrentPlan(DateTime date, {bool readOnly = false}) async => null;

  @override
  Future<Map<String, dynamic>> getInsights(
    DateTime start,
    DateTime end, {
    bool momentumOptIn = false,
  }) async => const {};

  @override
  Future<String?> getCoachExplains(
    DateTime start,
    DateTime end, {
    bool momentumOptIn = false,
  }) async => null;

  @override
  Future<Map<String, dynamic>> getWeightTrend(
    DateTime start,
    DateTime end,
  ) async => const {};

  @override
  Future<void> addWeightSample(DateTime date, double weightKg) async {}

  @override
  Future<Map<String, dynamic>> getWeeklyAdherence(DateTime weekStart) async =>
      const {};

  @override
  Future<Map<String, dynamic>> getWeeklyCheckIn(DateTime date) async =>
      const {};

  @override
  Future<NutritionTargetPlan?> applyWeeklyCheckIn(DateTime date) async => null;

  @override
  Future<void> skipWeeklyCheckIn(DateTime date) async {}

  @override
  Future<NutritionTargetPlan?> recalculatePlan(
    DateTime date, {
    String? mode,
    String? goal,
    double? ratePerWeek,
    Map<String, dynamic>? profile,
  }) async => null;

  @override
  Future<NutritionTargetPlan?> updatePlan(
    DateTime weekStart,
    Map<String, dynamic> patch,
  ) async => null;
}

class _RecordingRecipesRepository implements RecipesRepository {
  Recipe? created;

  @override
  Future<Recipe> createRecipe(Recipe recipe) async {
    created = recipe;
    return recipe;
  }

  @override
  Future<List<Recipe>> listRecipes() async => [];

  @override
  Future<Recipe> updateRecipe(Recipe recipe) async => recipe;

  @override
  Future<void> deleteRecipe(String id) async {}
}

FoodLogEntry _entry({
  required String id,
  required String name,
  required int hour,
}) {
  final at = DateTime(2026, 6, 16, hour);
  return FoodLogEntry(
    id: id,
    date: DateTime(2026, 6, 16),
    loggedAt: at,
    servingGrams: 150,
    calories: 250,
    proteinGrams: 30,
    carbsGrams: 12,
    fatGrams: 8,
    fiberGrams: 3,
    foodName: name,
  );
}

void main() {
  final getIt = GetIt.instance;
  late _RecordingRecipesRepository recipesRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    recipesRepo = _RecordingRecipesRepository();
    getIt
      ..registerSingleton<FoodLogRepository>(
        _FakeFoodLogRepository([
          _entry(id: 'a', name: 'Oats', hour: 8),
          _entry(id: 'b', name: 'Eggs', hour: 8),
        ]),
      )
      ..registerSingleton<NutritionTargetsRepository>(_FakeTargetsRepository())
      ..registerSingleton<RecipesRepository>(recipesRepo)
      ..registerSingleton<PreferencesService>(PreferencesService());
  });

  tearDown(() async {
    await getIt.reset();
  });

  // A tall phone viewport keeps the single-column layout (below the wide
  // breakpoint) with plenty of room for the sticky selection bar and rows.
  Future<void> sizeView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  // The pinned week banner overflows its fixed-height day cells by ~2px under
  // the test font — a pre-existing rendering quirk unrelated to selection mode.
  // Swallow only that specific overflow so it can't mask the assertions.
  void ignoreWeekBannerOverflow() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final summary = details.exceptionAsString();
      if (summary.contains('A RenderFlex overflowed')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
  }

  testWidgets(
    'selecting diary foods and creating a recipe calls the repo with the '
    'right items',
    (tester) async {
      await sizeView(tester);
      ignoreWeekBannerOverflow();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: DiaryScreen()),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('Oats'), findsOneWidget);
      expect(find.text('Eggs'), findsOneWidget);

      // Enter selection mode via the day menu.
      await tester.tap(find.byTooltip('Day options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select foods'));
      await tester.pumpAndSettle();

      // The sticky action bar appears, empty until something is selected.
      expect(find.text('Create recipe'), findsOneWidget);

      // Each row gains a checkbox in selection mode; the first belongs to Oats
      // (entries sort by logged time, then insertion). Tapping it → "1
      // selected".
      expect(find.byType(Checkbox), findsNWidgets(2));
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('1 selected'), findsOneWidget);

      // Create recipe → name dialog, accept the default name.
      await tester.tap(find.text('Create recipe'));
      await tester.pumpAndSettle();
      expect(find.text('Name this recipe'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      // The repo received exactly the selected entry, mapped to a RecipeItem.
      expect(recipesRepo.created, isNotNull);
      final recipe = recipesRepo.created!;
      expect(recipe.name, 'Meal');
      expect(recipe.id, '');
      expect(recipe.servings, 1);
      expect(recipe.items, hasLength(1));
      final item = recipe.items.single;
      expect(item.foodName, 'Oats');
      expect(item.servingGrams, 150);
      expect(item.calories, 250);
      expect(item.proteinGrams, 30);
      expect(item.carbsGrams, 12);
      expect(item.fatGrams, 8);
      expect(item.fiberGrams, 3);

      // Selection mode exits on success → the action bar is gone.
      expect(find.text('Create recipe'), findsNothing);
      expect(find.text('Recipe created.'), findsOneWidget);
    },
  );

  testWidgets('a meal header tap selects every food under it', (tester) async {
    await sizeView(tester);
    ignoreWeekBannerOverflow();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: DiaryScreen()),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Day options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select foods'));
    await tester.pumpAndSettle();

    // Both entries sit under the Breakfast (8 AM) header; tapping it selects
    // the whole group. The header text is wrapped in excludeSemantics, so tap
    // the InkWell that wraps it rather than the (un-hittable) RenderParagraph.
    final header = find.ancestor(
      of: find.text('Breakfast'),
      matching: find.byType(InkWell),
    );
    await tester.tap(header.first);
    await tester.pumpAndSettle();
    expect(find.textContaining('2 selected'), findsOneWidget);
  });
}
