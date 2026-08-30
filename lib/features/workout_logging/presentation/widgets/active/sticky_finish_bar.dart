import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/app_progress_ring.dart';

/// The persistent bottom action for the active workout — the approved
/// "Split Smart" design.
///
/// It sits directly on the scaffold canvas (no surface box, no hairline band):
/// a short top-to-transparent scrim lets scrolling content fade out beneath it.
///
/// Two states, driven by [completedSets]:
///   * State A — at least one set is completed: a contextual split with a small
///     emerald progress ring + a two-line muted summary on the left, and a
///     prominent blue "Finish" button on the right.
///   * State B — nothing logged yet (no completed sets, which also covers an
///     empty workout): the bar collapses to a single calm, centered,
///     low-emphasis ghost "Cancel workout" button. Finishing a workout with
///     nothing logged is meaningless — it would discard anyway — so the action
///     is honestly surfaced as cancel/discard via [onCancel].
class StickyFinishBar extends StatelessWidget {
  const StickyFinishBar({
    super.key,
    required this.completedSets,
    required this.totalSets,
    required this.totalVolume,
    required this.exerciseCount,
    required this.onFinish,
    required this.onCancel,
    this.showVolume = true,
  });

  /// Number of completed sets across the session.
  final int completedSets;

  /// Total number of sets across the session.
  final int totalSets;

  /// Total volume (sum of weight × reps for completed sets), in kg.
  final double totalVolume;

  /// Whether the "· N kg" volume segment is shown. Pass false for sessions
  /// with no weight-based exercises (e.g. a run), where "0 kg" is noise.
  final bool showVolume;

  /// Number of exercises in the session.
  final int exerciseCount;

  /// Invoked when the user confirms the workout is done (State A).
  final VoidCallback onFinish;

  /// Invoked when the user discards an empty workout (State B). Reuses the
  /// screen's existing cancel/discard confirmation flow.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaffoldBg = theme.scaffoldBackgroundColor;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    // A short top-to-transparent scrim using the scaffold background so content
    // scrolling underneath fades out before reaching the action.
    final content = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [scaffoldBg, scaffoldBg, scaffoldBg.withValues(alpha: 0)],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.x2,
          AppSpacing.x3,
          AppSpacing.x2,
          AppSpacing.x1 + bottomInset,
        ),
        child: completedSets > 0
            ? _SplitSummary(
                completedSets: completedSets,
                totalSets: totalSets,
                totalVolume: totalVolume,
                exerciseCount: exerciseCount,
                onFinish: onFinish,
                showVolume: showVolume,
              )
            : _EmptyCancel(onCancel: onCancel),
      ),
    );

    return content;
  }
}

/// State A: emerald ring + two-line summary on the left, blue Finish on the
/// right.
class _SplitSummary extends StatelessWidget {
  const _SplitSummary({
    required this.completedSets,
    required this.totalSets,
    required this.totalVolume,
    required this.exerciseCount,
    required this.onFinish,
    required this.showVolume,
  });

  final int completedSets;
  final int totalSets;
  final double totalVolume;
  final int exerciseCount;
  final VoidCallback onFinish;
  final bool showVolume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final progress = totalSets > 0 ? completedSets / totalSets : 0.0;
    final isComplete = totalSets > 0 && completedSets >= totalSets;
    final percent = (progress.clamp(0.0, 1.0) * 100).round();

    const tabular = [FontFeature.tabularFigures()];

    final ring = AppProgressRing(
      progress: progress,
      size: 42,
      strokeWidth: 4,
      color: AppColors.accentEmeraldGreen,
      semanticsLabel: 'Workout progress',
      child: isComplete
          ? Icon(
              Icons.check_rounded,
              size: 18,
              color: AppColors.accentEmeraldGreen,
            )
          : Text(
              '$percent',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
                fontFeatures: tabular,
              ),
            ),
    );

    final setsLabel = '$completedSets of $totalSets sets';
    final summaryLabel = showVolume
        ? '$setsLabel · ${_formatVolume(totalVolume)} kg'
        : setsLabel;
    final exerciseLabel =
        '$exerciseCount ${exerciseCount == 1 ? 'exercise' : 'exercises'}';

    final summary = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          summaryLabel,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w600,
            fontFeatures: tabular,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          exerciseLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
            fontFeatures: tabular,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    return Row(
      children: [
        ExcludeSemantics(child: ring),
        const SizedBox(width: AppSpacing.x1 + 4),
        Expanded(child: summary),
        const SizedBox(width: AppSpacing.x2),
        Semantics(
          button: true,
          label: 'Finish workout',
          child: FilledButton.icon(
            onPressed: onFinish,
            icon: const Icon(Icons.check_rounded, size: 20),
            label: const Text('Finish'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x3,
                vertical: 14,
              ),
              shape: const RoundedRectangleBorder(
                borderRadius: AppRadius.controlRadius,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatVolume(double volume) {
    // Whole-kilo display; group thousands for readability.
    final rounded = volume.round();
    final digits = rounded.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

/// State B: a single calm, centered, low-emphasis ghost "Cancel workout"
/// button with a subtle alert tint and an X glyph.
class _EmptyCancel extends StatelessWidget {
  const _EmptyCancel({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.accentAlertRed;

    return Center(
      child: Semantics(
        button: true,
        label: 'Cancel workout',
        child: OutlinedButton.icon(
          onPressed: onCancel,
          icon: Icon(Icons.close_rounded, size: 18, color: tint),
          label: Text('Cancel workout', style: TextStyle(color: tint)),
          style: OutlinedButton.styleFrom(
            foregroundColor: tint,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x3,
              vertical: 12,
            ),
            side: BorderSide(color: tint.withValues(alpha: 0.4)),
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.pillRadius,
            ),
          ),
        ),
      ),
    );
  }
}
