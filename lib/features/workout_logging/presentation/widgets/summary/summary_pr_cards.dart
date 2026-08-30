import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/utils/number_format_util.dart';
import 'package:hustl_app/core/utils/time_format_util.dart';
import 'package:hustl_app/core/widgets/app_section.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/effort/effort_reserve_gauge.dart';
import '../../../domain/models/workout_session.dart';

/// A personal-record achieved this session.
class SummaryPrEntry {
  const SummaryPrEntry({
    required this.exerciseName,
    required this.weight,
    required this.reps,
    this.loggingMode = ExerciseLoggingMode.weightReps,
    this.rpe,
  });

  final String exerciseName;
  final double weight;
  final int reps;
  final ExerciseLoggingMode loggingMode;

  /// The PR set's stored RPE, when logged. Optional — older sets may not
  /// carry effort data.
  final int? rpe;
}

/// Extracts every PR set from a session, newest exercises first.
List<SummaryPrEntry> prEntriesFromSession(WorkoutSession session) {
  final entries = <SummaryPrEntry>[];
  for (final exercise in session.exercises) {
    if (exercise.exercise.loggingMode != ExerciseLoggingMode.weightReps) {
      continue;
    }
    for (final set in exercise.sets) {
      if (set.reps > 0 && set.isPr) {
        entries.add(
          SummaryPrEntry(
            exerciseName: exercise.exercise.name,
            weight: set.weight,
            reps: set.reps,
            loggingMode: exercise.exercise.loggingMode,
            rpe: set.rpe,
          ),
        );
      }
    }
  }
  return entries;
}

/// PR rows for the records hit this session — a kind, quiet celebration:
/// a green-tinted flat row per record (success accent), no shame for non-PR
/// sets, which simply do not appear here.
class SummaryPrCards extends StatelessWidget {
  const SummaryPrCards({super.key, required this.entries});

  final List<SummaryPrEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          entries.length == 1 ? 'New personal record' : 'New personal records',
          padding: const EdgeInsets.only(bottom: AppSpacing.x1),
        ),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.x1),
            child: _PrRow(entry: entry),
          ),
      ],
    );
  }
}

class _PrRow extends StatelessWidget {
  const _PrRow({required this.entry});

  final SummaryPrEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.accentEmeraldGreen; // success, never a warning
    final metricLabel = switch (entry.loggingMode) {
      ExerciseLoggingMode.distanceDuration =>
        '${NumberFormatUtil.formatWeight(entry.weight)} km × '
            '${TimeFormatUtil.formatMmSs(entry.reps)}',
      ExerciseLoggingMode.durationOnly => TimeFormatUtil.formatMmSs(entry.reps),
      ExerciseLoggingMode.weightReps =>
        '${NumberFormatUtil.formatWeight(entry.weight)} kg × ${entry.reps}',
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.emoji_events_rounded, size: 18, color: accent),
          const SizedBox(width: AppSpacing.x1),
          Expanded(
            child: Text(
              entry.exerciseName,
              style: theme.textTheme.bodyLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.x1),
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.x1,
              runSpacing: 4,
              children: [
                Text(metricLabel, style: theme.textTheme.labelLarge),
                if (entry.rpe != null) EffortReserveGauge(rpe: entry.rpe),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
