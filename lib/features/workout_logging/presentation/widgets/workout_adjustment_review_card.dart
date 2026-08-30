import 'package:flutter/material.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/webmcp/active_workout_web_mcp_controller.dart';
import '../../domain/models/workout_set.dart';

class WorkoutAdjustmentReviewCard extends StatelessWidget {
  const WorkoutAdjustmentReviewCard({
    super.key,
    required this.adjustment,
    required this.onApply,
    required this.onDiscard,
  });

  final StagedWorkoutAdjustment adjustment;
  final Future<void> Function() onApply;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      key: const Key('workoutAdjustmentReviewCard'),
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.x2,
        AppSpacing.x2,
        AppSpacing.x2,
        0,
      ),
      padding: const EdgeInsets.all(AppSpacing.x2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: colors.primary.withValues(alpha: 0.38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 19,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Review suggested changes',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Nothing changes until you apply them.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.x1,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Not applied',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          for (var index = 0; index < adjustment.changes.length; index++) ...[
            _ChangeRow(change: adjustment.changes[index]),
            if (index != adjustment.changes.length - 1)
              Divider(height: AppSpacing.x3, color: colors.outlineVariant),
          ],
          const SizedBox(height: AppSpacing.x2),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('discardWorkoutAdjustment'),
                  onPressed: onDiscard,
                  child: const Text('Discard'),
                ),
              ),
              const SizedBox(width: AppSpacing.x1),
              Expanded(
                flex: 2,
                child: FilledButton(
                  key: const Key('applyWorkoutAdjustment'),
                  onPressed: () => onApply(),
                  child: const Text('Apply changes'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change});

  final WorkoutSetAdjustment change;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changedFields = _changedFields(change.before, change.after);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${change.exerciseName} · Set ${change.setNumber}',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          changedFields.join('  ·  '),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  static List<String> _changedFields(WorkoutSet before, WorkoutSet after) {
    final fields = <String>[];
    if (before.weight != after.weight) {
      fields.add('Weight ${_number(before.weight)} → ${_number(after.weight)}');
    }
    if (before.reps != after.reps) {
      fields.add('Reps ${before.reps} → ${after.reps}');
    }
    if (before.rpe != after.rpe) {
      fields.add('RPE ${before.rpe ?? '—'} → ${after.rpe ?? '—'}');
    }
    return fields;
  }

  static String _number(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';
}
