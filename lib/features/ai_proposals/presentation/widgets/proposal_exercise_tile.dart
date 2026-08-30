import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/number_format_util.dart';
import '../../../workout_logging/domain/utils/effort_scale.dart';
import '../../../../core/utils/text_format.dart';
import '../../../../core/widgets/hustl_icon.dart';

/// A read-only exercise tile for a proposed template, sized to sit inside a
/// grouped `SectionList(card:true)`. This mirrors the private
/// `_buildExerciseTile`/`_exerciseSummary`/`_exerciseLeading` helpers in
/// `template_detail_screen.dart` (which can't be reused cross-file), rendering
/// the same opaque `{exerciseId:<name>, sets:int, restTimerSeconds:int,
/// previousSets:[...]}` Map.
class ProposalExerciseTile extends StatelessWidget {
  const ProposalExerciseTile({
    super.key,
    required this.exercise,
    this.tone,
    this.trailing,
  });

  /// The render-Map (see [ProposedExercise.toRenderMap]).
  final Map<String, dynamic> exercise;

  /// Optional row tint for diff classification (add/change/remove).
  final Color? tone;

  final Widget? trailing;

  static String summaryFor(Map<String, dynamic> exercise) {
    final sets = (exercise['sets'] as num?)?.toInt() ?? 1;
    final parts = <String>['$sets sets'];
    final previousSets =
        exercise['previousSets'] as List<dynamic>? ?? const [];
    final reps = previousSets
        .whereType<Map>()
        .map((set) => set['reps'])
        .whereType<int>()
        .where((value) => value > 0)
        .toList();
    if (reps.isNotEmpty) {
      final uniqueReps = reps.toSet().toList()..sort();
      parts.add(
        uniqueReps.length == 1
            ? '${uniqueReps.first} reps'
            : 'reps ${uniqueReps.join('/')}',
      );
    }
    // Weight is persisted into the template on apply, so disclose it here.
    final weights = previousSets
        .whereType<Map>()
        .map((set) => (set['weight'] as num?)?.toDouble())
        .whereType<double>()
        .where((value) => value > 0)
        .toList();
    if (weights.isNotEmpty) {
      final uniqueWeights = weights.toSet().toList()..sort();
      final label = uniqueWeights.length == 1
          ? NumberFormatUtil.formatWeight(uniqueWeights.first)
          : uniqueWeights.map(NumberFormatUtil.formatWeight).join('/');
      parts.add('$label kg');
    }
    final restSeconds = (exercise['restTimerSeconds'] as num?)?.toInt();
    if (restSeconds != null && restSeconds > 0) {
      final minutes = restSeconds ~/ 60;
      final seconds = restSeconds % 60;
      if (minutes == 0) {
        parts.add('${seconds}s rest');
      } else {
        parts.add(seconds == 0 ? '${minutes}m rest' : '${minutes}m ${seconds}s rest');
      }
    }
    final first = previousSets.isNotEmpty ? previousSets.first : null;
    final rpe = first is Map ? first['rpe'] : null;
    if (rpe is int) parts.add('RIR ${EffortScale.rirLabelFromRpe(rpe)}');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final name = exercise['exerciseId'] as String? ?? '';
    final notes = (exercise['notes'] as String?)?.trim();
    final tint = tone ?? colors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        // Top-align so the glyph anchors to the name, not floating mid-tile when
        // a long note makes the row tall.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: HustlIcon(
                asset: 'assets/icons/ic_dumbbell.svg',
                size: 20,
                color: tint,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + diff badge share the top line so the badge anchors to
                // the name and the note below can use the full column width.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        formatExerciseName(name),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: AppSpacing.x1),
                      trailing!,
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  summaryFor(exercise),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.x1),
                  Text(
                    notes,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
