import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/bloc/food_search_bloc.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/bloc/food_search_event.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/bloc/food_search_state.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/add_food_search_view.dart';

class _MockFoodSearchBloc extends MockBloc<FoodSearchEvent, FoodSearchState>
    implements FoodSearchBloc {}

Food _food({
  required String id,
  required String name,
  String source = 'off',
  String? trustTier,
  bool macrosIncomplete = false,
  bool withMacros = true,
  int? loggedCount,
}) {
  return Food(
    id: id,
    name: name,
    source: source,
    caloriesPer100g: withMacros ? 100 : null,
    proteinPer100g: withMacros ? 10 : null,
    carbsPer100g: withMacros ? 20 : null,
    fatPer100g: withMacros ? 5 : null,
    trustTier: trustTier,
    macrosIncomplete: macrosIncomplete,
    loggedCount: loggedCount,
  );
}

Future<void> _pumpWithResults(WidgetTester tester, List<Food> results) async {
  final bloc = _MockFoodSearchBloc();
  final state = FoodSearchState(query: 'protein', results: results);
  when(() => bloc.state).thenReturn(state);
  when(() => bloc.stream).thenAnswer((_) => Stream.value(state));

  // A non-empty query so the live "Results" section renders.
  final controller = TextEditingController(text: 'protein');
  final focusNode = FocusNode();
  addTearDown(controller.dispose);
  addTearDown(focusNode.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: BlocProvider<FoodSearchBloc>.value(
          value: bloc,
          child: AddFoodSearchView(
            controller: controller,
            focusNode: focusNode,
            latest: const [],
            favorites: const [],
            isFavorite: (_) => false,
            onAddFood: (_, __) {},
            onAddLatest: (_) {},
            onToggleFavorite: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('camera icon (tap-only meal scan)', () {
    testWidgets('a plain tap fires onScan and there is no hidden menu gesture', (
      tester,
    ) async {
      final bloc = _MockFoodSearchBloc();
      const state = FoodSearchState(query: '', results: []);
      when(() => bloc.state).thenReturn(state);
      when(() => bloc.stream).thenAnswer((_) => Stream.value(state));

      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      var scanTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: BlocProvider<FoodSearchBloc>.value(
              value: bloc,
              child: AddFoodSearchView(
                controller: controller,
                focusNode: focusNode,
                latest: const [],
                favorites: const [],
                isFavorite: (_) => false,
                onAddFood: (_, __) {},
                onAddLatest: (_) {},
                onToggleFavorite: (_) {},
                onScan: () => scanTaps++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // The camera icon is a single-purpose shortcut: plain tap = scan a meal.
      expect(find.byTooltip('Scan a meal'), findsOneWidget);
      expect(find.byTooltip('Scan a meal (hold for more)'), findsNothing);

      await tester.tap(find.byTooltip('Scan a meal'));
      await tester.pump();
      expect(scanTaps, 1);
    });
  });

  group('foodSourceBadgeLabel', () {
    test('credits Open Food Facts for ODbL (off) rows', () {
      expect(foodSourceBadgeLabel('off'), 'Source: Open Food Facts');
      expect(foodSourceBadgeLabel('OFF'), 'Source: Open Food Facts');
      expect(foodSourceBadgeLabel(' off '), 'Source: Open Food Facts');
    });

    test('credits USDA for FoodData Central (fdc) rows', () {
      expect(foodSourceBadgeLabel('fdc'), 'Source: USDA');
      expect(foodSourceBadgeLabel('FDC'), 'Source: USDA');
    });

    test('shows no badge for custom or unknown sources', () {
      expect(foodSourceBadgeLabel('custom'), isNull);
      expect(foodSourceBadgeLabel('barcode'), isNull);
      expect(foodSourceBadgeLabel(''), isNull);
    });
  });

  group('trust badge on search results', () {
    testWidgets('a verified result shows the "Verified" badge', (tester) async {
      await _pumpWithResults(tester, [
        _food(
          id: 'v1',
          name: 'Foundation Chicken',
          source: 'fdc',
          trustTier: 'verified',
        ),
      ]);

      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Macros incomplete'), findsNothing);
    });

    testWidgets('a community result shows NO trust badge', (tester) async {
      await _pumpWithResults(tester, [
        _food(
          id: 'c1',
          name: 'Community Cola',
          source: 'off',
          trustTier: 'community',
        ),
      ]);

      // Community/custom/null tiers stay uncluttered: no Verified chip, and
      // (since macros are complete) no incomplete hint either.
      expect(find.text('Verified'), findsNothing);
      expect(find.text('Macros incomplete'), findsNothing);
      // The ODbL source attribution still shows for OFF rows.
      expect(find.text('Source: Open Food Facts'), findsOneWidget);
    });

    testWidgets(
      'a macros-incomplete community result shows the muted hint, not Verified',
      (tester) async {
        await _pumpWithResults(tester, [
          _food(
            id: 'i1',
            name: 'Mystery Snack',
            source: 'off',
            trustTier: 'community',
            macrosIncomplete: true,
            withMacros: false,
          ),
        ]);

        expect(find.text('Verified'), findsNothing);
        // The subtitle line and the badge both surface the incomplete state;
        // assert at least one "Macros incomplete" is present.
        expect(find.text('Macros incomplete'), findsWidgets);
      },
    );

    testWidgets('a null trustTier (legacy row) shows no Verified badge', (
      tester,
    ) async {
      await _pumpWithResults(tester, [
        _food(id: 'n1', name: 'Legacy Food', source: 'off'),
      ]);

      expect(find.text('Verified'), findsNothing);
    });
  });

  group('recents gating by active query', () {
    FoodLogEntry recent(String name) => FoodLogEntry(
      id: 'r-$name',
      date: DateTime(2024, 6, 15),
      loggedAt: DateTime(2024, 6, 15),
      servingGrams: 100,
      calories: 97,
      proteinGrams: 1,
      carbsGrams: 23,
      fatGrams: 0,
      foodName: name,
    );

    Future<void> pump(
      WidgetTester tester, {
      required String query,
      required List<FoodLogEntry> latest,
    }) async {
      final bloc = _MockFoodSearchBloc();
      final state = FoodSearchState(query: query, results: const []);
      when(() => bloc.state).thenReturn(state);
      when(() => bloc.stream).thenAnswer((_) => Stream.value(state));
      final controller = TextEditingController(text: query);
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: BlocProvider<FoodSearchBloc>.value(
              value: bloc,
              child: AddFoodSearchView(
                controller: controller,
                focusNode: focusNode,
                latest: latest,
                favorites: const [],
                isFavorite: (_) => false,
                onAddFood: (_, __) {},
                onAddLatest: (_) {},
                onToggleFavorite: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('hides Recent while a query is active', (tester) async {
      await pump(tester, query: 'avocado', latest: [recent('Banana, raw')]);
      // Searching "avocado" must not surface unrelated recent foods.
      expect(find.text('Recent'), findsNothing);
    });

    testWidgets('shows Recent on the empty-query landing state', (
      tester,
    ) async {
      await pump(tester, query: '', latest: [recent('Banana, raw')]);
      expect(find.text('Recent'), findsOneWidget);
    });
  });

  group('favorite affordance gating by food id', () {
    testWidgets('a backend-UUID result shows the favorite star', (
      tester,
    ) async {
      await _pumpWithResults(tester, [
        _food(
          id: '123e4567-e89b-12d3-a456-426614174000',
          name: 'Backend Food',
          source: 'fdc',
        ),
      ]);

      expect(find.byIcon(Icons.star_border), findsOneWidget);
    });

    testWidgets('a local asset-id result hides the favorite star', (
      tester,
    ) async {
      await _pumpWithResults(tester, [
        _food(id: 'fdc-171705', name: 'Local Generic Food', source: 'fdc'),
      ]);

      // On-device generic foods can't be favorited (no resolvable backend id),
      // so neither the empty nor filled star renders.
      expect(find.byIcon(Icons.star_border), findsNothing);
      expect(find.byIcon(Icons.star), findsNothing);
      // The serving-adjust affordance still renders (no onAddDefault here, so
      // the prominent one-tap "+" is absent; the tune toggle opens the portion
      // stepper to add).
      expect(find.byIcon(Icons.tune), findsOneWidget);
    });
  });

group('empty landing: Recent strip + time-of-day picks split', () {
    FoodLogEntry entry(String name) => FoodLogEntry(
      id: name,
      date: DateTime(2026, 1, 23),
      loggedAt: DateTime(2026, 1, 23, 8),
      servingGrams: 100,
      calories: 100,
      proteinGrams: 5,
      carbsGrams: 10,
      fatGrams: 2,
      foodName: name,
      source: 'self',
    );

    Future<void> pump(
      WidgetTester tester, {
      required List<FoodLogEntry> suggested,
      required List<FoodLogEntry> latest,
    }) async {
      final bloc = _MockFoodSearchBloc();
      const state = FoodSearchState(query: '', results: []);
      when(() => bloc.state).thenReturn(state);
      when(() => bloc.stream).thenAnswer((_) => Stream.value(state));

      final controller = TextEditingController(); // empty query -> empty state
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: BlocProvider<FoodSearchBloc>.value(
              value: bloc,
              child: AddFoodSearchView(
                controller: controller,
                focusNode: focusNode,
                suggested: suggested,
                latest: latest,
                favorites: const [],
                isFavorite: (_) => false,
                onAddFood: (_, __) {},
                onAddLatest: (_) {},
                onToggleFavorite: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets(
      'recents fill the strip; suggestions fill the vertical picks list below it',
      (tester) async {
        await pump(
          tester,
          suggested: [entry('Morning coffee')],
          latest: [entry('Late snack')],
        );

        // The strip keeps the plain recents under the "Recent" header; the
        // time-of-day suggestions move to the vertical picks list under their
        // own meal/time-aware header — no separate "Suggested for now" section.
        final picksHeader = timeOfDayPicksHeader(DateTime.now());
        expect(find.text('Recent'), findsOneWidget);
        expect(find.text(picksHeader), findsOneWidget);
        expect(find.text('Suggested for now'), findsNothing);

        expect(find.text('Morning coffee'), findsOneWidget); // suggestion -> picks
        expect(find.text('Late snack'), findsOneWidget); // recent -> strip

        // The Recent strip sits ABOVE the vertical picks list.
        expect(
          tester.getTopLeft(find.text('Late snack')).dy,
          lessThan(tester.getTopLeft(find.text('Morning coffee')).dy),
        );
      },
    );

    testWidgets(
      'no sparkle when the picks list carries the suggestions (not the strip)',
      (tester) async {
        await pump(
          tester,
          suggested: [entry('Morning coffee')],
          latest: [entry('Late snack')],
        );

        // The sparkle is a strip-chip decoration; with suggestions in the
        // vertical picks list the strip is recents-only, so no sparkle shows.
        expect(find.byIcon(Icons.auto_awesome), findsNothing);
        // The pick carries a one-tap add instead.
        expect(find.byTooltip('Add'), findsWidgets);
      },
    );

    testWidgets('no recents: just the vertical picks list, no Recent strip', (
      tester,
    ) async {
      await pump(
        tester,
        suggested: [entry('Morning coffee')],
        latest: const [],
      );

      // Nothing for the strip to show, so the "Recent" header is absent; the
      // suggestion still renders in the vertical picks list.
      expect(find.text('Recent'), findsNothing);
      expect(find.text(timeOfDayPicksHeader(DateTime.now())), findsOneWidget);
      expect(find.text('Morning coffee'), findsOneWidget);
    });

    testWidgets(
      'no suggestions: the legacy merged strip + a picks empty prompt',
      (tester) async {
        await pump(
          tester,
          suggested: const [], // thin history -> guards suppressed it
          latest: [entry('Late snack')],
        );

        // With no picks the strip falls back to the legacy merged behavior
        // (recents under "Recent", no sparkle), and the picks slot shows a
        // tasteful prompt rather than a blank gap.
        expect(find.text('Recent'), findsOneWidget);
        expect(find.text('Late snack'), findsOneWidget);
        expect(find.byIcon(Icons.auto_awesome), findsNothing);
        expect(
          find.text('Log a few meals and we\u2019ll suggest your usual here.'),
          findsOneWidget,
        );
      },
    );
  });

  group('time-of-day picks (vertical list on the empty landing)', () {
    FoodLogEntry pick(
      String name, {
      double calories = 204,
      double protein = 33,
      double fat = 7,
      double carbs = 0,
      double grams = 166,
      String? portionLabel,
    }) => FoodLogEntry(
      id: 'pick-$name',
      date: DateTime(2026, 1, 23),
      loggedAt: DateTime(2026, 1, 23, 8),
      servingGrams: grams,
      calories: calories,
      proteinGrams: protein,
      carbsGrams: carbs,
      fatGrams: fat,
      foodName: name,
      portionLabel: portionLabel,
      source: 'self',
    );

    FoodLogEntry recent(String name) => FoodLogEntry(
      id: 'recent-$name',
      date: DateTime(2026, 1, 23),
      loggedAt: DateTime(2026, 1, 23, 8),
      servingGrams: 100,
      calories: 97,
      proteinGrams: 1,
      carbsGrams: 23,
      fatGrams: 0,
      foodName: name,
      source: 'self',
    );

    Future<void> pump(
      WidgetTester tester, {
      required String query,
      List<FoodLogEntry> suggested = const [],
      List<FoodLogEntry> latest = const [],
      List<Food> favorites = const [],
      List<Food> results = const [],
      void Function(FoodLogEntry)? onAddLatest,
    }) async {
      final bloc = _MockFoodSearchBloc();
      final state = FoodSearchState(query: query, results: results);
      when(() => bloc.state).thenReturn(state);
      when(() => bloc.stream).thenAnswer((_) => Stream.value(state));
      final controller = TextEditingController(text: query);
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: BlocProvider<FoodSearchBloc>.value(
              value: bloc,
              child: AddFoodSearchView(
                controller: controller,
                focusNode: focusNode,
                suggested: suggested,
                latest: latest,
                favorites: favorites,
                isFavorite: (_) => false,
                onAddFood: (_, __) {},
                onAddLatest: onAddLatest ?? (_) {},
                onToggleFavorite: (_) {},
                onAddDefault: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('renders a meal/time-aware picks header from the current hour', (
      tester,
    ) async {
      await pump(tester, query: '', suggested: [pick('Grilled chicken')]);
      // The header word matches timeOfDayPicksHeader(now) — assert the helper
      // itself so the test is wall-clock independent, then assert it renders.
      final expectedHeader = timeOfDayPicksHeader(DateTime.now());
      expect(
        expectedHeader,
        anyOf(
          'Morning picks',
          'Afternoon picks',
          'Evening picks',
          'Late-night picks',
        ),
      );
      expect(find.text(expectedHeader), findsOneWidget);
    });

    testWidgets('a pick row shows the name, the serving, and the macro line', (
      tester,
    ) async {
      await pump(
        tester,
        query: '',
        suggested: [pick('Grilled chicken', portionLabel: '1 breast (166 g)')],
      );
      expect(find.text('Grilled chicken'), findsOneWidget);
      // Serving leads, then the "N Cal · P · F · C" breakdown.
      expect(
        find.text('1 breast (166 g) · 204 Cal · 33P · 7F · 0C'),
        findsOneWidget,
      );
    });

    testWidgets('falls back to a gram serving when there is no portion label', (
      tester,
    ) async {
      await pump(tester, query: '', suggested: [pick('Grilled chicken')]);
      expect(
        find.text('166 g · 204 Cal · 33P · 7F · 0C'),
        findsOneWidget,
      );
    });

    testWidgets('the + add button re-logs that pick', (tester) async {
      FoodLogEntry? added;
      await pump(
        tester,
        query: '',
        suggested: [pick('Grilled chicken')],
        onAddLatest: (e) => added = e,
      );
      // The pick row carries a one-tap "Add" affordance.
      final addButtons = find.byTooltip('Add');
      expect(addButtons, findsWidgets);
      await tester.tap(addButtons.last);
      await tester.pump();
      expect(added?.foodName, 'Grilled chicken');
    });

    testWidgets('typing replaces the picks list with search results', (
      tester,
    ) async {
      // With a query, the empty-state picks must be hidden and only the live
      // results render.
      await pump(
        tester,
        query: 'protein',
        suggested: [pick('Grilled chicken')],
        results: [_food(id: 'p1', name: 'Protein bar')],
      );
      expect(find.text('Grilled chicken'), findsNothing);
      expect(find.text('Morning picks'), findsNothing);
      expect(find.text('Afternoon picks'), findsNothing);
      expect(find.text('Evening picks'), findsNothing);
      expect(find.text('Late-night picks'), findsNothing);
      expect(find.text('Results'), findsOneWidget);
      expect(find.text('Protein bar'), findsOneWidget);
    });

    testWidgets(
      'no picks but some history: a tasteful prompt fills the slot, not a gap',
      (tester) async {
        await pump(
          tester,
          query: '',
          suggested: const [],
          latest: [recent('Banana, raw')],
        );
        expect(
          find.text('Log a few meals and we’ll suggest your usual here.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a brand-new user (nothing at all) shows no picks slot', (
      tester,
    ) async {
      await pump(tester, query: '');
      // The truly-empty landing keeps the search hint and adds no picks header
      // or empty prompt.
      expect(
        find.text('Log a few meals and we’ll suggest your usual here.'),
        findsNothing,
      );
      expect(find.text('Morning picks'), findsNothing);
      expect(find.text('Afternoon picks'), findsNothing);
      expect(find.text('Evening picks'), findsNothing);
      expect(find.text('Late-night picks'), findsNothing);
    });
  });

  // Regression: this shared view is ALSO used by the recipe IngredientPickerSheet,
  // which passes latest:[] + no suggested but CAN pass favorites. The empty-state
  // picks/empty-prompt must be gated on real recents/suggestions, NOT favorites —
  // otherwise that recipe flow (which never loads meal suggestions or logs meals)
  // would wrongly show a "[time] picks" header + the "log a few meals" prompt
  // above its Favorites.
  group('picks gating on recents/suggestions, not favorites', () {
    Food favFood(String id, String name) =>
        _food(id: id, name: name, source: 'fdc');

    FoodLogEntry recent(String name) => FoodLogEntry(
      id: 'r-$name',
      date: DateTime(2026, 1, 23),
      loggedAt: DateTime(2026, 1, 23, 8),
      servingGrams: 100,
      calories: 100,
      proteinGrams: 5,
      carbsGrams: 10,
      fatGrams: 2,
      foodName: name,
      source: 'self',
    );

    Future<void> pump(
      WidgetTester tester, {
      List<FoodLogEntry> suggested = const [],
      List<FoodLogEntry> latest = const [],
      List<Food> favorites = const [],
    }) async {
      final bloc = _MockFoodSearchBloc();
      const state = FoodSearchState(query: '', results: []);
      when(() => bloc.state).thenReturn(state);
      when(() => bloc.stream).thenAnswer((_) => Stream.value(state));
      final controller = TextEditingController(); // empty query -> empty state
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: BlocProvider<FoodSearchBloc>.value(
              value: bloc,
              child: AddFoodSearchView(
                controller: controller,
                focusNode: focusNode,
                suggested: suggested,
                latest: latest,
                favorites: favorites,
                isFavorite: (_) => false,
                onAddFood: (_, __) {},
                onAddLatest: (_) {},
                onToggleFavorite: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets(
      'recipe context (latest:[] + no suggested, WITH favorites) shows '
      'Favorites but NO picks header and NO "log a few meals" prompt',
      (tester) async {
        // Mirrors how IngredientPickerSheet drives this view.
        await pump(
          tester,
          suggested: const [],
          latest: const [],
          favorites: [favFood('fav-1', 'Olive oil')],
        );

        // Favorites still render as before for that flow.
        expect(find.text('Favorites'), findsOneWidget);
        expect(find.text('Olive oil'), findsOneWidget);

        // ...but neither the meal-history picks header nor the empty prompt,
        // since favorites are NOT meal history.
        expect(
          find.text('Log a few meals and we\u2019ll suggest your usual here.'),
          findsNothing,
        );
        expect(find.text('Morning picks'), findsNothing);
        expect(find.text('Afternoon picks'), findsNothing);
        expect(find.text('Evening picks'), findsNothing);
        expect(find.text('Late-night picks'), findsNothing);
      },
    );

    testWidgets(
      'add-food thin-history (a recent, no suggestions) WITH favorites still '
      'shows the picks header + "log a few meals" prompt',
      (tester) async {
        // The add-food sheet path: real meal history (a recent) but too thin
        // for suggestions. The picks slot must still fill with the prompt.
        await pump(
          tester,
          suggested: const [],
          latest: [recent('Banana, raw')],
          favorites: [favFood('fav-1', 'Olive oil')],
        );

        expect(
          find.text('Log a few meals and we\u2019ll suggest your usual here.'),
          findsOneWidget,
        );
        expect(find.text(timeOfDayPicksHeader(DateTime.now())), findsOneWidget);
        // Favorites still render below.
        expect(find.text('Favorites'), findsOneWidget);
        expect(find.text('Olive oil'), findsOneWidget);
      },
    );
  });

  group('recent trust badge on search results', () {
    testWidgets('a recent result shows the muted "Recent" provenance hint', (
      tester,
    ) async {
      await _pumpWithResults(tester, [
        _food(
          id: 'recent:greek yogurt',
          name: 'Greek yogurt',
          source: 'self',
          trustTier: 'recent',
          loggedCount: 4,
        ),
      ]);

      // "Recent · logged 4x" — quiet provenance, not a loud pill. No Verified.
      expect(find.text('Recent · logged 4x'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);
    });

    testWidgets('a recent logged once shows a bare "Recent" (no count)', (
      tester,
    ) async {
      await _pumpWithResults(tester, [
        _food(
          id: 'recent:oats',
          name: 'Oats',
          source: 'self',
          trustTier: 'recent',
          loggedCount: 1,
        ),
      ]);

      expect(find.text('Recent'), findsOneWidget);
      expect(find.textContaining('logged'), findsNothing);
    });
  });

  group('history-first search merge', () {
    FoodLogEntry historyEntry(
      String name, {
      double servingGrams = 100,
      double calories = 100,
      double protein = 5,
      double carbs = 10,
      double fat = 2,
    }) => FoodLogEntry(
      id: 'h-$name',
      date: DateTime(2026, 1, 23),
      loggedAt: DateTime(2026, 1, 23, 8),
      servingGrams: servingGrams,
      calories: calories,
      proteinGrams: protein,
      carbsGrams: carbs,
      fatGrams: fat,
      foodName: name,
      source: 'self',
    );

    Future<void> pump(
      WidgetTester tester, {
      required String query,
      List<FoodLogEntry> suggested = const [],
      List<FoodLogEntry> latest = const [],
      List<Food> results = const [],
      void Function(Food)? onAddDefault,
    }) async {
      final bloc = _MockFoodSearchBloc();
      final state = FoodSearchState(query: query, results: results);
      when(() => bloc.state).thenReturn(state);
      when(() => bloc.stream).thenAnswer((_) => Stream.value(state));
      final controller = TextEditingController(text: query);
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: BlocProvider<FoodSearchBloc>.value(
              value: bloc,
              child: AddFoodSearchView(
                controller: controller,
                focusNode: focusNode,
                suggested: suggested,
                latest: latest,
                favorites: const [],
                isFavorite: (_) => false,
                onAddFood: (_, __) {},
                onAddLatest: (_) {},
                onToggleFavorite: (_) {},
                onAddDefault: onAddDefault,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets(
      'a query matching a user-history food ranks it ABOVE a catalog-only match',
      (tester) async {
        await pump(
          tester,
          query: 'chick',
          latest: [historyEntry('Grilled chicken')],
          results: [_food(id: 'cat-1', name: 'Chicken nuggets', source: 'off')],
        );

        expect(find.text('Grilled chicken'), findsOneWidget);
        expect(find.text('Chicken nuggets'), findsOneWidget);
        // History food first, catalog-only match after it.
        expect(
          tester.getTopLeft(find.text('Grilled chicken')).dy,
          lessThan(tester.getTopLeft(find.text('Chicken nuggets')).dy),
        );
        // The history row carries the "Recent" provenance hint.
        expect(find.text('Recent'), findsOneWidget);
      },
    );

    testWidgets(
      'a food in BOTH history and catalog appears once with the user serving',
      (tester) async {
        final captured = <Food>[];
        await pump(
          tester,
          query: 'yogurt',
          latest: [historyEntry('Greek yogurt', servingGrams: 170)],
          results: [
            // A catalog dup of the same food at the 100g default.
            const Food(
              id: 'cat-dup',
              name: 'Greek yogurt',
              source: 'off',
              servingSizeGrams: 100,
              caloriesPer100g: 60,
              proteinPer100g: 10,
              carbsPer100g: 4,
              fatPer100g: 0,
            ),
            _food(id: 'cat-2', name: 'Yogurt drink', source: 'off'),
          ],
          onAddDefault: captured.add,
        );

        // Deduped: exactly one Greek yogurt row, plus the catalog-only one.
        expect(find.text('Greek yogurt'), findsOneWidget);
        expect(find.text('Yogurt drink'), findsOneWidget);

        // The surviving row is the HISTORY one: quick-adding it logs the user's
        // last-used serving (170 g), not the catalog 100g default.
        await tester.tap(find.byTooltip('Add').first);
        await tester.pump();
        expect(captured.single.servingSizeGrams, 170);
      },
    );

    testWidgets('a query with no history match still returns catalog results', (
      tester,
    ) async {
      await pump(
        tester,
        query: 'protein',
        latest: [historyEntry('Banana')], // no match for "protein"
        results: [_food(id: 'cat-1', name: 'Protein bar', source: 'off')],
      );

      // The catalog result is unaffected by the (non-matching) history.
      expect(find.text('Protein bar'), findsOneWidget);
      expect(find.text('Banana'), findsNothing);
      // No history row, so no "Recent" provenance hint.
      expect(find.text('Recent'), findsNothing);
    });
  });
}
