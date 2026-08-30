import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/app_section.dart';
import '../../../../core/widgets/staggered_entrance.dart';
import '../bloc/health_overview_bloc.dart';
import 'dashboard/conditions_copy.dart';
import 'dashboard/health_dashboard_biology.dart';
import 'dashboard/health_dashboard_insights.dart';
import 'dashboard/health_dashboard_today.dart';
import 'recovery_signal_prompt.dart';

/// "Conditions Report" (Biology redesign): the health dashboard reads as a
/// stack of premium grouped cards — the conditions hero, the instruments row,
/// the coach's route call, and a 7-day conditions strip (the "Today" group),
/// then the Body baselines card and the insights deck — each on
/// `colorScheme.surface` with tokenised radii / spacing, introduced by
/// sentence-case [SectionHeader] titles. The stacked column plays a one-time
/// staggered entrance.
class HealthDashboardView extends StatelessWidget {
  const HealthDashboardView({super.key, required this.state});

  final HealthOverviewState state;

  @override
  Widget build(BuildContext context) {
    // Today's snapshot is often blank until the current day finishes syncing.
    // Fall back to the most recent day that actually carries recovery data so
    // the hero shows a real band from a strong baseline instead of a blank
    // "Building" estimate. `latestRecovery` is what the hero renders;
    // `isStale` drives the subtle "as of <day>" indicator below it.
    final snapshots = state.recoverySnapshots;
    final latest = latestRecoverySnapshot(snapshots);
    final latestRecovery = latest.snapshot;
    final isStaleRecovery = latest.isStale;
    final weightTrend = state.summaries
        .map((summary) => summary.latestWeightKg)
        .whereType<double>()
        .toList();
    final bmiTrend = state.summaries
        .map((summary) => summary.bodyMassIndex)
        .whereType<double>()
        .toList();

    // Left column: the conditions hero + instruments + coaching + week strip
    // (the "Today" group). Right column: the Body baselines grid + insights.
    final todayGroup = TodayOverviewGroup(
      snapshot: latestRecovery,
      recoverySnapshots: snapshots,
      lastSyncedAt: state.lastSyncedAt,
      signalAvailability: state.signalAvailability,
      isStale: isStaleRecovery,
    );
    final baselines = <Widget>[
      const SectionHeader('Body'),
      BiologyGrid(
        latestWeightKg: state.latestWeightKg,
        latestBmi: state.latestBmi,
        weeklyWeightChangeKg: state.weeklyWeightChangeKg,
        weightTrend: weightTrend,
        bmiTrend: bmiTrend,
      ),
      if (state.insights.isNotEmpty) ...[
        const SectionHeader('Insights'),
        InsightDeck(insights: state.insights),
      ],
    ];

    // Contextual nudge when core recovery signals aren't flowing. It lives in
    // the scroll content (it belongs to the dashboard) and is added only when
    // it will actually render, so it reserves zero height when hidden.
    final availability = state.signalAvailability;
    final showSignalPrompt =
        availability.hasAnySignal && availability.missingSignals.isNotEmpty;

    return RefreshIndicator(
      onRefresh: () async {
        context.read<HealthOverviewBloc>().add(const HealthOverviewRefreshed());
      },
      child: ListView(
        // The scroll viewport extends to the physical bottom of the screen
        // (the screen's SafeArea does not consume the bottom inset), so the
        // content padding carries the home-indicator inset itself: content
        // draws under the indicator while scrolling, and clears it at rest.
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.x4,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: _isWide(context)
                  // Wide (landscape tablet / desktop): the instrument splits
                  // into two side-by-side columns within the single page
                  // scroll. Below the breakpoint it stays one stacked column.
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: todayGroup),
                        const SizedBox(width: AppSpacing.x3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: baselines,
                          ),
                        ),
                      ],
                    )
                  : StaggeredEntrance(
                      animationKey: 'health-dashboard',
                      children: [todayGroup, ...baselines],
                    ),
            ),
          ),
          if (showSignalPrompt)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.x2),
                  child: RecoverySignalPrompt(availability: availability),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Width at and above which the health dashboard splits into two columns.
/// Matches the shell's wide breakpoint so it engages only on landscape
/// tablet / desktop.
const double _kHealthWideBreakpoint = 900;

bool _isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= _kHealthWideBreakpoint;
