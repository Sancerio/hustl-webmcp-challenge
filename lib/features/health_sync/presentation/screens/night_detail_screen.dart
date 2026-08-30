import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/service_locator.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/app_section.dart';
import '../../../../core/widgets/coach_card.dart';
import '../../../../core/widgets/hustl_inline_skeleton.dart';
import '../../../../core/widgets/hustl_menu_button.dart';
import '../../../../core/widgets/main_scaffold.dart';
import '../../../../core/widgets/screen_empty_state.dart';
import '../../domain/models/daily_recovery_snapshot.dart';
import '../../domain/repositories/health_metrics_repository.dart';
import '../bloc/health_overview_bloc.dart';
import '../widgets/dashboard/conditions_copy.dart';
import '../widgets/dashboard/night_panel.dart';
import '../widgets/dashboard/night_signal_rows.dart';
import '../widgets/dashboard/recovery_coach.dart';

/// Route payload for `/health/night`, carried via GoRouter `extra` when pushed
/// from the overview — mirrors the `/progress/body-score` route's `extra`
/// convention — so the detail screen renders from data the overview already
/// loaded instead of re-fetching. Falls back to its own [HealthOverviewBloc]
/// when reached without it (e.g. a cold deep link).
class NightDetailArgs {
  const NightDetailArgs({required this.recoverySnapshots, this.lastSyncedAt});

  final List<DailyRecoverySnapshot> recoverySnapshots;
  final DateTime? lastSyncedAt;
}

/// The "Last night" detail screen ("Night Shift" direction): the story of
/// last night, ending in today's plan.
class NightDetailScreen extends StatelessWidget {
  const NightDetailScreen({super.key, this.args, this.repositoryOverride});

  final NightDetailArgs? args;
  final HealthMetricsRepository? repositoryOverride;

  @override
  Widget build(BuildContext context) {
    final fromRoute = args;
    if (fromRoute != null) {
      return _NightDetailScaffold(
        recoverySnapshots: fromRoute.recoverySnapshots,
        lastSyncedAt: fromRoute.lastSyncedAt,
      );
    }

    final repository = repositoryOverride ?? getIt<HealthMetricsRepository>();
    return BlocProvider<HealthOverviewBloc>(
      create: (_) =>
          HealthOverviewBloc(repository)..add(const HealthOverviewStarted()),
      child: BlocBuilder<HealthOverviewBloc, HealthOverviewState>(
        builder: (context, state) {
          if (state.status != HealthOverviewStatus.ready) {
            return MainScaffold(
              appBar: _nightAppBar(),
              child: const SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.x2),
                  child: HustlInlineSkeleton(
                    padding: EdgeInsets.zero,
                    rows: 6,
                    semanticsLabel: 'Loading last night',
                  ),
                ),
              ),
            );
          }
          return _NightDetailScaffold(
            recoverySnapshots: state.recoverySnapshots,
            lastSyncedAt: state.lastSyncedAt,
          );
        },
      ),
    );
  }
}

AppBar _nightAppBar() {
  return AppBar(
    automaticallyImplyLeading: false,
    leading: const HustlMenuButton(),
    title: const Text('Last night'),
    centerTitle: true,
    elevation: 0,
  );
}

class _NightDetailScaffold extends StatelessWidget {
  const _NightDetailScaffold({
    required this.recoverySnapshots,
    required this.lastSyncedAt,
  });

  final List<DailyRecoverySnapshot> recoverySnapshots;
  final DateTime? lastSyncedAt;

  @override
  Widget build(BuildContext context) {
    final snapshot = latestRecoverySnapshot(recoverySnapshots).snapshot;
    final hasSleepData = snapshot?.sleepDurationMinutes != null;

    return MainScaffold(
      appBar: _nightAppBar(),
      child: SafeArea(
        child: !hasSleepData || snapshot == null
            ? ScreenEmptyState(
                icon: Icons.bedtime_outlined,
                title: 'No sleep data for last night yet',
                message:
                    'Once your device syncs an overnight session, the story '
                    'of last night will show up here.',
                actionLabel: 'Back to overview',
                onAction: () =>
                    context.canPop() ? context.pop() : context.go('/health'),
              )
            : _NightDetailContent(
                snapshot: snapshot,
                recoverySnapshots: recoverySnapshots,
                lastSyncedAt: lastSyncedAt,
              ),
      ),
    );
  }
}

class _NightDetailContent extends StatelessWidget {
  const _NightDetailContent({
    required this.snapshot,
    required this.recoverySnapshots,
    required this.lastSyncedAt,
  });

  final DailyRecoverySnapshot snapshot;
  final List<DailyRecoverySnapshot> recoverySnapshots;
  final DateTime? lastSyncedAt;

  String? _summaryLine() {
    final parts = <String>[];
    final sleep = snapshot.sleepDurationMinutes;
    if (sleep != null) parts.add('${formatHoursMinutes(sleep)} asleep');
    final awake = snapshot.awakeMinutes;
    if (awake != null && awake > 0) {
      parts.add('${formatHoursMinutes(awake)} awake');
    }
    final efficiency = snapshot.sleepEfficiency;
    if (efficiency != null) {
      parts.add('${(efficiency * 100).round()}% efficiency');
    }
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = MaterialLocalizations.of(context);
    final baselines = ConditionsBaselines.fromSnapshots(
      recoverySnapshots,
      snapshot,
    );
    final summary = _summaryLine();

    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.x1, bottom: AppSpacing.x4),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
          child: Text(
            l10n.formatFullDate(snapshot.date.toLocal()),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
          child: NightPanelHero(snapshot: snapshot),
        ),
        if (summary != null) ...[
          const SizedBox(height: AppSpacing.x1 + 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
            child: Text(
              summary,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
        const SectionHeader('What tonight built'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
          child: NightSignalRows(snapshot: snapshot, baselines: baselines),
        ),
        const SectionHeader('Today, adjusted'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
          child: CoachCard(insight: recoveryCoachInsight(snapshot)),
        ),
        if (lastSyncedAt != null) ...[
          const SizedBox(height: AppSpacing.x3),
          Center(
            child: Text(
              'Synced ${l10n.formatMediumDate(lastSyncedAt!.toLocal())} at '
              '${l10n.formatTimeOfDay(TimeOfDay.fromDateTime(lastSyncedAt!.toLocal()))}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
