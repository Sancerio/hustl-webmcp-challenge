import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/add_food_sheet.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/food_entry_avatar.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/food_plate.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Food _food({
  required String id,
  required String name,
  double? servingSizeGrams,
}) {
  return Food(
    id: id,
    name: name,
    source: 'fdc',
    caloriesPer100g: 200,
    proteinPer100g: 20,
    carbsPer100g: 10,
    fatPer100g: 5,
    servingSizeGrams: servingSizeGrams,
  );
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required List<Food> results,
  required void Function(List<FoodLogEntry>) onAdd,
  bool enablePlate = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = PreferencesService();
  await prefs.init();

  final getIt = GetIt.instance;
  getIt.registerSingleton<FoodRepository>(_FakeFoodRepository(results));
  getIt.registerSingleton<FoodLogRepository>(_FakeFoodLogRepository());
  getIt.registerSingleton<PreferencesService>(prefs);

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => NoTransitionPage(
          child: Scaffold(
            body: AddFoodSheet(
              date: DateTime(2026, 1, 23),
              initialQuery: 'chicken',
              onAdd: onAdd,
              enablePlate: enablePlate,
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

  testWidgets('search-first: field, seeded results, scan shortcut, no plate', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      results: [
        _food(id: 'fdc-1', name: 'Grilled Chicken', servingSizeGrams: 150),
      ],
      onAdd: (_) {},
    );

    // The search field is the primary surface and the seeded query populated it.
    expect(find.text('Search for a food'), findsOneWidget);
    expect(find.text('Grilled Chicken'), findsOneWidget);

    // The field's camera shortcut is a single, plain-tap meal scan (no hidden
    // long-press menu).
    expect(find.byTooltip('Scan a meal'), findsOneWidget);
    expect(find.byTooltip('Scan a meal (hold for more)'), findsNothing);

    // The method ribbon surfaces every way in as equal-weight chips.
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Quick add'), findsOneWidget);
    expect(find.text('Describe'), findsOneWidget);
    expect(find.text('Recipes'), findsOneWidget);
    expect(find.text('Copy day'), findsOneWidget);

    // The plate is invisible at idle — no bar with zero items.
    expect(find.text('Plate'), findsNothing);
    expect(find.textContaining('Log plate'), findsNothing);
    expect(find.textContaining('Log foods'), findsNothing);
    // The "Scan a meal" scan-menu option isn't shown until the menu is opened.
    expect(find.text('Scan a meal'), findsNothing);
  });

  testWidgets(
    'plate mode: tapping + STAGES (no onAdd yet) and reveals the bar',
    (tester) async {
      List<FoodLogEntry>? logged;
      await _pumpSheet(
        tester,
        results: [
          _food(id: 'fdc-1', name: 'Grilled Chicken', servingSizeGrams: 150),
        ],
        onAdd: (entries) => logged = entries,
      );

      // The bar is hidden until the first item is staged.
      expect(find.textContaining('Log foods'), findsNothing);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Staging does NOT commit — onAdd has not fired.
      expect(logged, isNull);
      // The "Log foods (N)" bar now feeds back the staged item.
      expect(find.text('Log foods (1)'), findsOneWidget);
      expect(find.text('1 item'), findsOneWidget);

      // The sheet stays open for the next pick.
      expect(find.text('Search for a food'), findsOneWidget);
    },
  );

  testWidgets('plate mode: Log foods commits the whole staged plate', (
    tester,
  ) async {
    List<FoodLogEntry>? logged;
    await _pumpSheet(
      tester,
      results: [
        _food(id: 'fdc-1', name: 'Grilled Chicken', servingSizeGrams: 150),
      ],
      onAdd: (entries) => logged = entries,
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(logged, isNull);

    await tester.tap(find.text('Log foods (1)'));
    await tester.pumpAndSettle();

    // The single commit fires onAdd with the staged entry.
    expect(logged, isNotNull);
    expect(logged, hasLength(1));
    expect(logged!.first.servingGrams, 150);
    expect(logged!.first.source, 'search');
  });

  testWidgets('immediate mode (enablePlate: false): + logs straight away', (
    tester,
  ) async {
    List<FoodLogEntry>? logged;
    await _pumpSheet(
      tester,
      enablePlate: false,
      results: [
        _food(id: 'fdc-1', name: 'Grilled Chicken', servingSizeGrams: 150),
      ],
      onAdd: (entries) => logged = entries,
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // No staging: the pick logs immediately and no plate bar appears.
    expect(logged, isNotNull);
    expect(logged, hasLength(1));
    expect(logged!.first.servingGrams, 150);
    expect(logged!.first.source, 'search');
    expect(find.textContaining('Log foods'), findsNothing);

    // The sheet stays open for the next add.
    expect(find.text('Search for a food'), findsOneWidget);
  });

  testWidgets(
    'immediate mode: + falls back to 100g when serving size is unset',
    (tester) async {
      List<FoodLogEntry>? logged;
      await _pumpSheet(
        tester,
        enablePlate: false,
        results: [_food(id: 'fdc-2', name: 'Plain Rice')],
        onAdd: (entries) => logged = entries,
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(logged, isNotNull);
      expect(logged!.first.servingGrams, 100);
    },
  );

  testWidgets('+ clears the field AND its stale results after a pick', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      results: [
        _food(id: 'fdc-1', name: 'Grilled Chicken', servingSizeGrams: 150),
      ],
      onAdd: (_) {},
    );

    expect(find.text('Grilled Chicken'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // Clearing the field resets the bloc to its empty state, so the stale
    // 'Grilled Chicken' result row disappears with the now-blank box.
    expect(find.text('Grilled Chicken'), findsNothing);
  });

  testWidgets('the Scan chip opens the three capture options in one tap', (
    tester,
  ) async {
    await _pumpSheet(tester, results: const [], onAdd: (_) {});

    // The ribbon's Scan chip is the discoverable home for meal/barcode/label —
    // one tap opens the full menu (no hidden long-press anywhere).
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(find.text('Scan a meal'), findsOneWidget);
    expect(find.text('Barcode'), findsOneWidget);
    expect(find.text('Nutrition label'), findsOneWidget);
  });

  testWidgets(
    'plate footer shows the plate-preview cluster beside the item count',
    (tester) async {
      await _pumpSheet(
        tester,
        results: [
          _food(id: 'fdc-1', name: 'Grilled Chicken', servingSizeGrams: 150),
        ],
        onAdd: (_) {},
      );

      // No selection yet -> no footer, no preview cluster.
      expect(find.byType(PlatePreviewCluster), findsNothing);

      // Stage two picks -> the footer reveals with a two-avatar preview beside
      // the "2 items" count. The quick-add '+' clears the query (and its result
      // rows) after each stage, so re-run the search between picks.
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('1 item'), findsOneWidget);
      expect(find.byType(PlatePreviewCluster), findsOneWidget);
      expect(find.byType(FoodEntryAvatar), findsNWidgets(1));

      await tester.enterText(find.byType(TextField).first, 'chicken');
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('2 items'), findsOneWidget);
      expect(find.byType(PlatePreviewCluster), findsOneWidget);
      expect(find.byType(FoodEntryAvatar), findsNWidgets(2));
      // The commit button stays reachable next to the preview.
      expect(find.text('Log foods (2)'), findsOneWidget);
    },
  );
}
