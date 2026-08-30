import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/food_log_entry.dart';
import 'recipes_browser.dart';

/// Standalone full-screen recipe browser. A thin wrapper around
/// [RecipesBrowser]; picking a recipe pops the dialog with its entries.
class RecipesDialog extends StatelessWidget {
  const RecipesDialog({super.key, required this.date, this.defaultLoggedAt});

  final DateTime date;
  final DateTime? defaultLoggedAt;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Recipes'),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.close),
              tooltip: 'Close',
            ),
          ],
        ),
        body: SafeArea(
          child: RecipesBrowser(
            date: date,
            defaultLoggedAt: defaultLoggedAt,
            onPick: (entries) => context.pop<List<FoodLogEntry>>(entries),
          ),
        ),
      ),
    );
  }
}
