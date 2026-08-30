import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/food_log_entry.dart';

class QuickAddDialog extends StatefulWidget {
  const QuickAddDialog({super.key, required this.date, this.defaultLoggedAt});

  final DateTime date;
  final DateTime? defaultLoggedAt;

  @override
  State<QuickAddDialog> createState() => _QuickAddDialogState();
}

class _QuickAddDialogState extends State<QuickAddDialog> {
  final _grams = TextEditingController(text: '100');
  final _calories = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();

  @override
  void dispose() {
    _grams.dispose();
    _calories.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quick Add'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_grams, 'Serving (g)'),
          _field(_calories, 'Calories (kcal)'),
          _field(_protein, 'Protein (g)'),
          _field(_carbs, 'Carbs (g)'),
          _field(_fat, 'Fat (g)'),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Leave calories blank to estimate from macros.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => context.pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final grams =
                double.tryParse(_grams.text.trim().replaceAll(',', '.')) ?? 100;
            if (grams <= 0) return;
            final protein =
                double.tryParse(_protein.text.trim().replaceAll(',', '.')) ?? 0;
            final carbs =
                double.tryParse(_carbs.text.trim().replaceAll(',', '.')) ?? 0;
            final fat =
                double.tryParse(_fat.text.trim().replaceAll(',', '.')) ?? 0;
            // Calories fill in from macros (4/4/9 kcal per gram) when blank, so
            // a macros-only quick add still carries energy.
            final caloriesText = _calories.text.trim().replaceAll(',', '.');
            final derivedCals = protein * 4 + carbs * 4 + fat * 9;
            final cals = caloriesText.isEmpty
                ? derivedCals
                : double.tryParse(caloriesText) ?? derivedCals;
            final seed = widget.defaultLoggedAt?.toLocal();
            final now = seed ?? DateTime.now();
            final loggedAt = DateTime(
              widget.date.year,
              widget.date.month,
              widget.date.day,
              now.hour,
              now.minute,
              now.second,
            );
            final entry = FoodLogEntry(
              id: 'temp-${DateTime.now().microsecondsSinceEpoch}',
              date: widget.date,
              loggedAt: loggedAt,
              servingGrams: grams,
              calories: cals,
              proteinGrams: protein,
              carbsGrams: carbs,
              fatGrams: fat,
              foodName: 'Quick add',
              source: 'quick_add',
            );
            context.pop(entry);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
