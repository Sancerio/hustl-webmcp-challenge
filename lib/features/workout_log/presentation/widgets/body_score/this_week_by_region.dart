import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';
import 'package:hustl_app/core/services/haptics.dart';

import '../../../domain/models/muscle_group.dart';
import '../../../domain/services/body_score_coach.dart';
import '../../../domain/services/body_score_service.dart' show RegionVolumeBand;

/// Phase 2 (training-balance revamp) — the "This week, by region" headline IA.
///
/// This is the LEAD of the Training-balance surface for the in-progress current
/// week. It answers "am I balanced?" + "what do I do?" BEFORE any chart: a live
/// header strip, a status line + on/under-goal pip row, six sorted fill-to-goal
/// region bars, a "Do next" list, and a "How are these counted?" explainer.
///
/// Every figure is the SAME rounded RAW current-week sets-vs-goal number the
/// Phase 1 cue uses ([BodyScoreCoach.currentWeekByDisplayRegion] /
/// [BodyScoreCoach.currentWeekCue]) — never the paced (vol/days)*7 score.
class ThisWeekByRegion extends StatelessWidget {
  const ThisWeekByRegion({
    super.key,
    required this.dayOfWeek,
    required this.regions,
    required this.sessionCount,
    this.onTapRegion,
    this.onDoNext,
  });

  /// Days elapsed in the current week, inclusive of today (1-7).
  final int dayOfWeek;

  /// Per-display-region raw sets-this-week vs the weekly goal, already filtered
  /// to targeted, non-Other regions. Rendered in the order supplied - the
  /// caller sorts furthest-behind first.
  final List<CurrentWeekRegionSummary> regions;

  /// Completed sessions logged so far this week (drives the early-week variant).
  final int sessionCount;

  /// Tap a region bar -> drill into that region's workouts.
  final ValueChanged<DisplayRegion>? onTapRegion;

  /// Tap a "Do next" row -> act on that region (plan / start / drill-down).
  final ValueChanged<DisplayRegion>? onDoNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderStrip(dayOfWeek: dayOfWeek),
        const SizedBox(height: AppSpacing.x2),
        WeekStatusLine(
          regions: regions,
          dayOfWeek: dayOfWeek,
          sessionCount: sessionCount,
        ),
        const SizedBox(height: AppSpacing.x3),
        for (var i = 0; i < regions.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.x2 + 2),
          RegionGoalBar(
            key: ValueKey<DisplayRegion>(regions[i].region),
            summary: regions[i],
            dayOfWeek: dayOfWeek,
            onTap: onTapRegion == null
                ? null
                : () => onTapRegion!(regions[i].region),
          ),
        ],
        const SizedBox(height: AppSpacing.x3),
        DoNextList(regions: regions, onTap: onDoNext),
        const SizedBox(height: AppSpacing.x2),
        const CountingExplainer(),
      ],
    );
  }
}

/// Live header strip: "This week so far - day N of 7" - reads as in-progress,
/// not a closed date range.
class _HeaderStrip extends StatelessWidget {
  const _HeaderStrip({required this.dayOfWeek});

  final int dayOfWeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          Icons.calendar_today_outlined,
          size: 15,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          'This week so far · day $dayOfWeek of ${DateTime.daysPerWeek}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// The LEAD verdict that replaces the 0-100 balance ring: a one-line status
/// followed by a 6-pip row (one pip per region, filled when on/over goal).
///
/// Early in the week (few sessions logged) it switches to a non-judgemental
/// "still early" variant so a thin Monday is not scolded.
class WeekStatusLine extends StatelessWidget {
  const WeekStatusLine({
    super.key,
    required this.regions,
    required this.dayOfWeek,
    required this.sessionCount,
  });

  final List<CurrentWeekRegionSummary> regions;
  final int dayOfWeek;
  final int sessionCount;

  /// Early-week guard: the first two days, or before two sessions are logged,
  /// read as "still early" rather than "you're behind".
  bool get _isEarlyWeek => dayOfWeek <= 2 || sessionCount < 2;

