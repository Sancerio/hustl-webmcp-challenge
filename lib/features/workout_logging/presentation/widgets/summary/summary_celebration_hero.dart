import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';
import 'package:hustl_app/core/widgets/animated_metric_text.dart';
import 'package:hustl_app/core/widgets/app_progress_ring.dart';
import 'package:hustl_app/core/widgets/staggered_entrance.dart';

/// The completion summary hero (Wave I — Apple Fitness+ x Whoop, "data as
/// hero"): a full blue completion ring with the session's total volume BIG in
/// its centre, paired with the exercises / PRs counts as a grouped stat card —
/// all inside one elevated surface. The celebration is the calm count-ups, the
/// solid ring entrance, and the caller's celebrate haptic.
class SummaryCelebrationHero extends StatelessWidget {
  const SummaryCelebrationHero({
    super.key,
    required this.title,
    required this.subtitle,
    required this.exercises,
    required this.prs,
    required this.metricValue,
    this.metricUnitLabel = 'kg volume',
    this.metricSemanticsLabel = 'Total volume',
    this.metricFractionDigits = 0,
    this.heroSessionId,
  });

  final String title;
  final String subtitle;
  final int exercises;
  final int prs;

  /// The big number in the ring. Weight sessions centre on kg volume; cardio
  /// and duration-only sessions centre on distance or time instead, so the
  /// hero never celebrates a meaningless "0 kg volume".
  final double metricValue;
  final String metricUnitLabel;
  final String metricSemanticsLabel;
  final int metricFractionDigits;

  /// When provided, the title text and stats are wrapped in [Hero] widgets
  /// whose tags match those produced by `HistorySessionCard` for this session,
  /// giving the history-card → summary fly transition.
  final String? heroSessionId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // The Material wrapper prevents Hero text from inheriting the wrong
    // DefaultTextStyle during the flight.
    Widget heroWrap(String tag, Widget child) => heroSessionId != null
        ? Hero(
            tag: '$tag$heroSessionId',
            child: Material(type: MaterialType.transparency, child: child),
          )
        : child;

    final heroNumberStyle = TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: 34,
      height: 1.0,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.0,
      color: colors.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final titleWidget = heroWrap(
      'history_session_title_',
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(title, style: theme.textTheme.titleLarge),
      ),
    );

    final ring = AppProgressRing(
      progress: 1,
      size: 124,
      strokeWidth: 12,
      color: colors.primary,
      trackColor: colors.outlineVariant.withValues(alpha: 0.5),
      semanticsLabel: metricSemanticsLabel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedMetricText(
            value: metricValue,
            grouped: true,
            fractionDigits: metricFractionDigits,
            style: heroNumberStyle,
            semanticsLabel: metricSemanticsLabel,
          ),
          const SizedBox(height: 2),
          Text(
            metricUnitLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    final statsWidget = heroWrap(
      'history_session_stats_',
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatRow(label: 'Exercises', value: exercises.toDouble()),
          const Divider(height: 1),
          _StatRow(label: 'PRs', value: prs.toDouble()),
        ],
      ),
    );

    return StaggeredEntrance(
      animationKey: 'workout-summary-${heroSessionId ?? 'session'}',
      children: [
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(22),
          ),
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleWidget,
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.x3),
              Center(child: ring),
              const SizedBox(height: AppSpacing.x3),
              statsWidget,
            ],
          ),
        ),
      ],
    );
  }
}

/// An aligned 15px stat row: label left, tabular count-up value right.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          _AnimatedStatValue(value: value),
        ],
      ),
    );
  }
}

/// A small tabular count-up wrapper kept local so the hero owns its number
/// motion without re-importing the metric widget's larger surface.
class _AnimatedStatValue extends StatelessWidget {
  const _AnimatedStatValue({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final style = theme.textTheme.labelLarge;

    return Semantics(
      value: value.toStringAsFixed(0),
      liveRegion: !disableAnimations,
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: value),
          duration: disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => Text(v.toStringAsFixed(0), style: style),
        ),
      ),
    );
  }
}
