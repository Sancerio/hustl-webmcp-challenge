import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'design.dart';
import 'evaluator_scope.dart';

class TemplatesScreen extends StatelessWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final templates = EvaluatorScope.of(context).templates;
    return ListView(
      children: [
        const PageHeading(
          title: 'Templates',
          subtitle:
              'Programs become live only after you approve their Coach proposal.',
        ),
        for (final template in templates) ...[
          SurfaceCard(
            padding: const EdgeInsets.all(8),
            child: ListTile(
              onTap: () => context.go('/templates/${template.id}'),
              leading: const CircleAvatar(child: Icon(Icons.fitness_center)),
              title: Text(template.name),
              subtitle: Text('${template.exercises.length} exercises'),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class TemplateDetailScreen extends StatelessWidget {
  const TemplateDetailScreen({super.key, required this.templateId});

  final String templateId;

  @override
  Widget build(BuildContext context) {
    final state = EvaluatorScope.of(context);
    final template = state.templateById(templateId);
    if (template == null) {
      return const Center(child: Text('Template not found'));
    }
    return ListView(
      children: [
        TextButton.icon(
          onPressed: () => context.go('/templates'),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Back to Templates'),
        ),
        const SizedBox(height: 12),
        PageHeading(
          title: template.name,
          subtitle: template.description ?? 'Workout template',
        ),
        for (final exercise in template.exercises) ...[
          SurfaceCard(
            child: Row(
              children: [
                const CircleAvatar(child: Icon(Icons.fitness_center, size: 18)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.exercises
                                .where(
                                  (fixture) =>
                                      fixture.id == exercise['exerciseId'],
                                )
                                .map((fixture) => fixture.name)
                                .firstOrNull ??
                            exercise['exerciseId']! as String,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${exercise['sets']} sets · ${exercise['repsTarget'] ?? '—'} reps · RPE ${exercise['rpeTarget'] ?? '—'}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
