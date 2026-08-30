import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/add_food_search_view.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/add_food_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A FoodLogRepository whose getSuggestions returns a fixed payload, so the
// add-food empty state renders the time-of-day picks list + the Recent strip
// deterministically.
class _SuggestionsFoodLogRepository implements FoodLogRepository {
  _SuggestionsFoodLogRepository(this._suggestions);

  final FoodSuggestions _suggestions;

  @override
  Future<FoodSuggestions> getSuggestions({
    required int tzOffsetMinutes,
    int recentLimit = 12,
    int suggestionLimit = 4,
  }) async => _suggestions;

  @override
  Future<List<FoodLogEntry>> getLogsForRange(DateTime start, DateTime end) =>
      throw UnimplementedError();

  @override
  Future<List<FoodLogEntry>> getLogsForDate(DateTime date) async => const [];

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
  }) async => const [];

  @override
  Future<FoodLogEntry> updateEntry(String id, Map<String, dynamic> patch) async {
    throw UnimplementedError();
  }
}

class _NoopFoodRepository implements FoodRepository {
  @override
  Future<void> addFavorite(String foodId) async {}
  @override
  Future<Food> createCustomFood(Food food) async => food;
  @override
  Future<List<Food>> listCustomFoods() async => const [];
  @override
  Future<Set<String>> listFavoriteIds({int limit = 5000}) async => {};
  @override
  Future<List<Food>> listFavorites({int limit = 10}) async => const [];
  @override
  Future<Food?> lookupBarcode(String barcode) async => null;
  @override
  Future<void> removeFavorite(String foodId) async {}
  @override
  Future<List<Food>> searchFoods(String query, {int limit = 20}) async => const [];
  @override
  Future<FoodSearchResult> searchFoodsResult(String query, {int limit = 20}) async =>
      const FoodSearchResult(foods: []);
}

FoodLogEntry _entry(String name, {required int hour, double grams = 100}) {
  final loggedAt = DateTime(2026, 1, 23, hour);
  return FoodLogEntry(
    id: 'log-$name',
    date: DateTime(2026, 1, 23),
    loggedAt: loggedAt,
    servingGrams: grams,
    calories: 150,
    proteinGrams: 12,
    carbsGrams: 18,
    fatGrams: 4,
    foodName: name,
    source: 'self',
  );
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required FoodSuggestions suggestions,
  required void Function(List<FoodLogEntry>) onAdd,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = PreferencesService();
  await prefs.init();

  final getIt = GetIt.instance;
  getIt.registerSingleton<FoodRepository>(_NoopFoodRepository());
  getIt.registerSingleton<FoodLogRepository>(
    _SuggestionsFoodLogRepository(suggestions),
  );
  getIt.registerSingleton<PreferencesService>(prefs);

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => NoTransitionPage(
          child: Scaffold(
            body: AddFoodSheet(
              date: DateTime(2026, 1, 23),
              onAdd: onAdd, // no initialQuery -> empty state
            ),
          ),
        ),
      ),
    ],
  );

  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

void main() {
  final getIt = GetIt.instance;

  tearDown(() async {
    PreferencesService().resetForTests();
    await getIt.reset();
  });

  testWidgets(
    'empty state renders the Recent strip + a vertical time-of-day picks list',
    (tester) async {
      await _pumpSheet(
        tester,
        suggestions: FoodSuggestions(
          suggestions: [_entry('Morning oats', hour: 8, grams: 60)],
          recents: [_entry('Late snack', hour: 22)],
        ),
        onAdd: (_) {},
      );

      // The Recent strip carries the plain recents; the time-of-day SUGGESTIONS
      // become the rich vertical picks list under a meal/time-aware header.
      final picksHeader = timeOfDayPicksHeader(DateTime.now());
      expect(find.text(picksHeader), findsOneWidget);
      expect(find.text('Morning oats'), findsOneWidget);
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Late snack'), findsOneWidget);

      // The pick row carries the macro breakdown (60g · 90 Cal · 12P · 4F · 18C).
      expect(
        find.text('60 g · 150 Cal · 12P · 4F · 18C'),
        findsOneWidget,
      );

      // The Recent strip sits above the vertical picks list.
      expect(
        tester.getTopLeft(find.text('Recent')).dy,
        lessThan(tester.getTopLeft(find.text(picksHeader)).dy),
      );
    },
  );

  testWidgets(
    'Suggested for now is absent when the backend suppresses it (guards)',
    (tester) async {
      await _pumpSheet(
        tester,
        suggestions: FoodSuggestions(
          suggestions: const [], // min-history guards suppressed it
          recents: [_entry('Banana', hour: 12)],
        ),
        onAdd: (_) {},
      );

      // No suggestions -> the picks list falls back to a tasteful prompt (the
      // user has a recent, so the slot is shown rather than hidden).
      expect(
        find.text('Log a few meals and we\u2019ll suggest your usual here.'),
        findsOneWidget,
      );
      // Recent still renders.
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Banana'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping a time-of-day pick row stages it into the plate (re-log flow)',
    (tester) async {
      List<FoodLogEntry>? logged;
      await _pumpSheet(
        tester,
        suggestions: FoodSuggestions(
          suggestions: [_entry('Morning oats', hour: 8, grams: 60)],
          recents: const [],
        ),
        onAdd: (entries) => logged = entries,
      );

      // The pick row's trailing + add re-logs the representative.
      await tester.tap(find.widgetWithIcon(IconButton, Icons.add).last);
      await tester.pumpAndSettle();

      // Plate mode: staging reveals the "Log foods (1)" bar without onAdd yet.
      expect(logged, isNull);
      expect(find.text('Log foods (1)'), findsOneWidget);

      // Committing the plate flows the staged re-log through onAdd at its last
      // serving (60g) — the existing add-food path.
      await tester.tap(find.text('Log foods (1)'));
      await tester.pumpAndSettle();
      expect(logged, isNotNull);
      expect(logged, hasLength(1));
      expect(logged!.first.foodName, 'Morning oats');
      expect(logged!.first.servingGrams, 60);
    },
  );

  testWidgets('tapping a Recent chip stages it into the plate', (tester) async {
    List<FoodLogEntry>? logged;
    await _pumpSheet(
      tester,
      suggestions: FoodSuggestions(
        suggestions: const [],
        recents: [_entry('Late snack', hour: 22, grams: 80)],
      ),
      onAdd: (entries) => logged = entries,
    );

    // The Recent glyph strip re-logs on tap (one-tap staple).
    await tester.tap(find.text('Late snack'));
    await tester.pumpAndSettle();

    expect(logged, isNull);
    expect(find.text('Log foods (1)'), findsOneWidget);

    await tester.tap(find.text('Log foods (1)'));
    await tester.pumpAndSettle();
    expect(logged, isNotNull);
    expect(logged!.first.foodName, 'Late snack');
    expect(logged!.first.servingGrams, 80);
  });
}
