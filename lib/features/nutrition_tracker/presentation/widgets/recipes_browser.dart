import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';

import '../../domain/models/food_log_entry.dart';
import '../../domain/models/recipe.dart';
import '../../domain/repositories/recipes_repository.dart';
import '../utils/macro_format.dart';
import 'edit_recipe_sheet.dart';

/// The reusable recipe list: load, browse, edit, delete, and pick a recipe.
///
/// Tapping a recipe calls [onPick] with the exploded [FoodLogEntry]s for the
/// given [date] (no modal) — the host decides what to do (add to the plate, or
/// pop a dialog). Used inline as the add-food sheet's Recipes mode and wrapped
/// by [RecipesDialog] for standalone use.
class RecipesBrowser extends StatefulWidget {
  const RecipesBrowser({
    super.key,
    required this.date,
    required this.onPick,
    this.defaultLoggedAt,
  });

  final DateTime date;
  final DateTime? defaultLoggedAt;
  final ValueChanged<List<FoodLogEntry>> onPick;

  @override
  State<RecipesBrowser> createState() => _RecipesBrowserState();
}

class _RecipesBrowserState extends State<RecipesBrowser> {
  bool _isLoading = true;
  String? _error;
  List<Recipe> _recipes = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final repo = GetIt.instance<RecipesRepository>();
      final items = await repo.listRecipes();
      if (!mounted) return;
      setState(() {
        _recipes = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _totalsLabel(Recipe recipe) {
    double calories = 0;
    double protein = 0;
    double carbs = 0;
    double fat = 0;
    for (final item in recipe.items) {
      calories += item.calories;
      protein += item.proteinGrams;
      carbs += item.carbsGrams;
      fat += item.fatGrams;
    }
    return formatMacros(
      protein: protein,
      fat: fat,
      carbs: carbs,
      calories: calories,
    );
  }

  List<FoodLogEntry> _entriesForRecipe(Recipe recipe) {
    final seed = widget.defaultLoggedAt?.toLocal();
    final now = seed ?? DateTime.now();
    final base = DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
      now.hour,
      now.minute,
      now.second,
    );
    return recipe.items
        .asMap()
        .entries
        .map((pair) {
          final index = pair.key;
          final item = pair.value;
          return FoodLogEntry(
            id: 'temp-${DateTime.now().microsecondsSinceEpoch}-$index',
            date: widget.date,
            loggedAt: base.add(Duration(seconds: index)),
            servingGrams: item.servingGrams,
            calories: item.calories,
            proteinGrams: item.proteinGrams,
            carbsGrams: item.carbsGrams,
            fatGrams: item.fatGrams,
            fiberGrams: item.fiberGrams,
            sugarGrams: item.sugarGrams,
            sodiumMg: item.sodiumMg,
            foodName: item.foodName,
            source: 'recipe',
          );
        })
        .toList(growable: false);
  }

  Future<void> _confirmDelete(Recipe recipe) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete recipe?'),
        content: Text('Delete “${recipe.name}”?'),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;

    try {
      await GetIt.instance<RecipesRepository>().deleteRecipe(recipe.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      HustlSnack.show(
        context,
        message.trim().isEmpty
            ? 'Couldn’t delete that recipe. Please try again.'
            : message,
        variant: HustlSnackVariant.error,
      );
    }
  }

  /// Opens the full recipe editor (name, servings, ingredient amounts) and
  /// reloads the list on save.
  Future<void> _openEditor(Recipe recipe) async {
    final saved = await EditRecipeSheet.show(context, recipe: recipe);
    if (!mounted || saved != true) return;
    await _load();
    if (!mounted) return;
    HustlSnack.show(
      context,
      'Recipe updated.',
      variant: HustlSnackVariant.success,
    );
  }

  /// Opens the editor on a blank recipe and reloads the list once created.
  Future<void> _createRecipe() async {
    final created = await EditRecipeSheet.showNew(context);
    if (!mounted || created != true) return;
    await _load();
    if (!mounted) return;
    HustlSnack.show(
      context,
      'Recipe created.',
      variant: HustlSnackVariant.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const _RecipesLoadingSkeleton();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x2,
            AppSpacing.x2,
            AppSpacing.x2,
            AppSpacing.x1,
          ),
          child: FilledButton.tonalIcon(
            onPressed: _createRecipe,
            icon: const Icon(Icons.add),
            label: const Text('New recipe'),
          ),
        ),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildContent() {
    final theme = Theme.of(context);
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Could not load recipes.',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.x2),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_recipes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x3),
          child: Text(
            'No recipes yet — tap New recipe to build a meal you can log in a '
            'single tap.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemBuilder: (context, index) {
        final recipe = _recipes[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(recipe.name),
          subtitle: Text(_totalsLabel(recipe)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => _openEditor(recipe),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit recipe',
              ),
              IconButton(
                onPressed: () => _confirmDelete(recipe),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete recipe',
              ),
            ],
          ),
          onTap: () => widget.onPick(_entriesForRecipe(recipe)),
        );
      },
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemCount: _recipes.length,
    );
  }
}

/// Skeleton shaped like the recipe list (a title + subtitle per row) so loading
/// reads as the list filling in rather than a lone spinner.
class _RecipesLoadingSkeleton extends StatelessWidget {
  const _RecipesLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.x2),
      itemBuilder: (context, _) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSkeleton(width: 180, height: 16),
          SizedBox(height: AppSpacing.x1),
          AppSkeleton(width: 120, height: 12),
        ],
      ),
    );
  }
}
