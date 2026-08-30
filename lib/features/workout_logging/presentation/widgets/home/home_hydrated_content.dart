import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';
import 'package:hustl_app/core/widgets/animated_metric_text.dart';
import 'package:hustl_app/core/widgets/app_progress_ring.dart';
import 'package:hustl_app/core/widgets/app_section.dart';
import 'package:hustl_app/core/widgets/coach_card.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/workout_templates/domain/models/workout_template.dart';

import '../../../domain/models/workout_session.dart';
import '../../../domain/services/next_workout_focus_service.dart';
import 'home_volume_trend_chart.dart';
import 'home_week_stats.dart';
import 'kg_format.dart';
import 'next_session_row.dart';
import 'readiness_today_slot.dart';
import 'train_section_rows.dart';
import 'training_balance_coach.dart';
import 'week_training_widget.dart';

const _sectionHeaderPadding = EdgeInsets.only(
  top: AppSpacing.x3,
  bottom: AppSpacing.x1,
);

class _FixedValueListenable<T> implements ValueListenable<T> {
  const _FixedValueListenable(this.value);

  @override
  final T value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// The Train dashboard column (MacroFactor language): the week training
/// widget, a flat divider-bound next-session row, then TRAINING / THIS WEEK /
/// INSIGHTS sections built from 13px UPPERCASE headers and hairline rows.
class HomeHydratedContent extends StatelessWidget {
  const HomeHydratedContent({
    super.key,
    required this.recent,
    required this.stats,
    required this.templates,
    required this.onStartEmptyWorkout,
    required this.onRepeatSession,
    required this.onOpenTemplates,
    required this.onOpenBodyScore,
    this.focus,
    this.readiness,
    this.weeklyWorkoutGoal = 3,
    this.focusListenable,
    this.readinessStateListenable,
    this.weeklyWorkoutGoalListenable,
  });

  /// Most recent completed sessions (newest first) — drives the
  /// next-session row.
  final List<WorkoutSession> recent;

  /// The recent-window aggregation that drives the week widget, the hero
  /// numerals and the volume trend. Computed OFF the build path (in the screen's
  /// async load) and cached, so `build()` never re-runs the O(recent) nested
  /// set-iteration on every rebuild (FAB scroll toggles, readiness/goal loads,
  /// parent rebuilds) — which on Flutter web runs inline on the UI thread.
  final HomeWeekStats stats;

  final List<WorkoutTemplate> templates;
  final NextWorkoutFocusPlan? focus;
  final VoidCallback onStartEmptyWorkout;
  final ValueChanged<WorkoutSession> onRepeatSession;
  final VoidCallback onOpenTemplates;
  final VoidCallback onOpenBodyScore;

  /// Optional latest readiness snapshot (R2) for static previews and tests.
  /// Production passes [readinessStateListenable] so loading, available, and
  /// unavailable states resolve without changing the dashboard's geometry.
  final DailyRecoverySnapshot? readiness;

  /// Weekly workout-count goal (same value the Progress screen uses; default
  /// 3/wk). Drives the hero ring's goal progress and emerald goal-met state.
  final int weeklyWorkoutGoal;

  /// Production passes independent live values so a late readiness read cannot
  /// rebuild the hero/week bars, and a goal read cannot rebuild readiness or
  /// coaching. Null retains the static constructor API used by previews/tests.
  final ValueListenable<NextWorkoutFocusPlan?>? focusListenable;
  final ValueListenable<ReadinessTodayState>? readinessStateListenable;
  final ValueListenable<int>? weeklyWorkoutGoalListenable;

  /// Wide-layout breakpoint (matches `ResponsiveCenter.wideBreakpoint`): at and
  /// above this width the dashboard reflows into two side-by-side columns.
  static const double _wideBreakpoint = 900;

