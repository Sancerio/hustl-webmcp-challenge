import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/recipe.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/recipes_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/plate_review_sheet.dart';

class _RecordingRecipesRepository implements RecipesRepository {
  Recipe? created;
  bool throwOnCreate = false;

  @override
  Future<Recipe> createRecipe(Recipe recipe) async {
    if (throwOnCreate) throw Exception('boom');
    created = recipe;
    return recipe.copyWith(id: 'saved-1');
  }

  @override
  Future<List<Recipe>> listRecipes() async => [];

  @override
  Future<Recipe> updateRecipe(Recipe recipe) async => recipe;

  @override
  Future<void> deleteRecipe(String id) async {}
}

FoodLogEntry _entry({required String id, required String name}) {
  final at = DateTime(2026, 6, 16, 8);
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

/// Mounts the sheet inside a router so [context.pop] resolves and a
/// [ScaffoldMessenger] exists for [HustlSnack]. Returns a getter for the most
/// recent [onChanged] emission so tests can assert the rescaled entry.
Future<List<FoodLogEntry>? Function()> _pumpSheet(
  WidgetTester tester,
  List<FoodLogEntry> entries, {
  String? highlightEntryId,
  String? bannerMessage,
}) async {
  List<FoodLogEntry>? lastChanged;
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => NoTransitionPage(
          child: Scaffold(
            body: PlateReviewSheet(
              entries: entries,
              onChanged: (updated) => lastChanged = updated,
              onCommit: () {},
              highlightEntryId: highlightEntryId,
              bannerMessage: bannerMessage,
            ),
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return () => lastChanged;
}

void main() {
  final getIt = GetIt.instance;
  late _RecordingRecipesRepository recipesRepo;

  setUp(() {
    recipesRepo = _RecordingRecipesRepository();
    getIt.registerSingleton<RecipesRepository>(recipesRepo);
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('save as recipe is hidden when the plate is empty', (
    tester,
  ) async {
    await _pumpSheet(tester, const []);
    expect(find.text('Save as recipe'), findsNothing);
  });

  testWidgets('save as recipe prompts for a name and saves the mapped items', (
    tester,
  ) async {
    await _pumpSheet(tester, [
      _entry(id: 'a', name: 'Oats'),
      _entry(id: 'b', name: 'Eggs'),
    ]);

    expect(find.text('Save as recipe'), findsOneWidget);

    await tester.tap(find.text('Save as recipe'));
    await tester.pumpAndSettle();

    // The single-field name dialog appears with the "Meal" default; accept it.
    expect(find.text('Name this recipe'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    // The repo received both entries as an unsaved recipe, snapshots intact.
    expect(recipesRepo.created, isNotNull);
    final recipe = recipesRepo.created!;
    expect(recipe.name, 'Meal');
    expect(recipe.id, '');
    expect(recipe.servings, 1);
    expect(recipe.items, hasLength(2));
    expect(recipe.items.map((i) => i.foodName), ['Oats', 'Eggs']);
    final first = recipe.items.first;
    expect(first.servingGrams, 150);
    expect(first.calories, 250);
    expect(first.proteinGrams, 30);
    expect(first.carbsGrams, 12);
    expect(first.fatGrams, 8);
    expect(first.fiberGrams, 3);

    // Saving is independent of logging — the sheet stays open.
    expect(find.text('Recipe saved.'), findsOneWidget);
    expect(find.text('Log foods (2)'), findsOneWidget);
  });

  testWidgets('cancelling the name dialog does not save', (tester) async {
    await _pumpSheet(tester, [_entry(id: 'a', name: 'Oats')]);

    await tester.tap(find.text('Save as recipe'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(recipesRepo.created, isNull);
  });

  testWidgets('a failed save surfaces an error snack', (tester) async {
    recipesRepo.throwOnCreate = true;
    await _pumpSheet(tester, [_entry(id: 'a', name: 'Oats')]);

    await tester.tap(find.text('Save as recipe'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(
      find.text('Couldn’t save that recipe. Please try again.'),
      findsOneWidget,
    );
    expect(recipesRepo.created, isNull);
  });

  testWidgets('pencil expands the inline stepper and +/- rescale the row', (
    tester,
  ) async {
    final changed = await _pumpSheet(tester, [_entry(id: 'a', name: 'Oats')]);

    // The macro line starts at the seed portion (150 g, 250 Cal).
    expect(find.text('250 Cal · 30P · 8F · 12C · 150 g'), findsOneWidget);
    // The stepper is hidden until the pencil is tapped.
    expect(find.byKey(const Key('plateRowGrams')), findsNothing);

    await tester.tap(find.byTooltip('Edit portion'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plateRowGrams')), findsOneWidget);
    expect(find.text('150 g'), findsOneWidget);

    // + nudges by the 5 g step → 155 g, macros rescale proportionally.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('155 g'), findsOneWidget);
    expect(changed()!.single.servingGrams, 155);

    // - nudges back to 150 g.
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    expect(find.text('150 g'), findsOneWidget);
    expect(changed()!.single.servingGrams, 150);
  });

  testWidgets('quick chips rescale grams and macros, and emit the entry', (
    tester,
  ) async {
    final changed = await _pumpSheet(tester, [_entry(id: 'a', name: 'Oats')]);
    await tester.tap(find.byTooltip('Edit portion'));
    await tester.pumpAndSettle();

    // 2x doubles 150 g -> 300 g, so calories double 250 -> 500.
    await tester.tap(find.text('2×'));
    await tester.pumpAndSettle();
    expect(find.text('300 g'), findsOneWidget);
    expect(find.text('500 Cal · 60P · 16F · 24C · 300 g'), findsOneWidget);
    expect(changed()!.single.servingGrams, 300);
    expect(changed()!.single.calories, closeTo(500, 0.001));

    // 1/2x halves 300 g -> 150 g, back to the seed macros.
    await tester.tap(find.text('½×'));
    await tester.pumpAndSettle();
    expect(find.text('150 g'), findsOneWidget);
    expect(changed()!.single.servingGrams, 150);

    // +25 g chip -> 175 g.
    await tester.tap(find.text('+25 g'));
    await tester.pumpAndSettle();
    expect(find.text('175 g'), findsOneWidget);
    expect(changed()!.single.servingGrams, 175);

    // -25 g chip -> 150 g.
    await tester.tap(find.text('−25 g'));
    await tester.pumpAndSettle();
    expect(find.text('150 g'), findsOneWidget);
    expect(changed()!.single.servingGrams, 150);
  });

  testWidgets(
    'highlightEntryId highlights + auto-expands the row and shows the banner',
    (tester) async {
      await _pumpSheet(
        tester,
        [_entry(id: 'a', name: 'Oats'), _entry(id: 'b', name: 'Eggs')],
        highlightEntryId: 'b',
        bannerMessage: 'Scanned — review the portion before logging.',
      );

      // The banner is shown.
      expect(
        find.text('Scanned — review the portion before logging.'),
        findsOneWidget,
      );

      // The matching row (b) auto-expands its inline stepper.
      expect(find.byKey(const Key('plateRowGrams')), findsOneWidget);

      // The highlighted row paints a tint (an AnimatedContainer with a
      // non-transparent decoration colour).
      final highlighted = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .where((c) {
            final d = c.decoration;
            return d is BoxDecoration &&
                d.color != null &&
                d.color != Colors.transparent;
          });
      expect(highlighted, isNotEmpty);
    },
  );

  testWidgets(
    'auto-scrolls a long plate so the highlighted scanned row is in view',
    (tester) async {
      // A long plate with the scanned row appended at the bottom (off-screen).
      final entries = [
        for (var i = 0; i < 16; i++) _entry(id: 'e$i', name: 'Food $i'),
      ];
      await _pumpSheet(
        tester,
        entries,
        highlightEntryId: 'e15',
        bannerMessage: 'Scanned — review the portion before logging.',
      );

      // The appended highlighted row's auto-expanded stepper is on-screen: the
      // sheet scrolled it into the viewport (without the auto-scroll it would
      // sit below the fold).
      final grams = find.byKey(const Key('plateRowGrams'));
      expect(grams, findsOneWidget);
      final viewport = tester.getRect(find.byType(Scrollable));
      expect(viewport.overlaps(tester.getRect(grams)), isTrue);
    },
  );

  testWidgets(
    'undo of an earlier-row removal keeps the editor on the same food',
    (tester) async {
      final changed = await _pumpSheet(tester, [
        _entry(id: 'a', name: 'Oats'),
        _entry(id: 'b', name: 'Eggs'),
      ]);

      // Open the editor on the SECOND row (Eggs).
      await tester.tap(find.byTooltip('Edit portion').last);
      await tester.pumpAndSettle();
      // Remove the FIRST row (Oats); _editingIndex shifts 1 -> 0.
      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();
      // Undo reinserts Oats; the editor must shift back to Eggs (index 1).
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      // Nudging +5 g now affects Eggs, not Oats.
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      final items = changed()!;
      expect(items.firstWhere((e) => e.id == 'b').servingGrams, 155);
      expect(items.firstWhere((e) => e.id == 'a').servingGrams, 150);
    },
  );
}
