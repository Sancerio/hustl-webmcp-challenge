import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';

import '../../domain/models/food.dart';
import '../../domain/models/food_log_entry.dart';
import '../../domain/models/recipe.dart';
import '../../domain/repositories/food_repository.dart';
import '../bloc/food_search_bloc.dart';
import 'add_food_scan_menu.dart';
import 'add_food_search_view.dart';
import 'barcode_scan_dialog.dart';
import 'nutrition_label_scan_dialog.dart';

/// Modal food-search picker used when building a recipe. Unlike the diary
/// add-food flow it never logs anything — it RETURNS a single [RecipeItem]
/// (a food resolved to absolute macros at the chosen grams) so the recipe
/// editor can append it. Reuses [AddFoodSearchView] verbatim; favorites are
/// wired to [FoodRepository] so the star toggle behaves like the main flow.
class IngredientPickerSheet extends StatefulWidget {
  const IngredientPickerSheet({super.key});

  /// Opens the picker and resolves to the chosen ingredient, or null if the
  /// user dismissed it without picking.
  static Future<RecipeItem?> show(BuildContext context) {
    return showModalBottomSheet<RecipeItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (_) => const IngredientPickerSheet(),
    );
  }

  @override
  State<IngredientPickerSheet> createState() => _IngredientPickerSheetState();
}