  @override
  Widget build(BuildContext context) {
    final lastSession = recent.isNotEmpty ? recent.first : null;
    final liveFocus = focusListenable ?? _FixedValueListenable(focus);
    final initialReadinessState =
        readiness != null && readiness!.hasRecoveryData
        ? ReadinessTodayState.available(readiness!)
        : const ReadinessTodayState.unavailable();
    final liveReadinessState =
        readinessStateListenable ??
        _FixedValueListenable(initialReadinessState);
    final liveWeeklyGoal =
        weeklyWorkoutGoalListenable ?? _FixedValueListenable(weeklyWorkoutGoal);

    final templatesSubtitle = templates.isEmpty
        ? 'Save a workout to reuse it'
        : '${templates.length} saved '
              '${templates.length == 1 ? 'routine' : 'routines'}';

    // The four logical blocks of the dashboard, grouped into a primary
    // (hero + next-session) group and a secondary (Training + Volume trend)
    // group. Both layouts reuse these so behaviour stays identical.
    final heroBlock = ValueListenableBuilder<int>(
      valueListenable: liveWeeklyGoal,
      builder: (context, goal, _) => _TrainHeroCard(
        stats: stats,
        weeklyWorkoutGoal: goal,
        // Any prior logged session means this isn't their first workout — so an
        // empty current week reads as a "fresh week", not a first-run welcome.
        hasHistory: recent.isNotEmpty,
      ),
    );
    final readinessAndNextSession = ValueListenableBuilder<ReadinessTodayState>(
      valueListenable: liveReadinessState,
      builder: (context, readinessState, _) {
        final readiness = readinessState.snapshot;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.x2),
            ReadinessTodaySlot(state: readinessState),
            const SizedBox(height: AppSpacing.x3),
            NextSessionRow.forSession(
              lastSession,
              onStart: lastSession == null
                  ? onStartEmptyWorkout
                  : () => onRepeatSession(lastSession),
              readinessBand: readiness?.flowBand,
            ),
          ],
        );
      },
    );
    const trainingHeader = SectionHeader(
      'Training',
      padding: _sectionHeaderPadding,
    );
    // Training-balance coaching, surfaced INLINE as the shared coach card so the
    // actual guidance ("Add 3 chest sets" + why) is visible without a tap. When
    // there's no plan yet (no completed sessions), fall back to the plain nav
    // row so the body-score detail stays reachable.
    final trainingBlock = ValueListenableBuilder<NextWorkoutFocusPlan?>(
      valueListenable: liveFocus,
      builder: (context, coachPlan, _) {
        // Training-balance coaching, surfaced INLINE as the shared coach card
        // so the actual guidance is visible without a tap. When there's no
        // plan yet, fall back to the plain nav row.
        final trainingCoachCard = coachPlan == null
            ? null
            : CoachCard(
                insight: trainingBalanceInsight(
                  coachPlan,
                  onSeeDetails: onOpenBodyScore,
                ),
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trainingCoachCard != null) ...[
              trainingCoachCard,
              const SizedBox(height: AppSpacing.x2),
            ],
            SectionList(
              card: true,
              children: [
                TrainNavRow(
                  title: 'Templates',
                  subtitle: templatesSubtitle,
                  onTap: onOpenTemplates,
                ),
                if (trainingCoachCard == null)
                  TrainNavRow(
                    title: 'Training balance',
                    subtitle: 'See which muscles need work',
                    onTap: onOpenBodyScore,
                  ),
              ],
            ),
          ],
        );
      },
    );
    const volumeHeader = SectionHeader(
      'Volume trend',
      padding: _sectionHeaderPadding,
    );
    final volumeChart = HomeVolumeTrendChart(
      weeklyVolumes: stats.weeklyVolumes,
    );

    final isWide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    if (isWide) {
      // Two-column dashboard: primary blocks (hero + Start) on the left,
      // secondary blocks (Training + Volume trend) on the right, side by side
      // within the existing single page scroll. Columns size to their own
      // content (start-aligned), so neither is stretched to match the other.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [heroBlock, readinessAndNextSession],
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    trainingHeader,
                    trainingBlock,
                    volumeHeader,
                    volumeChart,
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }

    // This is the app's default landing surface, and users often start
    // scrolling as soon as workout data hydrates. Keep the dashboard static:
    // animating every full-width section's opacity/translation while the same
    // layers are scrolling causes visible raster contention on a cold launch.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        heroBlock,
        readinessAndNextSession,
        trainingHeader,
        trainingBlock,
        volumeHeader,
        volumeChart,
      ],
    );
  }
}

