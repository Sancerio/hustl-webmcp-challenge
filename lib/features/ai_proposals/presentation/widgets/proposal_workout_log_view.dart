import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/app_section.dart';
import '../../domain/models/proposal_detail.dart';
import '../../domain/models/proposed_workout_log.dart';

/// Renders a `workout_log` proposal: the session name + when, then each exercise
/// with its sets (strength: weight×reps; cardio: distance/time). Approving writes
/// a completed session (undoable — the session is deleted on undo).
class ProposalWorkoutLogView extends StatelessWidget {
  const ProposalWorkoutLogView({
    super.key,
    required this.detail,
    this.terminal = false,
  });

  final ProposalDetail detail;
  final bool terminal;

  static String _meta(ProposedWorkoutLog w) {
    final parts = <String>[];
    final n = w.exercises.length;
    parts.add('$n exercise${n == 1 ? '' : 's'}');
    final sets = w.totalSets;
    parts.add('$sets set${sets == 1 ? '' : 's'}');
    final dur = w.durationSeconds;
    if (dur != null && dur > 0) parts.add('${(dur / 60).round()} min');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final w = detail.proposedWorkoutLog;
    if (w == null || w.exercises.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Banner(title: w.name, subtitle: _meta(w)),
        const SizedBox(height: AppSpacing.x2),
        const SectionHeader(
          'Exercises',
          padding: EdgeInsets.only(bottom: AppSpacing.x1),
        ),
        SectionList(
          card: true,
          children: [for (final ex in w.exercises) _ExerciseRow(exercise: ex)],
        ),
        if ((w.notes ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.x1),
          Text(
            w.notes!.trim(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        if (!terminal) ...[
          const SizedBox(height: AppSpacing.x1),
          Text(
            'Logged by your assistant — undo right after approving, or edit the '
            'session in your history.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.x2),
      decoration: BoxDecoration(
        color: AppColors.accentEmeraldGreen.withValues(alpha: 0.10),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          Icon(
            Icons.fitness_center_outlined,
            size: 18,
            color: AppColors.accentEmeraldGreen,
          ),
          const SizedBox(width: AppSpacing.x1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise});

  final ProposedWorkoutExercise exercise;

  static String _setLabel(ProposedWorkoutSet s) {
    // Strength: weight × reps. Cardio: distance / duration. Either may be partial.
    final hasStrength = s.weight != null || s.reps != null;
    final hasCardio = s.distance != null || s.durationSeconds != null;
    String base;
    if (hasStrength || !hasCardio) {
      final w = s.weight;
      final r = s.reps;
      if (w != null && r != null) {
        base = '${_trim(w)} kg × $r';
      } else if (w != null) {
        base = '${_trim(w)} kg';
      } else if (r != null) {
        base = '$r reps';
      } else {
        base = '1 set';
      }
    } else {
      final parts = <String>[];
      if (s.distance != null) parts.add('${_trim(s.distance! / 1000)} km');
      if (s.durationSeconds != null) parts.add(_duration(s.durationSeconds!));
      base = parts.join(' · ');
    }
    if (s.rpe != null) {
      base = '$base @ RPE ${_trim(s.rpe!)}';
    }
    if (s.setType != null && s.setType != 'regular') {
      base = '$base (${s.setType})';
    }
    return base;
  }

  static String _trim(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }

  static String _duration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(exercise.name, style: theme.textTheme.bodyLarge),
              ),
              Text(
                '${exercise.sets.length} set${exercise.sets.length == 1 ? '' : 's'}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            exercise.sets.map(_setLabel).join('   ·   '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
