import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/screen_empty_state.dart';
import 'package:hustl_app/core/navigation/workout_minimize_intent.dart';
import '../../../../workout_templates/domain/models/workout_template.dart';

/// Bottom sheet that lists every saved template and starts a workout from one.
/// Replaces the inline extension method that previously lived on the home
/// screen state. Reachable from the Templates entry card.
Future<void> showHomeTemplatePicker(
  BuildContext context, {
  required List<WorkoutTemplate> templates,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // Push on the root navigator so this sheet does not linger on the active
    // tab branch navigator after a tab switch (which would leave the tab root's
    // `canPop()` true and flip its avatar to a back chevron).
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (sheetContext) => _TemplatePickerSheet(
      templates: templates,
      onStart: (t) {
        sheetContext.pop();
        context.go(
          '/workout_session',
          extra: workoutRouteExtra(context, _extraFromTemplate(t)),
        );
      },
      onSeeAll: () {
        sheetContext.pop();
        context.push('/templates');
      },
      onStartWorkout: () {
        sheetContext.pop();
        context.go('/workout_session', extra: workoutRouteExtra(context));
      },
    ),
  );
}

Map<String, dynamic> _extraFromTemplate(WorkoutTemplate t) => {
  'initialName': t.name,
  'initialExercises': t.exercises
      .map(
        (e) => {
          'name': e['exerciseId'] as String? ?? '',
          'sets': (e['sets'] as int?) ?? 1,
          'rest': e['restTimerSeconds'] as int?,
          'previousSets': e['previousSets'] as List<dynamic>?,
          'previousSetsAreTemplateTargets': true,
          // Provenance: template prescription targets are separate from true
          // previous-session history, especially for zero-load weight×reps rows.
          'targetsArePlaceholder': e['targetsArePlaceholder'] == true,
        },
      )
      .toList(),
};

class _TemplatePickerSheet extends StatelessWidget {
  const _TemplatePickerSheet({
    required this.templates,
    required this.onStart,
    required this.onSeeAll,
    required this.onStartWorkout,
  });

  final List<WorkoutTemplate> templates;
  final ValueChanged<WorkoutTemplate> onStart;
  final VoidCallback onSeeAll;
  final VoidCallback onStartWorkout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x2,
          AppSpacing.x2,
          AppSpacing.x2,
          AppSpacing.x3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Templates', style: theme.textTheme.titleLarge),
                ),
                if (templates.isNotEmpty)
                  TextButton(onPressed: onSeeAll, child: const Text('See all')),
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x1),
            if (templates.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
                child: ScreenEmptyState(
                  icon: Icons.fitness_center_rounded,
                  assetIcon: 'assets/icons/empty_workout.svg',
                  title: 'No templates yet',
                  message:
                      'Finish a workout and save it as a template to reuse it '
                      'here.',
                  actionLabel: 'Start a workout',
                  onAction: onStartWorkout,
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: templates.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.x1),
                  itemBuilder: (context, index) {
                    final t = templates[index];
                    return Material(
                      color: colors.surface,
                      borderRadius: AppRadius.controlRadius,
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.controlRadius,
                          side: BorderSide(color: colors.outlineVariant),
                        ),
                        title: Text(t.name, style: theme.textTheme.titleMedium),
                        subtitle: Text(
                          t.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        trailing: FilledButton.tonalIcon(
                          onPressed: () => onStart(t),
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('Start'),
                        ),
                        onTap: () => onStart(t),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
