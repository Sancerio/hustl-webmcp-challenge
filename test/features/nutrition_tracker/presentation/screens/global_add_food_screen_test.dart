import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/diary_refresh_signal.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/screens/global_add_food_screen.dart';

class _FakeFoodRepository implements FoodRepository {
  _FakeFoodRepository(this._results);

  final List<Food> _results;

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
  Future<List<Food>> searchFoods(String query, {int limit = 20}) async =>
      _results;

  @override
  Future<FoodSearchResult> searchFoodsResult(
    String query, {
    int limit = 20,
  }) async => FoodSearchResult(foods: _results);
}

/// Records what was persisted so the test can assert the global save path ran.
class _RecordingFoodLogRepository implements FoodLogRepository {
  final List<List<FoodLogEntry>> added = [];

  @override
  Future<List<FoodLogEntry>> addEntries(List<FoodLogEntry> entries) async {
    added.add(entries);
    return entries;
  }

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
  ) async => throw UnimplementedError();
}

Food _food({required String id, required String name, double? serving}) {
  return Food(
    id: id,
    name: name,
    source: 'fdc',
    caloriesPer100g: 200,
    proteinPer100g: 20,
    carbsPer100g: 10,
    fatPer100g: 5,
    servingSizeGrams: serving,
  );
}

void main() {
  final getIt = GetIt.instance;

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets(
    'global save persists entries AND pings the diary refresh signal',
    (tester) async {
      final logRepo = _RecordingFoodLogRepository();
      final signal = DiaryRefreshSignal();
      var refreshCount = 0;
      signal.addListener(() => refreshCount++);

      getIt.registerSingleton<FoodRepository>(
        _FakeFoodRepository([
          _food(id: 'fdc-1', name: 'Grilled Chicken', serving: 150),
        ]),
      );
      getIt.registerSingleton<FoodLogRepository>(logRepo);
      getIt.registerSingleton<DiaryRefreshSignal>(signal);

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => NoTransitionPage(
              child: Scaffold(
                body: Center(
                  child: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => context.push('/add-food'),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/add-food',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: GlobalAddFoodScreen()),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      // Open the global add-food host; its post-frame callback presents the
      // AddFoodSheet.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Drive a log: the sheet is search-first, so just type and one-tap '+'.
      // There's no staging plate — the quick-add logs immediately.
      await tester.enterText(find.byType(TextField), 'chicken');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // The save reached the repository and the diary refresh signal fired so a
      // live diary reloads and shows the new food.
      expect(logRepo.added, hasLength(1));
      expect(logRepo.added.first, hasLength(1));
      expect(refreshCount, 1);
    },
  );
}
