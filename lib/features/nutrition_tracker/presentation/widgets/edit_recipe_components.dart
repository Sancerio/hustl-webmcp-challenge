import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';

import '../../domain/models/recipe.dart';
import '../utils/macro_format.dart';
import 'food_entry_avatar.dart';

String _n(double v) => v.toStringAsFixed(0);

/// Section header for the ingredients list: the title plus a trailing "Add"
/// button that opens the food-search ingredient picker.
class RecipeIngredientsHeader extends StatelessWidget {
  const RecipeIngredientsHeader({super.key, required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 20),
          label: const Text('Add'),
        ),
      ],
    );
  }
}

/// Live-recomputed macro summary for the recipe being edited: the per-serving
/// figure is the hero (total ÷ servings) with the whole-recipe total beneath.
class RecipeTotalsHeader extends StatelessWidget {
  const RecipeTotalsHeader({
    super.key,
    required this.items,
    required this.servings,
  });

  final List<RecipeItem> items;
  final double servings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    var calories = 0.0;
    var protein = 0.0;
    var carbs = 0.0;
    var fat = 0.0;
    for (final item in items) {
      calories += item.calories;
      protein += item.proteinGrams;
      carbs += item.carbsGrams;
      fat += item.fatGrams;
    }
    final per = servings < 0.01 ? 0.01 : servings;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.x2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.x2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Per serving',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(
            '${_n(calories / per)} Cal',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formatMacros(
              protein: protein / per,
              fat: fat / per,
              carbs: carbs / per,
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(
            'Recipe total '
            '${formatMacros(protein: protein, fat: fat, carbs: carbs, calories: calories)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One editable ingredient, styled to match the diary's [DiaryEntryTile]: a
/// leading food glyph, the name + macros line, and a subtle grams pill. Tap the
/// row to rescale the amount; swipe left to remove (with an Undo snack from the
/// editor). Mirroring the diary row is what keeps the recipe editor consistent
/// with the rest of the app.
class RecipeItemRow extends StatelessWidget {
  const RecipeItemRow({
    super.key,
    required this.item,
    required this.onEditGrams,
    required this.onRemove,
  });

  final RecipeItem item;
  final VoidCallback onEditGrams;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Dismissible(
      key: ValueKey('ingredient-${item.id}'),
      direction: DismissDirection.endToStart,
      movementDuration: const Duration(milliseconds: 120),
      confirmDismiss: (dir) async => dir == DismissDirection.endToStart,
      onDismissed: (_) {
        Haptics.confirm();
        onRemove();
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.x2),
        color: colors.error.withValues(alpha: 0.15),
        child: Icon(Icons.delete_outline, color: colors.error),
      ),
      child: InkWell(
        onTap: onEditGrams,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              FoodEntryAvatar(name: item.foodName),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.foodName,
                      style: theme.textTheme.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatMacros(
                        protein: item.proteinGrams,
                        fat: item.fatGrams,
                        carbs: item.carbsGrams,
                        calories: item.calories,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.x1),
              _GramsPill(grams: item.servingGrams),
            ],
          ),
        ),
      ),
    );
  }
}

/// The editable amount, shown as a quiet tonal pill (the whole row is tappable
/// to change it) rather than a heavy outlined button.
class _GramsPill extends StatelessWidget {
  const _GramsPill({required this.grams});

  final double grams;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x1 + 2,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.x1),
      ),
      child: Text('${_n(grams)} g', style: theme.textTheme.labelLarge),
    );
  }
}