  int get _metCount => regions.where((r) => r.isMet).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final total = regions.length;
    final met = _metCount;

    final String headline;
    final String? sub;
    final Color accent;
    final IconData icon;

    if (total == 0) {
      headline = 'No weekly goals yet';
      sub = null;
      accent = colors.onSurfaceVariant;
      icon = Icons.info_outline;
    } else if (_isEarlyWeek && met < total) {
      // Still early - frame by activity, not by a deficit.
      final sessions = sessionCount;
      headline = 'Still early this week';
      sub = sessions == 0
          ? 'No sessions logged yet - plenty of week left.'
          : '$sessions ${sessions == 1 ? 'session' : 'sessions'} logged so far.';
      accent = colors.primary;
      icon = Icons.bolt_outlined;
    } else if (met >= total) {
      headline = "You're balanced - every region hit its weekly goal";
      sub = 'Nice work. Keep the loads progressing.';
      accent = colors.tertiary;
      icon = Icons.check_circle_outline;
    } else {
      // The gap region is the furthest-behind targeted region.
      final gap = regions
          .where((r) => !r.isMet)
          .fold<CurrentWeekRegionSummary?>(
            null,
            (lowest, r) => lowest == null || r.displayPercent < lowest.displayPercent
                ? r
                : lowest,
          );
      headline =
          "You're on track - $met of $total regions hit their weekly goal";
      sub = gap == null ? null : '${gap.region.label} is your gap this week.';
      accent = met >= (total / 2).ceil()
          ? colors.primary
          : AppColors.accentWarningAmber;
      icon = Icons.insights_outlined;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (total > 0) ...[
          const SizedBox(height: AppSpacing.x2),
          _PipRow(regions: regions),
        ],
      ],
    );
  }
}

/// A row of pips, one per region - filled emerald when on/over goal, an empty
/// outlined dot when under. A compact, glanceable "N of M hit goal".
class _PipRow extends StatelessWidget {
  const _PipRow({required this.regions});

