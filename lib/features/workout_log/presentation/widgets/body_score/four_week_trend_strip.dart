import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';

import '../../../domain/models/muscle_group.dart';

/// One ISO week's DEDUPED physical-set count per display region, plus a flag
/// marking the in-progress (rightmost) week. Built by the screen from
/// `summarize(weekRange).physicalSetsByDisplayRegion` per week - the SAME
/// deduped integer basis the current-week headline bars use, so the rightmost
/// (in-progress) bar matches the headline exactly and every week reads on the
/// same basis (a set training two muscles in one display region counts ONCE,
/// not the raw `baseSet x groupRatio` figure that double-counts compounds).
class WeeklyRegionPoint {
  const WeeklyRegionPoint({
    required this.label,
    required this.setsByRegion,
    required this.targetsByRegion,
    this.inProgress = false,
  });

  /// Short axis label for the week (e.g. "May 5").
  final String label;

  /// DEDUPED physical sets logged in this ISO week, per display region (the
  /// integer count from `physicalSetsByDisplayRegion`, carried as a double for
  /// the fill math). Consistent with the headline's deduped basis.
  final Map<DisplayRegion, double> setsByRegion;

  /// Weekly target per display region (the goal line each bar fills toward).
  final Map<DisplayRegion, double> targetsByRegion;

  /// Whether this is the current, still-accumulating week.
  final bool inProgress;
}

/// Phase 3 (training-balance revamp) — a compact "Last 4 weeks" per-region
/// weekly bar strip. One bar per ISO week per display region; the rightmost
/// week is this week, in progress. Lives inside the demoted "Trends & detail"
/// section, below the headline IA.
class FourWeekTrendStrip extends StatelessWidget {
  const FourWeekTrendStrip({super.key, required this.weeks});

  /// Oldest → newest; the last entry is the in-progress current week.
  final List<WeeklyRegionPoint> weeks;

  static const List<DisplayRegion> _regions = [
    DisplayRegion.chest,
    DisplayRegion.back,
    DisplayRegion.shoulders,
    DisplayRegion.arms,
    DisplayRegion.core,
    DisplayRegion.legs,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (weeks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Last 4 weeks',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Rightmost is this week, in progress.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        for (var i = 0; i < _regions.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.x2),
          _RegionTrendRow(region: _regions[i], weeks: weeks),
        ],
      ],
    );
  }
}

class _RegionTrendRow extends StatelessWidget {
  const _RegionTrendRow({required this.region, required this.weeks});

  final DisplayRegion region;
  final List<WeeklyRegionPoint> weeks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // Scale every week's bar against the region's weekly target (or the max set
    // count if that is higher), so an on-goal week reaches the top.
    double maxScale = 0.0;
    for (final week in weeks) {
      final sets = week.setsByRegion[region] ?? 0.0;
      final target = week.targetsByRegion[region] ?? 0.0;
      if (sets > maxScale) maxScale = sets;
      if (target > maxScale) maxScale = target;
    }
    if (maxScale <= 0) maxScale = 1.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            region.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.x1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final week in weeks)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _WeekBar(
                      region: region,
                      week: week,
                      maxScale: maxScale,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.region,
    required this.week,
    required this.maxScale,
  });

  final DisplayRegion region;
  final WeeklyRegionPoint week;
  final double maxScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sets = week.setsByRegion[region] ?? 0.0;
    final target = week.targetsByRegion[region] ?? 0.0;
    final fraction = (sets / maxScale).clamp(0.0, 1.0);
    // [sets] is the DEDUPED physical-set count (see [WeeklyRegionPoint]), so the
    // met-state matches the current-week headline's deduped basis exactly - the
    // strip can never read a compound-inflated "met" while the headline reads
    // "under". Compare on the rounded integers the tooltip also shows.
    final met = target > 0 && sets.round() >= target.round();

    // Hit-goal weeks read emerald; under-goal weeks read in the muted accent.
    // The in-progress week is rendered hollow (outlined) to signal it is still
    // accumulating.
    final Color barColor = met
        ? colors.tertiary
        : AppColors.accentElectricBlue.withValues(alpha: 0.55);

    const trackHeight = 56.0;
    return Tooltip(
      message:
          '${week.label}: ${sets.round()} / ${target.round()} sets'
          '${week.inProgress ? ' (in progress)' : ''}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: trackHeight,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: fraction <= 0 ? 0.02 : fraction,
                child: Container(
                  decoration: BoxDecoration(
                    color: week.inProgress
                        ? barColor.withValues(alpha: 0.25)
                        : barColor,
                    border: week.inProgress
                        ? Border.all(color: barColor, width: 1.5)
                        : null,
                    borderRadius: AppRadius.controlRadius,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            week.label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}
