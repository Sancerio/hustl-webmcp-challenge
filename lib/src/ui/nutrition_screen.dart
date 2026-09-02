import 'package:flutter/material.dart';

import 'design.dart';
import 'evaluator_scope.dart';

class NutritionScreen extends StatelessWidget {
  const NutritionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = EvaluatorScope.of(context);
    final targets = state.nutritionTargets;
    final calories = state.todayCalories;
    final protein = state.todayProtein;
    final carbs = state.todayCarbs;
    final fat = state.todayFat;
    return ListView(
      children: [
        const PageHeading(
          title: 'Nutrition',
          subtitle:
              'Today’s logged intake stays separate from any targets waiting in Coach.',
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Today', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 18),
              _Progress(
                label: 'Calories',
                value:
                    '${_displayNumber(calories)} / ${_displayNumber(targets.calories)} kcal',
                fraction: calories / targets.calories,
              ),
              _Progress(
                label: 'Protein',
                value:
                    '${_displayNumber(protein)} / ${_displayNumber(targets.protein)} g',
                fraction: protein / targets.protein,
              ),
              _Progress(
                label: 'Carbs',
                value:
                    '${_displayNumber(carbs)} / ${_displayNumber(targets.carbs)} g',
                fraction: carbs / targets.carbs,
              ),
              _Progress(
                label: 'Fat',
                value:
                    '${_displayNumber(fat)} / ${_displayNumber(targets.fat)} g',
                fraction: fat / targets.fat,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              child: Icon(Icons.breakfast_dining_outlined),
            ),
            title: Text('${state.foodEntries.length} meals logged'),
            subtitle: const Text(
              'Food proposals remain pending until you review them in Coach.',
            ),
          ),
        ),
      ],
    );
  }
}

String _displayNumber(num value) {
  final text = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
  final parts = text.split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return parts.length == 1 ? grouped : '$grouped.${parts.last}';
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.label,
    required this.value,
    required this.fraction,
  });

  final String label;
  final String value;
  final double fraction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(value),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: fraction.clamp(0, 1),
          minHeight: 8,
          borderRadius: BorderRadius.circular(8),
          backgroundColor: line,
        ),
      ],
    ),
  );
}
