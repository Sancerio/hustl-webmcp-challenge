import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';

import '../../domain/models/recipe.dart';
import '../../domain/repositories/recipes_repository.dart';
import 'edit_recipe_components.dart';
import 'ingredient_picker_sheet.dart';

/// Full-screen editor for a recipe — create one from scratch or edit an
/// existing one: rename, change the serving count, add ingredients via the
/// food-search picker, rescale or remove them, and save. Editing only affects
/// FUTURE logging — already-logged entries are independent snapshots, so there
/// is no "update past entries?" prompt.
class EditRecipeSheet extends StatefulWidget {
  const EditRecipeSheet({super.key, required this.recipe});

  final Recipe recipe;

  /// Opens the editor and resolves to `true` once the recipe is saved.
  static Future<bool?> show(BuildContext context, {required Recipe recipe}) {
    return showDialog<bool>(
      context: context,
      useSafeArea: false,
      builder: (_) => Dialog.fullscreen(child: EditRecipeSheet(recipe: recipe)),
    );
  }

  /// Opens the editor on a blank recipe and resolves to `true` once it is
  /// created.
  static Future<bool?> showNew(BuildContext context) {
    return show(
      context,
      recipe: const Recipe(id: '', name: '', servings: 1, items: []),
    );
  }

  @override
  State<EditRecipeSheet> createState() => _EditRecipeSheetState();
}

class _EditRecipeSheetState extends State<EditRecipeSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _servingsController;
  late List<RecipeItem> _items;
  bool _saving = false;

  /// A blank id means we are building a brand-new recipe rather than editing
  /// one already persisted on the backend.
  bool get _isNew => widget.recipe.id.isEmpty;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.recipe.name);
    _servingsController = TextEditingController(
      text: _formatServings(widget.recipe.servings),
    );
    _items = List<RecipeItem>.from(widget.recipe.items);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _servingsController.dispose();
    super.dispose();
  }

  String _formatServings(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  // Clamp so the per-serving math in the header never divides by zero.
  double get _servings {
    final parsed = double.tryParse(_servingsController.text.trim()) ?? 1;
    return parsed < 0.01 ? 0.01 : parsed;
  }

  Future<void> _editGrams(int index) async {
    final item = _items[index];
    // TextFormField owns + disposes its controller internally, so the dialog's
    // dismiss animation never touches a controller we already disposed.
    var draft = item.servingGrams.toStringAsFixed(0);
    final grams = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item.foodName),
        content: TextFormField(
          initialValue: draft,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount (g)'),
          onChanged: (value) => draft = value,
        ),
        actions: [
          TextButton(
            onPressed: () => dialogContext.pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => dialogContext.pop(double.tryParse(draft.trim())),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    if (!mounted || grams == null || grams <= 0) return;

    final old = item.servingGrams;
    final factor = old <= 0 ? 1.0 : grams / old;
    setState(() {
      _items[index] = item.copyWith(
        servingGrams: grams,
        calories: item.calories * factor,
        proteinGrams: item.proteinGrams * factor,
        carbsGrams: item.carbsGrams * factor,
        fatGrams: item.fatGrams * factor,
        fiberGrams: item.fiberGrams == null ? null : item.fiberGrams! * factor,
        sugarGrams: item.sugarGrams == null ? null : item.sugarGrams! * factor,
        sodiumMg: item.sodiumMg == null ? null : item.sodiumMg! * factor,
      );
    });
  }

  Future<void> _addIngredient() async {
    final item = await IngredientPickerSheet.show(context);
    if (!mounted || item == null) return;
    setState(() => _items.add(item));
  }

  void _removeItem(int index) {
    final removed = _items[index];
    setState(() => _items.removeAt(index));
    HustlSnack.show(
      context,
      'Removed ${removed.foodName}.',
      actionLabel: 'Undo',
      onAction: () {
        if (!mounted) return;
        setState(() {
          final at = index <= _items.length ? index : _items.length;
          _items.insert(at, removed);
        });
      },
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      HustlSnack.show(
        context,
        'Give the recipe a name.',
        variant: HustlSnackVariant.warning,
      );
      return;
    }
    if (_items.isEmpty) {
      HustlSnack.show(
        context,
        'Add at least one ingredient.',
        variant: HustlSnackVariant.warning,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = GetIt.instance<RecipesRepository>();
      final draft = widget.recipe.copyWith(
        name: name,
        servings: _servings,
        items: _items,
      );
      if (_isNew) {
        await repo.createRecipe(draft);
      } else {
        await repo.updateRecipe(draft);
      }
      if (!mounted) return;
      // Pop with success; the recipes list shows the confirmation toast on its
      // own (still-mounted) surface after reloading.
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final message = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      HustlSnack.show(
        context,
        message.trim().isEmpty
            ? 'Couldn’t save that recipe. Please try again.'
            : message,
        variant: HustlSnackVariant.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New recipe' : 'Edit recipe'),
        centerTitle: true,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.close),
          tooltip: 'Close',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x2,
            AppSpacing.x2,
            AppSpacing.x2,
            AppSpacing.x3,
          ),
          children: [
            RecipeTotalsHeader(items: _items, servings: _servings),
            const SizedBox(height: AppSpacing.x2),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Recipe name'),
            ),
            const SizedBox(height: AppSpacing.x2),
            TextField(
              controller: _servingsController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Makes how many servings',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.x3),
            RecipeIngredientsHeader(onAdd: _addIngredient),
            const SizedBox(height: AppSpacing.x1),
            for (var i = 0; i < _items.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              RecipeItemRow(
                key: ValueKey(_items[i].id),
                item: _items[i],
                onEditGrams: () => _editGrams(i),
                onRemove: () => _removeItem(i),
              ),
            ],
            if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
                child: Text(
                  'No ingredients left — add at least one before saving.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x2),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ),
      ),
    );
  }
}
