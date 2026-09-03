import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';

import '../../../domain/models/workout_session.dart';

/// The next-session entry on the Train dashboard: a flat, divider-bound row —
/// "Repeat Upper" with a quiet meta line ("7 exercises · ~60 min") and a small
/// blue text-button "Start". No filled hero card.
class NextSessionRow extends StatelessWidget {
  const NextSessionRow({
    super.key,
    required this.title,
    required this.meta,
    required this.onStart,
  });

  final String title;
  final String meta;
  final VoidCallback onStart;

  /// Builds the row for the last completed [session] (repeat variant), or the
  /// first-workout variant when there is no history yet.
  ///
  /// [readinessBand] (R2, optional) appends a calm band-driven suffix to the
  /// meta line — a pure annotation. `null` leaves the meta exactly as today, so
  /// existing call sites and tests are unaffected.
  factory NextSessionRow.forSession(
    WorkoutSession? session, {
    Key? key,
    required VoidCallback onStart,
    RecoveryFlowBand? readinessBand,
  }) {
    if (session == null) {
      return NextSessionRow(
        key: key,
        title: 'Start your first workout',
        meta: 'Your progress builds from here',
        onStart: onStart,
      );
    }
    return NextSessionRow(
      key: key,
      title: 'Repeat ${session.name}',
      meta: _metaWithReadiness(_metaFor(session), readinessBand),
      onStart: onStart,
    );
  }

  /// Appends a quiet, band-driven suffix to the meta line. Only the lower bands
  /// add a gentle suggestion; Ready/Charged add nothing (the Start CTA already
  /// reads as "go"). Never a block — always a calm suffix.
  static String _metaWithReadiness(String meta, RecoveryFlowBand? band) {
    final suffix = switch (band) {
      RecoveryFlowBand.recharge => 'lighter day suggested',
      RecoveryFlowBand.steady => 'moderate day',
      RecoveryFlowBand.ready => null,
      RecoveryFlowBand.charged => null,
      null => null,
    };
    if (suffix == null) return meta;
    return '$meta · $suffix';
  }

  static String _metaFor(WorkoutSession session) {
    final exerciseCount = session.exercises
        .where((e) => e.sets.isNotEmpty)
        .length;
    final parts = <String>[
      exerciseCount == 1 ? '1 exercise' : '$exerciseCount exercises',
    ];
    final estimate = _durationEstimate(session);
    if (estimate != null) parts.add('~$estimate min');
    return parts.join(' · ');
  }

  /// A rough duration estimate. Prefers the actual logged duration of the
  /// source session; otherwise estimates from total set count (~2.5 min/set,
  /// a calm working-set pace). Null when there is no signal to estimate from.
  static int? _durationEstimate(WorkoutSession session) {
    final logged = session.endTime?.difference(session.startTime).inMinutes;
    if (logged != null && logged > 0) {
      // Round to the nearest 5 so it reads as an estimate, not a stopwatch.
      return ((logged / 5).round() * 5).clamp(5, 240);
    }
    final totalSets = session.exercises.fold<int>(
      0,
      (sum, e) => sum + e.sets.length,
    );
    if (totalSets == 0) return null;
    return ((totalSets * 2.5 / 5).round() * 5).clamp(5, 240);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Semantics(
      container: true,
      button: true,
      label: '$title. $meta. Start',
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x2,
            AppSpacing.x2,
            AppSpacing.x2,
            AppSpacing.x2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              FilledButton(
                onPressed: () {
                  Haptics.confirm();
                  onStart();
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x3,
                    vertical: AppSpacing.x1 + 2,
                  ),
                ),
                child: const Text('Start'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
