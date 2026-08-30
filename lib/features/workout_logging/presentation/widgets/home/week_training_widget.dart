import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';

import 'home_week_stats.dart';
import 'kg_format.dart';

const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// The week training mini-chart: one vertical bar per day (Mon–Sun). It reads
/// at a glance as "trained vs rest" — a TRAINED day fills the whole bar in the
/// primary accent, a REST day shows only a faint track. The current day's
/// letter is emphasised. Binary, one colour — instantly legible (no cryptic
/// partial heights to decode).
class WeekTrainingWidget extends StatelessWidget {
  const WeekTrainingWidget({
    super.key,
    required this.stats,
    this.showSummary = true,
    this.firstRun = false,
    this.emptyHint = 'Log your first workout',
  });

  final HomeWeekStats stats;

  /// When false, the right-hand week-volume summary column is omitted (the
  /// hero card shows the big volume number instead).
  final bool showSummary;

  /// Empty week: the bars are calm ghost tracks and a quiet [emptyHint]
  /// replaces the dead empty row, so the week strip reads as an invitation
  /// rather than seven stark grey zeros.
  final bool firstRun;

  /// The encouraging line shown under the ghost bars when [firstRun] is true.
  /// Defaults to the brand-new-user invitation; a returning user whose current
  /// week is simply empty gets a "fresh week" variant instead of being told
  /// this is their first workout.
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final trainedDays = stats.days
        .where((d) => d.volume > 0 || d.sets > 0)
        .length;

    final semantics = firstRun
        ? 'No workouts logged this week yet.'
        : trainedDays == 1
        ? 'This week: trained on 1 of 7 days.'
        : 'This week: trained on $trainedDays of 7 days.';

    final bars = Semantics(
      container: true,
      label: semantics,
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < stats.days.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: _DayBar(
                  letter: _dayLetters[i],
                  day: stats.days[i],
                  firstRun: firstRun,
                ),
              ),
            ],
            if (showSummary) ...[
              const SizedBox(width: AppSpacing.x2),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatCompactKg(stats.weekVolume),
                    style: AppTextStyles.metricEmphasis(context),
                  ),
                  Text(
                    'kg this week',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    if (!firstRun) return bars;

    // First-run: keep the calm week strip but anchor it with a single
    // encouraging hint instead of leaving seven empty tracks reading as zeros.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        bars,
        const SizedBox(height: AppSpacing.x1 + 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bolt_rounded, size: 15, color: colors.primary),
            const SizedBox(width: 5),
            // Flexible so a longer hint (e.g. the returning-user variant) wraps
            // instead of overflowing the card on narrow widths.
            Flexible(
              child: Text(
                emptyHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A single day: a vertical bar over a faint track, with the day letter
/// beneath. A trained day (any volume or sets logged) fills the WHOLE bar in
/// the primary accent; a rest day shows only the track. Binary — trained vs
/// rest — never a volume-proportional height.
class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.letter,
    required this.day,
    this.firstRun = false,
  });

  final String letter;
  final HomeDayTraining day;

  /// First-run: the track reads as a calm ghost (a touch fainter) so the empty
  /// week never feels like a stark grey zero waiting to be judged.
  final bool firstRun;

  static const double _trackHeight = 46;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    // Binary fill: a trained day fills the whole bar, a rest day shows only the
    // track. No volume-proportional height.
    final trained = day.volume > 0 || day.sets > 0;
    final trackAlpha = firstRun ? 0.12 : 0.18;
    final double fill = trained ? 1.0 : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _trackHeight,
          child: Center(
            child: SizedBox(
              width: 11,
              child: Stack(
                children: [
                  // Track.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.onSurfaceVariant.withValues(
                          alpha: trackAlpha,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  // Trained-day fill (full bar).
                  if (trained)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(end: fill),
                        duration: reduceMotion
                            ? Duration.zero
                            : AppMotion.emphasized,
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) => FractionallySizedBox(
                          heightFactor: value,
                          widthFactor: 1.0,
                          alignment: Alignment.bottomCenter,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          letter,
          style: theme.textTheme.labelSmall?.copyWith(
            color: day.isToday ? colors.onSurface : colors.onSurfaceVariant,
            fontWeight: day.isToday ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