class _IngredientPickerSheetState extends State<IngredientPickerSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final Set<String> _favoriteIds = {};
  List<Food> _favoriteFoods = [];

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final repo = GetIt.instance<FoodRepository>();
    try {
      final results = await Future.wait<Object>([
        repo.listFavoriteIds(limit: 500).catchError((_) => <String>{}),
        repo.listFavorites(limit: 10).catchError((_) => <Food>[]),
      ]);
      final ids = results[0] as Set<String>;
      final foods = results[1] as List<Food>;
      if (!mounted) return;
      setState(() {
        _favoriteFoods = foods;
        _favoriteIds
          ..clear()
          ..addAll(ids.isNotEmpty ? ids : foods.map((f) => f.id));
      });
    } catch (_) {
      // Favorites are best-effort; an empty list just hides the section.
    }
  }

  Future<void> _toggleFavorite(Food food) async {
    final repo = GetIt.instance<FoodRepository>();
    final wasFavorite = _favoriteIds.contains(food.id);
    setState(() {
      if (wasFavorite) {
        _favoriteIds.remove(food.id);
        _favoriteFoods.removeWhere((f) => f.id == food.id);
      } else {
        _favoriteIds.add(food.id);
        _favoriteFoods = [food, ..._favoriteFoods].take(10).toList();
      }
    });
    try {
      wasFavorite
          ? await repo.removeFavorite(food.id)
          : await repo.addFavorite(food.id);
    } catch (_) {
      if (!mounted) return;
      // Roll back on failure so the star reflects the persisted state.
      setState(() {
        if (wasFavorite) {
          _favoriteIds.add(food.id);
          _favoriteFoods = [food, ..._favoriteFoods].take(10).toList();
        } else {
          _favoriteIds.remove(food.id);
          _favoriteFoods.removeWhere((f) => f.id == food.id);
        }
      });
    }
  }

  void _returnFood(Food food, double grams) {
    if (grams <= 0) return;
    context.pop(recipeItemFromFood(food, grams));
  }

  // --- scan capture (returns the chosen ingredient, never logs) ---

  /// Capture an ingredient by scanning a packaged product. The AI "scan a meal"
  /// option is hidden (`includeMeal: false`): a recipe ingredient is ONE
  /// product, so only barcode + nutrition-label capture make sense here.
  Future<void> _openScanMenu(BuildContext context) async {
    final choice = await showAddFoodScanMenu(context, includeMeal: false);
    if (!context.mounted || choice == null) return;
    switch (choice) {
      case AddFoodScanChoice.barcode:
        await _onBarcode(context);
      case AddFoodScanChoice.label:
        await _onLabel(context);
      case AddFoodScanChoice.meal:
        break; // not offered in the recipe context
    }
  }

  Future<void> _onBarcode(BuildContext context) async {
    final repo = GetIt.instance<FoodRepository>();
    String? code;
    if (kIsWeb) {
      code = await _promptBarcodeInput(context);
    } else {
      final result = await showDialog<BarcodeScanResult>(
        context: context,
        builder: (_) => const BarcodeScanDialog(),
      );
      if (!context.mounted) return;
      switch (result) {
        case BarcodeScanCode(code: final scanned):
          code = scanned;
        case BarcodeScanManualEntry():
          code = await _promptBarcodeInput(context);
        case null:
          return;
      }
    }
    if (!context.mounted || code == null || code.isEmpty) return;
    try {
      final food = await repo.lookupBarcode(code);
      if (!context.mounted) return;
      if (food == null) {
        await _onBarcodeMiss(context);
        return;
      }
      // Default serving (or 100g) — same portion pattern as the search '+';
      // the grams are editable on the ingredient row afterwards.
      context.pop(recipeItemFromFood(food, food.servingSizeGrams ?? 100));
    } catch (e) {
      if (!context.mounted) return;
      final message = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      HustlSnack.show(
        context,
        message.trim().isEmpty
            ? 'Couldn’t look up that barcode. Please try again.'
            : message,
        variant: HustlSnackVariant.error,
      );
    }
  }

  /// A barcode with no database match falls through to the label scan, so the
  /// user can still capture the product from its nutrition panel.
  Future<void> _onBarcodeMiss(BuildContext context) async {
    if (kIsWeb) {
      HustlSnack.show(
        context,
        'No food found for that barcode. Try searching or add it manually.',
        variant: HustlSnackVariant.warning,
      );
      return;
    }
    HustlSnack.show(
      context,
      'No match for that barcode. Snap the nutrition label to add it.',
      variant: HustlSnackVariant.info,
    );
    await _onLabel(context);
  }

  Future<void> _onLabel(BuildContext context) async {
    if (kIsWeb) {
      HustlSnack.show(
        context,
        'Label scan isn\'t available on web yet.',
        variant: HustlSnackVariant.warning,
      );
      return;
    }
    // The recipe has no date; the label dialog only uses it to stamp the entry
    // it returns, and we read just the macros/grams back out as a RecipeItem.
    final entry = await showDialog<FoodLogEntry>(
      context: context,
      builder: (context) => NutritionLabelScanDialog(date: DateTime.now()),
    );
    if (!context.mounted || entry == null) return;
    context.pop(_recipeItemFromEntry(entry));
  }

  Future<String?> _promptBarcodeInput(BuildContext context) async {
    final textController = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter barcode'),
        content: TextField(
          controller: textController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Barcode'),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => context.pop(textController.text.trim()),
            child: const Text('Lookup'),
          ),
        ],
      ),
    );
    textController.dispose();
    return code?.trim().isEmpty == true ? null : code;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocProvider(
      create: (_) => FoodSearchBloc(GetIt.instance<FoodRepository>()),
      child: Builder(
        builder: (innerContext) => LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: constraints.maxHeight,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                left: AppSpacing.x2,
                right: AppSpacing.x2,
                top: AppSpacing.x1 + 4,
                bottom:
                    MediaQuery.of(innerContext).viewInsets.bottom +
                    AppSpacing.x2,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                      ),
                      const SizedBox(width: 6),
                      Text('Add ingredient', style: theme.textTheme.titleLarge),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x1 + 4),
                  Expanded(
                    child: AddFoodSearchView(
                      controller: _controller,
                      focusNode: _focusNode,
                      latest: const [],
                      favorites: _favoriteFoods,
                      isFavorite: (food) => _favoriteIds.contains(food.id),
                      onScan: () => _openScanMenu(innerContext),
                      onAddFood: _returnFood,
                      // Quick path: '+' adds the food at its default serving.
                      onAddDefault: (food) =>
                          _returnFood(food, food.servingSizeGrams ?? 100),
                      onAddLatest: (entry) =>
                          context.pop(_recipeItemFromEntry(entry)),
                      onToggleFavorite: _toggleFavorite,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Resolves a [Food] at [grams] to absolute macros (per-100g × grams/100).
RecipeItem recipeItemFromFood(Food food, double grams) {
  final factor = grams / 100;
  return RecipeItem(
    id: 'temp-${DateTime.now().microsecondsSinceEpoch}',
    foodId: food.id,
    foodName: food.name,
    servingGrams: grams,
    calories: (food.caloriesPer100g ?? 0) * factor,
    proteinGrams: (food.proteinPer100g ?? 0) * factor,
    carbsGrams: (food.carbsPer100g ?? 0) * factor,
    fatGrams: (food.fatPer100g ?? 0) * factor,
    fiberGrams: food.fiberPer100g == null ? null : food.fiberPer100g! * factor,
    sugarGrams: food.sugarPer100g == null ? null : food.sugarPer100g! * factor,
    sodiumMg: food.sodiumMgPer100g == null
        ? null
        : food.sodiumMgPer100g! * factor,
  );
}

/// A recently-logged entry already carries absolute macros at its grams, so it
/// maps straight across (used only if the picker ever surfaces a Recent row).
RecipeItem _recipeItemFromEntry(FoodLogEntry e) => RecipeItem(
  id: 'temp-${DateTime.now().microsecondsSinceEpoch}',
  foodId: e.food?.id,
  foodName: e.foodName ?? e.food?.name ?? 'Food',
  servingGrams: e.servingGrams,
  calories: e.calories,
  proteinGrams: e.proteinGrams,
  carbsGrams: e.carbsGrams,
  fatGrams: e.fatGrams,
  fiberGrams: e.fiberGrams,
  sugarGrams: e.sugarGrams,
  sodiumMg: e.sodiumMg,
);
