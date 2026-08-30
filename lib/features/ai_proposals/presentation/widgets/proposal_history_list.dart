import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/widgets/app_section.dart';
import '../../../../core/widgets/hustl_inline_skeleton.dart';
import '../../../../core/widgets/screen_empty_state.dart';
import '../../../../core/widgets/staggered_entrance.dart';
import '../../../../core/widgets/hustl_snack.dart';
import '../../domain/models/proposal_summary.dart';
import '../bloc/proposal_history_cubit.dart';
import 'proposal_history_row.dart';

/// The History tab body: consumes [ProposalHistoryCubit] and renders a
/// day-grouped, newest-first list of decided proposals — a sibling of the
/// pending inbox's `SectionList(card: true)` layout.
class ProposalHistoryList extends StatelessWidget {
  const ProposalHistoryList({super.key});

  /// 'Today' / 'Yesterday' / 'EEE, d MMM' for the LOCAL calendar day of [time].
  /// Day distance is computed on UTC date-only anchors so a 23-hour
  /// spring-forward day can't collapse "yesterday" into "today".
  static String _dayHeader(DateTime time) {
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final day = DateTime.utc(time.year, time.month, time.day);
    final diffDays = today.difference(day).inDays;
    if (diffDays == 0) return 'Today';
    if (diffDays == 1) return 'Yesterday';
    return DateFormat('EEE, d MMM').format(time);
  }

  static DateTime _activityTime(ProposalSummary p) =>
      p.decidedAt ?? p.createdAt;

  /// Groups [items] by the LOCAL calendar day of `decidedAt ?? createdAt`,
  /// newest-first — sorted here (not trusting server order) so a proposal
  /// decided today but created earlier still lands under "Today", and an
  /// optimistically-undone row (its decidedAt advanced to now) moves up.
  static List<MapEntry<String, List<ProposalSummary>>> _groupByDay(
    List<ProposalSummary> items,
  ) {
    final sorted = [...items]
      ..sort((a, b) => _activityTime(b).compareTo(_activityTime(a)));
    final grouped = <String, List<ProposalSummary>>{};
    for (final item in sorted) {
      final header = _dayHeader(_activityTime(item));
      grouped.putIfAbsent(header, () => []).add(item);
    }
    return grouped.entries.toList();
  }

  Future<void> _handleUndo(BuildContext context, ProposalSummary p) async {
    Haptics.selection();
    final cubit = context.read<ProposalHistoryCubit>();
    final success = await cubit.revert(p);
    if (!context.mounted) return;
    if (success) {
      final message = p.isWorkoutLog
          ? 'Workout removed'
          : p.isFoodLogRevision
          ? 'Change undone'
          : 'Removed from your diary';
      HustlSnack.show(context, message, variant: HustlSnackVariant.success);
    } else {
      HustlSnack.show(
        context,
        "Couldn't undo — remove it manually instead",
        variant: HustlSnackVariant.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProposalHistoryCubit, ProposalHistoryState>(
      builder: (context, state) {
        if (state is ProposalHistoryLoading ||
            state is ProposalHistoryInitial) {
          return const HustlInlineSkeleton();
        }
        if (state is ProposalHistoryFailure) {
          return ScreenEmptyState(
            icon: Icons.cloud_off_rounded,
            title: "We couldn't load your activity",
            message: state.message,
            actionLabel: 'Try again',
            onAction: () => context.read<ProposalHistoryCubit>().load(),
          );
        }
        final loaded = state as ProposalHistoryLoaded;
        if (loaded.items.isEmpty) {
          return RefreshIndicator(
            onRefresh: () => context.read<ProposalHistoryCubit>().refresh(),
            child: ListView(
              children: const [
                SizedBox(height: 80),
                ScreenEmptyState(
                  icon: Icons.history,
                  title: 'No AI activity yet',
                  message:
                      'When your connected AI logs a meal or workout, edits '
                      'an entry, or updates a plan, it shows up here.',
                ),
              ],
            ),
          );
        }
        final groups = _groupByDay(loaded.items);
        return RefreshIndicator(
          onRefresh: () => context.read<ProposalHistoryCubit>().refresh(),
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.x3),
            children: [
              // First-view stagger only; revisits + revert rebuilds render static.
              StaggeredEntrance(
                animationKey: 'ai-activity-history',
                children: [
                  for (final group in groups) ...[
                    SectionHeader(group.key),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.x2,
                      ),
                      child: SectionList(
                        card: true,
                        children: [
                          for (final p in group.value)
                            ProposalHistoryRow(
                              proposal: p,
                              isBusy: loaded.inFlightIds.contains(p.id),
                              onUndo: () => _handleUndo(context, p),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
