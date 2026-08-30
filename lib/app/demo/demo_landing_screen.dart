import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// Public evaluator entrypoint for the WebMCP challenge build.
class DemoLandingScreen extends StatelessWidget {
  const DemoLandingScreen({super.key});

  static const _pillars = <({IconData icon, String title, String body})>[
    (
      icon: Icons.fitness_center_outlined,
      title: 'Training',
      body: 'Plan workouts and review progression with bounded context.',
    ),
    (
      icon: Icons.bedtime_outlined,
      title: 'Recovery',
      body: 'Balance readiness, sleep, soreness, and recent workload.',
    ),
    (
      icon: Icons.restaurant_outlined,
      title: 'Nutrition',
      body: 'Log meals and shape targets without losing human control.',
    ),
    (
      icon: Icons.forum_outlined,
      title: 'Coach',
      body: 'Keep every proposed change visible, reviewable, and reversible.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final horizontal = wide ? AppSpacing.x4 : AppSpacing.x2;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontal,
              AppSpacing.x5,
              horizontal,
              AppSpacing.x6,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label(colors: colors),
                    const SizedBox(height: AppSpacing.x3),
                    Text(
                      'One coach for training, recovery, and nutrition.',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: AppSpacing.x2),
                    Text(
                      'Hustl gives AI the right context while you stay in '
                      'control. AI proposes, you review, and Hustl records '
                      'the decision.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x3),
                    FilledButton.icon(
                      onPressed: () => context.go('/'),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Try the demo'),
                    ),
                    const SizedBox(height: AppSpacing.x5),
                    Text(
                      'A collaborative coaching loop',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      'Ask, inspect, propose, review. Nothing important '
                      'happens invisibly.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x3),
                    _PillarGrid(wide: wide, colors: colors),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: AppRadius.pillRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2,
          vertical: AppSpacing.x1,
        ),
        child: Text(
          'Hustl WebMCP evaluator',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PillarGrid extends StatelessWidget {
  const _PillarGrid({required this.wide, required this.colors});

  final bool wide;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = wide
            ? (constraints.maxWidth - AppSpacing.x2) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: AppSpacing.x2,
          runSpacing: AppSpacing.x2,
          children: [
            for (final pillar in DemoLandingScreen._pillars)
              SizedBox(
                width: cardWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: AppRadius.cardRadius,
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Padding(
                    padding: AppSpacing.cardPadding,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(pillar.icon, color: colors.primary),
                        const SizedBox(width: AppSpacing.x2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pillar.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.x1),
                              Text(
                                pillar.body,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: colors.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
