import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/features/workout_logging/domain/utils/effort_scale.dart';
import 'package:hustl_app/core/utils/number_format_util.dart';
import 'package:hustl_app/core/widgets/app_section.dart';

import '../../domain/models/workout_exercise.dart';
import '../../domain/models/workout_set.dart';
import '../../../../core/utils/time_format_util.dart';
import '../../../exercise_library/domain/models/exercise.dart';

/// Flat per-exercise recap rows: name, optional heart-rate line, and the
/// logged sets as a quiet tabular text line (PR sets emphasized in green).
/// Hairline dividers between rows, no icon blocks, no chips.
class WorkoutExerciseSummaryList extends StatelessWidget {
  final List<WorkoutExercise> exercises;
  final bool showTitle;
  final String? highlightExerciseKey;
  const WorkoutExerciseSummaryList({
    super.key,
    required this.exercises,
    this.showTitle = true,
    this.highlightExerciseKey,
  });

  @override
  Widget build(BuildContext context) {
    GlobalKey? highlightTileKey;
    final normalizedHighlightKey = highlightExerciseKey?.toLowerCase();

    final rows = exercises.map((exercise) {
      final exerciseKey =
          Exercise.canonicalKeyFrom(
            name: exercise.exercise.name,
            slug: exercise.exercise.slug,
          ) ??
          exercise.exercise.name.trim().toLowerCase();
      final isHighlight =
          normalizedHighlightKey != null &&
          normalizedHighlightKey == exerciseKey;
      final row = _ExerciseRow(exercise: exercise);
      if (!isHighlight) return row as Widget;
      return Container(
        key: highlightTileKey ??= GlobalKey(),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.primary),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1),
        child: row,
      );
    }).toList();

    // Bring the highlighted exercise into view after build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (highlightTileKey?.currentContext != null) {
        Scrollable.ensureVisible(
          highlightTileKey!.currentContext!,
          alignment: 0.1,
          duration: const Duration(milliseconds: 300),
        );
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle)
          const SectionHeader('Exercises', padding: EdgeInsets.only(bottom: 4)),
        SectionList(children: rows),
      ],
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise});

  final WorkoutExercise exercise;

  String _setLabel(WorkoutSet set) {
    final base = switch (exercise.exercise.loggingMode) {
      ExerciseLoggingMode.distanceDuration =>
        '${NumberFormatUtil.formatWeight(set.weight)} km × '
            '${TimeFormatUtil.formatMmSs(set.reps)}',
      ExerciseLoggingMode.durationOnly => TimeFormatUtil.formatMmSs(set.reps),
      ExerciseLoggingMode.weightReps =>
        '${set.reps} × ${NumberFormatUtil.formatWeight(set.weight)}',
    };
    // Effort shows as RIR (e.g. "(RIR 2)") in the dense ·-joined recap line.
    final rir = EffortScale.rirLabelFromRpe(set.rpe);
    return rir == null ? base : '$base (RIR $rir)';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final completedSets = exercise.sets.where((set) => set.reps > 0).toList();

    final metrics = exercise.metrics;
    final hrRawValue = metrics?['hr'];
    final hrRaw = hrRawValue is Map ? hrRawValue : null;
    final effortRawValue = metrics?['effort'];
    final effortRaw = effortRawValue is Map ? effortRawValue : null;
    final hrEffort = (effortRaw?['hr1to10'] as num?)?.toInt();
    final avgHr = (hrRaw?['avgBpm'] as num?)?.toDouble();
    final maxHr = (hrRaw?['maxBpm'] as num?)?.toDouble();

    final caption = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(exercise.exercise.name, style: theme.textTheme.bodyLarge),
          if (hrEffort != null || avgHr != null || maxHr != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                [
                  if (hrEffort != null) 'HR effort $hrEffort/10',
                  if (avgHr != null) 'Avg ${avgHr.round()} bpm',
                  if (maxHr != null) 'Max ${maxHr.round()} bpm',
                ].join(' · '),
                style: caption,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: completedSets.isEmpty
                ? Text('No completed sets', style: caption)
                : Text.rich(
                    TextSpan(
                      children: [
                        for (var i = 0; i < completedSets.length; i++) ...[
                          if (i > 0) const TextSpan(text: '  ·  '),
                          TextSpan(
                            text: completedSets[i].isPr
                                ? '${_setLabel(completedSets[i])} PR'
                                : _setLabel(completedSets[i]),
                            style: completedSets[i].isPr
                                ? TextStyle(
                                    color: AppColors.accentEmeraldGreen,
                                    fontWeight: FontWeight.w600,
                                  )
                                : null,
                          ),
                        ],
                      ],
                    ),
                    style: caption?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