  final List<CurrentWeekRegionSummary> regions;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label:
          '${regions.where((r) => r.isMet).length} of ${regions.length} '
          'regions hit their weekly goal',
      child: Row(
        children: [
          for (final region in regions)
            Tooltip(
              message:
                  '${region.region.label}: '
                  '${region.displaySets} / ${region.weeklyTarget.round()} sets'
                  '${region.isMet ? ' - done' : ''}',
              child: Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: region.isMet ? colors.tertiary : Colors.transparent,
                  border: region.isMet
                      ? null
                      : Border.all(color: colors.outlineVariant, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A single fill-to-goal region bar: "Core 10 / 10 sets" with a horizontal fill
/// in one of three color zones and, when the domain supplies a
/// [RegionVolumeBand], subtle min / target / max markers (target at 100%, with
/// faint min and max ticks bounding the healthy window). Tap -> the region
/// drill-down.
///
/// Phase 4 (training-balance revamp): the displayed figure is the TRUE integer
/// physical-set count ([CurrentWeekRegionSummary.displaySets]), and the three
/// colour zones are driven by the band (below min -> amber/under, inside the
/// min..max window -> emerald/on-target, above max -> blue/plenty). When no band
/// is present it degrades gracefully to a single 100% target tick and the
/// legacy percent-of-target zones. The fill animates to its new width via
/// [AppMotion] when the value changes (accumulation micro-animation).
class RegionGoalBar extends StatelessWidget {
  const RegionGoalBar({
    super.key,
    required this.summary,
    required this.dayOfWeek,
    this.onTap,
  });

  final CurrentWeekRegionSummary summary;
  final int dayOfWeek;
  final VoidCallback? onTap;

  /// The three fill zones, keyed off the SAME on-target predicate
  /// ([CurrentWeekRegionSummary.isMet]) the pip, the headline and the do-next
  /// use, so the bar colour can never disagree with them (e.g. read green while
  /// the pip is empty and the do-next still says "add sets"):
  ///   under the weekly target ([isMet] == false) -> amber (building)
  ///   met, up to the band max                     -> emerald (on target)
  ///   above the band max                          -> blue/accent (plenty)
  /// The band's min/max still render as subtle MARKERS on the track, but they no
  /// longer flip the colour - an in-band-but-under-target region (e.g. 7 sets in
  /// a 6..14 band with a 10 target) reads amber/building, matching its empty pip
  /// and its "Add about 3 sets" do-next row. Without a band the "plenty" ceiling
  /// falls back to the legacy 115%-of-target threshold.
  Color _zoneColor(ColorScheme colors) {
    if (!summary.isMet) return AppColors.accentWarningAmber; // building
    final band = summary.band;
    final bool plenty = band != null && band.max > band.min
        ? band.isAbove(summary.displaySets.toDouble())
        : summary.displayPercent > 115.0;
    if (plenty) return AppColors.accentElectricBlue; // past the band - plenty
    return colors.tertiary; // emerald - on target
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final zone = _zoneColor(colors);
    final done = summary.displaySets;
    final target = summary.weeklyTarget.round();
    final band = (summary.band != null && summary.band!.max > summary.band!.min)
        ? summary.band
        : null;

    // The continuous fill rides the displayed integer count so the bar and the
    // "N / N sets" figure agree exactly.
    final double sets = done.toDouble();

    // The bar's max scale. With a band, scale to the band ceiling (with a little
    // headroom so the max marker is not pinned at the edge); an over-max fill
    // pushes the scale out so it reads as "past the max", not clamped. Without a
    // band, keep the legacy target-with-headroom scale.
    final double scaleMax;
    if (band != null) {
      scaleMax = sets > band.max ? sets * 1.05 : band.max * 1.05;
    } else {
      scaleMax = target <= 0
          ? 1.0
          : (sets > summary.weeklyTarget ? sets * 1.05 : summary.weeklyTarget);
    }
    final double fillFraction = scaleMax <= 0
        ? 0.0
        : (sets / scaleMax).clamp(0.0, 1.0);
    final double goalFraction = scaleMax <= 0
        ? 1.0
        : (summary.weeklyTarget / scaleMax).clamp(0.0, 1.0);
    final double? minFraction = band == null || scaleMax <= 0
        ? null
        : (band.min / scaleMax).clamp(0.0, 1.0);
    final double? maxFraction = band == null || scaleMax <= 0
        ? null
        : (band.max / scaleMax).clamp(0.0, 1.0);

    // Faint pace marker: where an on-track lifter would be by today
    // (target * daysElapsed / 7). Gated by an early-week guard so a day-1 bar is
    // not cluttered with a near-zero marker.
    final bool showPace = dayOfWeek >= 2 && dayOfWeek < DateTime.daysPerWeek;
    final double paceSets =
        summary.weeklyTarget * dayOfWeek / DateTime.daysPerWeek;
    final double paceFraction = scaleMax <= 0
        ? 0.0
        : (paceSets / scaleMax).clamp(0.0, 1.0);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                summary.region.label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$done / $target sets',
              style: theme.textTheme.labelLarge?.copyWith(
                color: summary.isMet ? colors.tertiary : colors.onSurface,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (summary.isMet) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle, size: 16, color: colors.tertiary),
            ],
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            const barHeight = 12.0;
            return SizedBox(
              height: barHeight,
              child: Stack(
                children: [
                  // Track.
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: AppRadius.pillRadius,
                    ),
                  ),
                  // Fill - animates to the new width when the value changes.
                  ClipRRect(
                    borderRadius: AppRadius.pillRadius,
                    child: AnimatedFractionallySizedBox(
                      duration: AppMotion.emphasized,
                      curve: AppMotion.emphasizedCurve,
                      alignment: Alignment.centerLeft,
                      widthFactor: fillFraction,
                      child: Container(color: zone),
                    ),
                  ),
                  // Subtle min / max band markers (only when a band is present).
                  if (minFraction != null)
                    Positioned(
                      left: (minFraction * width).clamp(0.0, width - 1.5),
                      top: 2,
                      bottom: 2,
                      child: Container(
                        width: 1.5,
                        color: colors.onSurfaceVariant.withValues(alpha: 0.35),
                      ),
                    ),
                  if (maxFraction != null)
                    Positioned(
                      left: (maxFraction * width).clamp(0.0, width - 1.5),
                      top: 2,
                      bottom: 2,
                      child: Container(
                        width: 1.5,
                        color: colors.onSurfaceVariant.withValues(alpha: 0.35),
                      ),
                    ),
                  // Faint pace marker (where on-track would be by today).
                  if (showPace)
                    Positioned(
                      left: (paceFraction * width).clamp(0.0, width - 1.5),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 1.5,
                        color: colors.onSurfaceVariant.withValues(alpha: 0.45),
                      ),
                    ),
                  // 100% target tick (always shown - the headline goal).
                  Positioned(
                    left: (goalFraction * width).clamp(0.0, width - 2.0),
                    top: -1,
                    bottom: -1,
                    child: Container(
                      width: 2.0,
                      decoration: BoxDecoration(
                        color: colors.onSurface,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: () {
        Haptics.selection();
        onTap!();
      },
      borderRadius: AppRadius.controlRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: content,
      ),
    );
  }
}

/// The "Do next" list - up to three tappable "Add about N <region> sets" rows,
/// built from the SAME raw gap the bars show (furthest-behind first). When every
/// region has met its goal it collapses to a single "all clear" row.
class DoNextList extends StatelessWidget {
  const DoNextList({super.key, required this.regions, this.onTap});

  final List<CurrentWeekRegionSummary> regions;
  final ValueChanged<DisplayRegion>? onTap;

  static const int _maxRows = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // Order by the DISPLAYED percent (so the largest DISPLAYED gap surfaces
    // first), matching the bar order the screen sorts and the gaps these rows
    // cite - a 5 / 10 primary ranks ahead of a 9 / 10 secondary-heavy region.
    final under = regions.where((r) => !r.isMet).toList()
      ..sort((a, b) => a.displayPercent.compareTo(b.displayPercent));
    final rows = under.take(_maxRows).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Do next',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        if (rows.isEmpty)
          _DoNextRow(
            icon: Icons.check_circle_outline,
            iconColor: colors.tertiary,
            label: "You're all caught up this week",
            onTap: null,
          )
        else
          for (final region in rows)
            _DoNextRow(
              icon: Icons.add_circle_outline,
              iconColor: colors.primary,
              label: _addLabel(region),
              onTap: onTap == null ? null : () => onTap!(region.region),
            ),
      ],
    );
  }

  static String _addLabel(CurrentWeekRegionSummary region) {
    final add = region.displayGap.clamp(1, 999);
    final name = region.region.label.toLowerCase();
    return 'Add about $add $name ${add == 1 ? 'set' : 'sets'}';
  }
}

class _DoNextRow extends StatelessWidget {
  const _DoNextRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          if (onTap != null)
            Icon(Icons.chevron_right, size: 20, color: colors.onSurfaceVariant),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: () {
        Haptics.selection();
        onTap!();
      },
      child: row,
    );
  }
}

/// "How are these counted?" - a collapsible explainer of raw sets vs the
/// weighted "≈ hard sets" the rest of the surface uses.
class CountingExplainer extends StatelessWidget {
  const CountingExplainer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.x1),
        title: Text(
          'How are these counted?',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'These are the raw sets you logged this week vs your weekly goal '
              '- one logged set counts as one set. The radar and the evenness '
              'stat below instead use "≈ hard sets": each set is weighted by '
              'how hard it was (rep range and effort), so an all-out set counts '
              'more than an easy one.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
