import 'package:flutter/material.dart';

import 'design.dart';
import 'evaluator_scope.dart';

class TrainingScreen extends StatelessWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = EvaluatorScope.of(context);
    return ListView(
      children: [
        const PageHeading(
          title: 'Train with context',
          subtitle:
              'Your training, recovery, and nutrition work together before the plan changes.',
        ),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            const _Metric(
              label: 'This week',
              value: '4 sessions',
              icon: Icons.bolt,
            ),
            const _Metric(
              label: 'Readiness',
              value: '42 · Recharge',
              icon: Icons.favorite,
            ),
            _Metric(
              label: 'Protein',
              value:
                  '${state.todayProtein.round()} / ${state.nutritionTargets.protein.round()} g',
              icon: Icons.restaurant,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Today’s recommendation',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(
                'Use a lower-volume upper session. Sleep and HRV are below baseline, so preserve strength while trimming fatigue.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 18),
              const Row(
                children: [
                  Icon(Icons.check_circle_outline, color: blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Last: Lower strength · 64 min · completed'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 245,
    child: SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: blue),
          const SizedBox(height: 20),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(label),
        ],
      ),
    ),
  );
}
