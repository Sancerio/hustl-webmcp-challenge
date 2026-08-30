import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/add_food_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeFoodRepository implements FoodRepository {
  @override
  Future<void> addFavorite(String foodId) async {}

  @override
  Future<Food> createCustomFood(Food food) async => food;

  @override
  Future<List<Food>> listCustomFoods() async => [];

  @override
  Future<Set<String>> listFavoriteIds({int limit = 5000}) async => {};

  @override
  Future<List<Food>> listFavorites({int limit = 10}) async => [];

  @override
  Future<Food?> lookupBarcode(String barcode) async => null;

  @override
  Future<void> removeFavorite(String foodId) async {}

  @override
  Future<List<Food>> searchFoods(String query, {int limit = 20}) async => [];

  @override
  Future<FoodSearchResult> searchFoodsResult(
    String query, {
    int limit = 20,
  }) async => const FoodSearchResult(foods: []);
}

class _FakeFoodLogRepository implements FoodLogRepository {
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
  Future<FoodSuggestions> getSuggestions({
    required int tzOffsetMinutes,
    int recentLimit = 12,
    int suggestionLimit = 4,
  }) async => const FoodSuggestions();

  @override
  Future<List<FoodLogEntry>> getLogsForRange(DateTime start, DateTime end) =>
      throw UnimplementedError();

  @override
  Future<List<FoodLogEntry>> getLogsForDate(DateTime date) async => [];

  @override
  Future<FoodLogEntry> updateEntry(
    String id,
    Map<String, dynamic> patch,
  ) async {
    throw UnimplementedError();
  }
}

void main() {
  final getIt = GetIt.instance;

  tearDown(() async {
    PreferencesService().resetForTests();
    await getIt.reset();
  });

  testWidgets('Logging from AddFoodSheet uses the provided initial time', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    getIt.registerSingleton<FoodRepository>(_FakeFoodRepository());
    getIt.registerSingleton<FoodLogRepository>(_FakeFoodLogRepository());
    getIt.registerSingleton<PreferencesService>(prefs);

    final date = DateTime(2026, 1, 23);
    final initialLoggedAt = DateTime(2026, 1, 23, 15, 30);
    List<FoodLogEntry>? logged;

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => NoTransitionPage(
            child: Scaffold(
              body: AddFoodSheet(
                date: date,
                initialLoggedAt: initialLoggedAt,
                onAdd: (entries) => logged = entries,
              ),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // Quick-add stages into the plate (the sheet's default), so add the food
    // then commit the plate via "Log foods" — the seeded time must survive the
    // round-trip from staging to the single commit.
    await tester.tap(find.text('Quick add'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // Staging hasn't committed yet.
    expect(logged, isNull);

    await tester.tap(find.text('Log foods (1)'));
    await tester.pumpAndSettle();

    expect(logged, isNotNull);
    expect(logged, hasLength(1));
    expect(logged!.first.loggedAt.hour, 15);
    expect(logged!.first.loggedAt.minute, 30);
  });
}
