import 'package:flutter/material.dart';

import '../model/models.dart';
import 'charts.dart';
import 'design.dart';
import 'evaluator_scope.dart';

class NutritionScreen extends StatelessWidget {
  const NutritionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = EvaluatorScope.of(context);
    final targets = state.nutritionTargets;
    final remaining = (targets.calories - state.todayCalories).clamp(
      0,
      double.infinity,
    );
    return ListView(
      children: [
        const PageHeading(
          title: 'Nutrition',
          subtitle: 'Monday, 31 August · intake and targets',
        ),
        const _DateStrip(),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final summary = _MacroSummary(
              calories: state.todayCalories,
              remaining: remaining,
              protein: state.todayProtein,
              carbs: state.todayCarbs,
              fat: state.todayFat,
              calorieTarget: targets.calories,
              proteinTarget: targets.protein,
              carbsTarget: targets.carbs,
              fatTarget: targets.fat,
            );
            const balance = _EnergyBalance();
            if (constraints.maxWidth < 760) {
              return Column(
                children: [summary, const SizedBox(height: 14), balance],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: summary),
                const SizedBox(width: 14),
                const Expanded(flex: 5, child: balance),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        _MealTimeline(entries: state.foodEntries),
      ],
    );
  }
}

class _DateStrip extends StatelessWidget {
  const _DateStrip();

  @override
  Widget build(BuildContext context) => const HustlPanel(
    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Icon(Icons.chevron_left_rounded, color: hustleMuted),
        _Day(day: 'F', date: '28'),
        _Day(day: 'S', date: '29'),
        _Day(day: 'S', date: '30'),
        _Day(day: 'M', date: '31', selected: true),
        _Day(day: 'T', date: '1'),
        _Day(day: 'W', date: '2'),
        _Day(day: 'T', date: '3'),
        Icon(Icons.chevron_right_rounded, color: hustleMuted),
      ],
    ),
  );
}

class _Day extends StatelessWidget {
  const _Day({required this.day, required this.date, this.selected = false});
  final String day;
  final String date;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: selected ? hustleBlue : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      children: [
        Text(day, style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 2),
        Text(date, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _MacroSummary extends StatelessWidget {
  const _MacroSummary({
    required this.calories,
    required this.remaining,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.calorieTarget,
    required this.proteinTarget,
    required this.carbsTarget,
    required this.fatTarget,
  });
  final double calories;
  final num remaining;
  final double protein;
  final double carbs;
  final double fat;
  final num calorieTarget;
  final num proteinTarget;
  final num carbsTarget;
  final num fatTarget;

  @override
  Widget build(BuildContext context) => HustlPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HustlSectionTitle('Today'),
        Row(
          children: [
            RingMetric(
              value: calories / calorieTarget,
              center: _displayNumber(remaining),
              caption: 'kcal left',
              color: hustleBlue,
              size: 116,
            ),
            const SizedBox(width: 22),
            Expanded(
              child: Column(
                children: [
                  _Macro(
                    label: 'Protein',
                    value: protein,
                    target: proteinTarget,
                    color: macroProtein,
                  ),
                  _Macro(
                    label: 'Carbs',
                    value: carbs,
                    target: carbsTarget,
                    color: macroCarbs,
                  ),
                  _Macro(
                    label: 'Fat',
                    value: fat,
                    target: fatTarget,
                    color: macroFat,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${_displayNumber(calories)} / ${_displayNumber(calorieTarget)} kcal',
        ),
      ],
    ),
  );
}

class _Macro extends StatelessWidget {
  const _Macro({
    required this.label,
    required this.value,
    required this.target,
    required this.color,
  });
  final String label;
  final num value;
  final num target;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text('${_displayNumber(value)} / ${_displayNumber(target)} g'),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: (value / target).clamp(0, 1),
            minHeight: 6,
            color: color,
          ),
        ),
      ],
    ),
  );
}

class _EnergyBalance extends StatelessWidget {
  const _EnergyBalance();

  @override
  Widget build(BuildContext context) => const HustlPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HustlSectionTitle('Energy balance'),
        Row(
          children: [
            Text(
              '−410',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            SizedBox(width: 6),
            Text('kcal today'),
          ],
        ),
        SizedBox(height: 16),
        Sparkline(
          values: [-180, -260, -210, -330, -290, -380, -410],
          color: hustleEmerald,
          height: 105,
        ),
        SizedBox(height: 10),
        Text('A steady deficit without an aggressive recovery cost.'),
      ],
    ),
  );
}

class _MealTimeline extends StatelessWidget {
  const _MealTimeline({required this.entries});
  final List<FoodLogEntry> entries;

  @override
  Widget build(BuildContext context) => HustlPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HustlSectionTitle('${entries.length} meals logged'),
        for (var index = 0; index < entries.length; index++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 5),
                child: StatusDot(color: hustleBlue, size: 9),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entries[index].foodName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_displayNumber(entries[index].calories)} kcal · '
                      '${_displayNumber(entries[index].proteinGrams)} g protein',
                    ),
                  ],
                ),
              ),
              const Text('Today', style: TextStyle(color: hustleMuted)),
            ],
          ),
          if (index != entries.length - 1) const Divider(height: 28),
        ],
      ],
    ),
  );
}

String _displayNumber(num value) {
  final text = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
  return text.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}
