import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/utils/number_format_util.dart';
import 'package:hustl_app/core/widgets/animated_metric_text.dart';
import 'package:hustl_app/core/widgets/app_progress_ring.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';

import 'progress_trend_stat_card.dart';

/// Hero stat block at the top of the Progress screen (Wave I — Apple Fitness+ x
/// Whoop, "data as hero"): a blue goal ring with the goal-hit count BIG in its
/// centre, paired with the volume trend on a quiet aligned row beneath — all
/// inside one elevated card.
class ProgressHeroSection extends StatefulWidget {
  const ProgressHeroSection({
    super.key,
    required this.goalHitWeeks,
    required this.goalWindowWeeks,
    required this.weeklyGoal,
    required this.lastWeeksVolume,
    required this.prevWeeksVolume,
    required this.weeksCount,
    this.weeklyVolumeSeries = const [],
  });

  /// Number of weeks (within [goalWindowWeeks]) where the weekly goal was met.
  final int goalHitWeeks;

  /// Number of recent weeks the goal-hit rate is measured over.
  final int goalWindowWeeks;

  final int weeklyGoal;
  final double lastWeeksVolume;
  final double prevWeeksVolume;
  final int weeksCount;

  /// The weekly-volume series (oldest→newest) for the co-hero sparkline.
  final List<double> weeklyVolumeSeries;

  @override
  State<ProgressHeroSection> createState() => _ProgressHeroSectionState();
}

class _ProgressHeroSectionState extends State<ProgressHeroSection> {
  /// True once every week in the window has met the goal — the earned moment
  /// that triggers a one-shot celebration (haptic + a brief ring pop).
  bool get _goalFullyMet =>
      widget.goalWindowWeeks > 0 &&
      widget.goalHitWeeks >= widget.goalWindowWeeks;

  /// Guards the celebration so the haptic fires once per met-transition, not on
  /// every rebuild (e.g. scroll / refresh) while it stays met.
  bool _celebrated = false;

  @override
  void initState() {
    super.initState();
    // If the screen opens already fully met, treat it as ack'd — we only
    // celebrate the moment it *becomes* met during a session.
    _celebrated = _goalFullyMet;
  }

  @override
  void didUpdateWidget(covariant ProgressHeroSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final met = _goalFullyMet;
    if (met && !_celebrated) {
      _celebrated = true;
      // Fire-and-forget; preference-aware and a no-op on web.
      Haptics.celebrate();
    } else if (!met) {
      _celebrated = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final goalHitWeeks = widget.goalHitWeeks;
    final goalWindowWeeks = widget.goalWindowWeeks;
    final weeklyGoal = widget.weeklyGoal;
    final lastWeeksVolume = widget.lastWeeksVolume;
    final prevWeeksVolume = widget.prevWeeksVolume;
    final weeksCount = widget.weeksCount;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final ringProgress = goalWindowWeeks > 0
        ? (goalHitWeeks / goalWindowWeeks).clamp(0.0, 1.0)
        : 0.0;

    final diff = lastWeeksVolume - prevWeeksVolume;
    final isUp = diff >= 0;
    // Kind by default: a volume dip is neutral, never error red. Up = green
    // success, down = amber warning (the over-budget hue).
    final trendColor = isUp
        ? AppColors.accentEmeraldGreen
        : AppColors.accentWarningAmber;
    final trendPercent = prevWeeksVolume > 0
        ? ((diff / prevWeeksVolume) * 100).abs()
        : 0.0;
    // No lifting volume in the trailing window yet — a bare "0 kg" reads dead, so
    // we show an inviting prompt instead of a discouraging zero.
    final bool hasVolume = lastWeeksVolume > 0;
    final volumeLabel = hasVolume
        ? '${NumberFormatUtil.formatDouble(lastWeeksVolume, decimalDigits: 0)} kg'
        : 'Add your first';

    // True first-run hero: no goal weeks hit AND no recent lifting volume. We
    // gate on volume too so an active user who simply hasn't hit a 3x/week goal
    // still sees the honest "0 of 8 weeks" metric — only a genuinely blank start
    // swaps the bare "0" for an inviting glyph + encouraging line.
    final bool isFreshWindow = goalHitWeeks == 0 && !hasVolume;

    final heroNumberStyle = TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: 44,
      height: 1.0,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.2,
      color: colorScheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final goalLine = isFreshWindow
        ? 'Hit $weeklyGoal workouts this week to light up your first ring.'
        : 'Goal: $weeklyGoal workouts a week.';

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.fromLTRB(18, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _celebrateRing(
                reduceMotion: reduceMotion,
                child: AppProgressRing(
                  progress: ringProgress,
                  size: 124,
                  strokeWidth: 12,
                  color: colorScheme.primary,
                  // Fresh window: a soft blue ghost track invites the first fill
                  // instead of reading as a stark empty/gray ring.
                  trackColor: isFreshWindow
                      ? colorScheme.primary.withValues(alpha: 0.18)
                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
                  semanticsLabel: isFreshWindow
                      ? 'No goal weeks yet. Log your first workout to begin.'
                      : 'Weekly goal hit $goalHitWeeks of $goalWindowWeeks weeks',
                  child: isFreshWindow
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Inviting glyph in place of a bare "0" — the ring is
                            // a goal to fill, not a verdict.
                            HustlIcon(
                              asset: 'assets/icons/ic_target.svg',
                              size: 34,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Start here',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Focal hero numeral — counts up as data loads.
                            AnimatedMetricText(
                              value: goalHitWeeks.toDouble(),
                              style: heroNumberStyle,
                              semanticsLabel:
                                  'Weekly goal hit $goalHitWeeks of $goalWindowWeeks weeks',
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'of $goalWindowWeeks weeks',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isFreshWindow ? 'Weekly goal' : 'Weekly goal hit',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(goalLine, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          Divider(
            height: 1,
            thickness: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppSpacing.x1 + 4),
          // Volume trend promoted from a quiet ▲% row to a co-hero stat: a big
          // value + a kind direction cue + a sparkline of the weekly series.
          TrendStatCard(
            label: 'Volume · last $weeksCount wk',
            value: volumeLabel,
            valueColor: hasVolume ? null : colorScheme.primary,
            cue: prevWeeksVolume > 0
                ? '${isUp ? 'Up' : 'Down'} ${trendPercent.round()}%'
                : null,
            cueColor: trendColor,
            series: widget.weeklyVolumeSeries,
          ),
        ],
      ),
    );
  }

  /// Wraps the goal ring in a brief, tasteful scale/opacity pop when the goal
  /// is fully met. Reduce-motion safe: returns the child untouched when
  /// animations are disabled or the goal is not (yet) met.
  Widget _celebrateRing({required bool reduceMotion, required Widget child}) {
    if (reduceMotion || !_goalFullyMet) return child;
    return child
        .animate()
        .scaleXY(
          begin: 0.94,
          end: 1.0,
          duration: AppMotion.emphasized,
          curve: AppMotion.celebrateCurve,
        )
        .fadeIn(duration: AppMotion.fast);
  }
}
