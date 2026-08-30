import 'package:flutter/material.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/effort/effort_reserve_gauge.dart';
import 'package:intl/intl.dart';

import 'history_session_metrics.dart';

/// A single workout-history tile. Wave I (Apple Fitness+ x Whoop): each session
/// is its own elevated surface card so the list reads as a stack of workouts,
/// not a spreadsheet ledger. Tapping opens the summary directly; the trailing
/// swipe reveals a quick delete, and a long-press opens the full action menu
/// (handled by the parent via [onLongPress]).
class HistorySessionCard extends StatelessWidget {
  const HistorySessionCard({
    super.key,
    required this.session,
    required this.metrics,
    required this.onOpenSummary,
    required this.onLongPress,
    required this.onSwipeDelete,
  });

  final WorkoutSession session;
  final HistorySessionMetrics metrics;
  final VoidCallback onOpenSummary;
  final VoidCallback onLongPress;

  /// Returns true to confirm the delete (card animates out), false to cancel.
  final Future<bool> Function() onSwipeDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasDetails = session.exercises.isNotEmpty;

    final tile = Material(
      color: colors.surface,
      borderRadius: _cardRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenSummary,
        onLongPress: () {
          Haptics.maybeLightImpact();
          onLongPress();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Hero(
                      tag: 'history_session_title_${session.id}',
                      flightShuttleBuilder: _titleFlightShuttle,
                      child: Material(
                        type: MaterialType.transparency,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.name,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatDate(session.startTime),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Hero(
                tag: 'history_session_stats_${session.id}',
                child: Material(
                  type: MaterialType.transparency,
                  child: _CompactStatsRow(
                    durationText: metrics.durationText,
                    prs: metrics.prCount,
                    volume: metrics.totalVolume,
                  ),
                ),
              ),
              if (hasDetails) ...[
                const SizedBox(height: 12),
                _ExerciseBestSetTable(
                  session: session,
                  bestSetFor: (id) => metrics.bestSetByExerciseId[id] ?? '-',
                  bestSetRpeFor: (id) => metrics.bestSetRpeByExerciseId[id],
                  onShowMore: onOpenSummary,
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text('Tap to view exercises', style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('dismiss_${session.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => onSwipeDelete(),
      background: _SwipeDeleteBackground(color: colors.error),
      child: tile,
    );
  }

  /// The rounded radius shared by the card surface and its swipe background.
  static final BorderRadius _cardRadius = BorderRadius.circular(20);

  /// During the Hero flight, keep the text readable in both contexts by
  /// providing a simple cross-fade from the card style to the destination style.
  static Widget _titleFlightShuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final from = fromHeroContext.widget as Hero;
        final to = toHeroContext.widget as Hero;
        return Opacity(
          opacity: 1.0,
          child: flightDirection == HeroFlightDirection.push
              ? FadeTransition(opacity: animation, child: to.child)
              : FadeTransition(
                  opacity: ReverseAnimation(animation),
                  child: from.child,
                ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final day = DateFormat('EEE').format(local);
    final date = DateFormat('d MMM yyyy').format(local);
    final time = DateFormat('h:mm a').format(local);
    return '$day, $date · $time';
  }
}

class _SwipeDeleteBackground extends StatelessWidget {
  const _SwipeDeleteBackground({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Icon(Icons.delete_outline, color: color),
    );
  }
}

/// Aligned stat row: each item is a quiet label over a tabular value. Wave G
/// §12 keeps icons subtle (onSurfaceVariant), not accent-shouting.
class _CompactStatsRow extends StatelessWidget {
  const _CompactStatsRow({
    required this.durationText,
    required this.prs,
    required this.volume,
  });

  final String durationText;
  final int? prs;
  final int? volume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    Widget item(IconData icon, String value) {
      return Expanded(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: muted),
            const SizedBox(width: 6),
            Text(value, style: theme.textTheme.labelLarge),
          ],
        ),
      );
    }

    return Row(
      children: [
        item(Icons.timer_outlined, durationText),
        item(Icons.emoji_events_outlined, prs?.toString() ?? '—'),
        item(Icons.trending_up, volume == null ? '—' : '$volume kg'),
      ],
    );
  }
}

class _ExerciseBestSetTable extends StatelessWidget {
  const _ExerciseBestSetTable({
    required this.session,
    required this.bestSetFor,
    required this.bestSetRpeFor,
    required this.onShowMore,
  });

  final WorkoutSession session;
  final String Function(String exerciseId) bestSetFor;

  /// The RPE logged on that exercise's best set, when available — drives the
  /// compact effort gauge next to the best-set label.
  final int? Function(String exerciseId) bestSetRpeFor;
  final VoidCallback onShowMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = session.exercises;
    final visible = items.take(4).toList();
    final remaining = items.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 4),
          child: Text(
            'Best sets',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Divider(),
        for (int i = 0; i < visible.length; i++)
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        visible[i].exercise.name,
                        style: theme.textTheme.bodyLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (bestSetRpeFor(visible[i].id) != null) ...[
                            EffortReserveGauge(
                              rpe: bestSetRpeFor(visible[i].id),
                              showLabel: true,
                              pipSize: 5,
                              pipGap: 2,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              bestSetFor(visible[i].id),
                              style: theme.textTheme.labelLarge,
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (i < visible.length - 1) const Divider(),
            ],
          ),
        if (remaining > 0) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onShowMore,
              icon: const Icon(Icons.more_horiz, size: 18),
              label: Text('Show $remaining more'),
            ),
          ),
        ],
      ],
    );
  }
}