/// The Train hero (Wave I — Apple Fitness+ x Whoop): a week ring that tracks
/// the weekly WORKOUT goal — filling as workouts are logged and turning emerald
/// once the goal is met — with the workouts count BIG in its centre, the week
/// volume as a large numeral beside it, and the 7-day bars below.
class _TrainHeroCard extends StatelessWidget {
  const _TrainHeroCard({
    required this.stats,
    required this.weeklyWorkoutGoal,
    required this.hasHistory,
  });

  final HomeWeekStats stats;

  /// Weekly workout-count goal (the same value the Progress screen uses).
  final int weeklyWorkoutGoal;

  /// Whether the user has any logged workout history. Drives whether an empty
  /// current week reads as a brand-new welcome or a returning "fresh week".
  final bool hasHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // Fully empty current week: no workouts, no volume, no sets logged. We swap
    // the dead "0 ring + 0 kg" hero for an inviting welcome so the user is
    // greeted, not graded. The blue Start CTA lives in the next-session row
    // directly below this card.
    final isEmptyWeek =
        stats.weekWorkouts == 0 && stats.weekVolume <= 0 && stats.weekSets == 0;
    if (isEmptyWeek) {
      return _EmptyWeekHeroCard(stats: stats, isNewUser: !hasHistory);
    }

    // The ring tracks the weekly WORKOUT goal so it and the centre numeral mean
    // the same thing: "N of {goal} workouts". It turns emerald — the app's
    // success/goal-met tone — once the goal is met, otherwise stays blue.
    final goal = weeklyWorkoutGoal > 0 ? weeklyWorkoutGoal : 3;
    final goalMet = stats.weekWorkouts >= goal;
    final ringProgress = (stats.weekWorkouts / goal).clamp(0.0, 1.0);
    final ringColor = goalMet ? colors.tertiary : colors.primary;

    final bigNumberStyle = TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: 34,
      height: 1.0,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.0,
      color: colors.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppProgressRing(
                progress: ringProgress,
                size: 104,
                strokeWidth: 11,
                color: ringColor,
                trackColor: colors.outlineVariant.withValues(alpha: 0.5),
                semanticsLabel: goalMet
                    ? 'Weekly goal met: ${stats.weekWorkouts} of $goal '
                          'workouts'
                    : '${stats.weekWorkouts} of $goal weekly workouts',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedMetricText(
                      value: stats.weekWorkouts.toDouble(),
                      style: bigNumberStyle,
                      semanticsLabel: stats.weekWorkouts == 1
                          ? '1 workout this week'
                          : '${stats.weekWorkouts} workouts this week',
                    ),
                    Text(
                      'of $goal',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'This week',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatCompactKg(stats.weekVolume),
                      style: bigNumberStyle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'kg volume · ${stats.weekSets} sets',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          WeekTrainingWidget(stats: stats, showSummary: false),
        ],
      ),
    );
  }
}

/// The Train hero for an empty current week. Same elevated card and week strip
/// as the hydrated hero, but the dead "0 ring + 0 kg" is replaced with a soft
/// blue-tinted glyph, a confident headline and one supportive line. The blue
/// Start CTA sits in the next-session row directly below, so this hero is the
/// warm invitation that leads into it — never a grade.
///
/// Copy adapts to [isNewUser]: a brand-new user is welcomed to their first
/// workout, while a returning user whose current week is simply empty gets a
/// "fresh week" nudge — never told this is their first workout.
class _EmptyWeekHeroCard extends StatelessWidget {
  const _EmptyWeekHeroCard({required this.stats, required this.isNewUser});

  final HomeWeekStats stats;
  final bool isNewUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final title = isNewUser
        ? 'Your first workout starts here'
        : 'New week, fresh start';
    final body = isNewUser
        ? 'Log a session and your week, volume and trends come to life.'
        : 'Log a session to light up this week’s ring, volume and trends.';
    final hint = isNewUser
        ? 'Log your first workout'
        : 'No workouts logged yet this week';

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.fromLTRB(18, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Soft blue-tinted circular holder — a welcome, not a placeholder.
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary.withValues(alpha: 0.10),
                ),
                alignment: Alignment.center,
                child: HustlIcon(
                  asset: 'assets/icons/ic_dumbbell.svg',
                  size: 26,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      body,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          WeekTrainingWidget(
            stats: stats,
            showSummary: false,
            firstRun: true,
            emptyHint: hint,
          ),
        ],
      ),
    );
  }
}
