import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/utils/number_format_util.dart';
import '../../../../core/widgets/app_chip.dart';
import '../../domain/services/body_score_coach.dart';
import '../../domain/services/body_score_service.dart';
import 'body_score_radar.dart';
import '../../domain/utils/time_periods.dart';

class BodyScoreSummaryCard extends StatelessWidget {
  const BodyScoreSummaryCard({
    super.key,
    required this.summary,
    required this.loading,
    this.error,
    this.onOpenDetail,
    this.onRetry,
    this.periodWindow,
    this.onPeriodChanged,
    this.selectedPeriod = BodyScorePeriod.last4FullWeeks,
    this.availablePeriods = BodyScorePeriod.values,
    Map<String, double>? otherRegionBreakdown,
  }) : otherRegionBreakdown = otherRegionBreakdown ?? const {};

  final BodyScoreSummary? summary;
  final bool loading;
  final String? error;
  final VoidCallback? onOpenDetail;
  final VoidCallback? onRetry;
  final Map<String, double> otherRegionBreakdown;
  final BodyScorePeriodWindow? periodWindow;
  final ValueChanged<BodyScorePeriod>? onPeriodChanged;
  final BodyScorePeriod selectedPeriod;
  final List<BodyScorePeriod> availablePeriods;

  @override
  Widget build(BuildContext context) {
    if (loading && summary == null) {
      return _BodyScoreShimmer(cardHeight: _cardHeight(context));
    }

    if (summary == null) {
      return _BodyScoreEmptyState(
        message: error ?? 'Training balance unavailable',
        rangeLabel: periodWindow?.labelWithDate,
        onRetry: onRetry,
      );
    }

    return Stack(
      children: [
        _BodyScoreContent(
          summary: summary!,
          otherRegionBreakdown: otherRegionBreakdown,
          onOpenDetail: onOpenDetail,
          periodWindow: periodWindow,
          onPeriodChanged: onPeriodChanged,
          selectedPeriod: selectedPeriod,
          availablePeriods: availablePeriods,
        ),
        if (loading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }

  double _cardHeight(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) {
      return 190;
    }
    if (width < 500) {
      return 200;
    }
    return 210;
  }
}

class _BodyScoreContent extends StatelessWidget {
  const _BodyScoreContent({
    required this.summary,
    required this.otherRegionBreakdown,
    this.onOpenDetail,
    this.periodWindow,
    this.onPeriodChanged,
    required this.selectedPeriod,
    required this.availablePeriods,
  });

  final BodyScoreSummary summary;
  final Map<String, double> otherRegionBreakdown;
  final VoidCallback? onOpenDetail;
  final BodyScorePeriodWindow? periodWindow;
  final ValueChanged<BodyScorePeriod>? onPeriodChanged;
  final BodyScorePeriod selectedPeriod;
  final List<BodyScorePeriod> availablePeriods;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayAggregates = _aggregateDisplayRegions(summary);
    final coachingCue = BodyScoreCoach.overallCue(summary);
    final otherAggregate = displayAggregates[DisplayRegion.other] ?? 0.0;
    final nonOtherAggregates = displayAggregates.entries
        .where((entry) => entry.key != DisplayRegion.other)
        .toList(growable: false);
    MapEntry<DisplayRegion, double>? dominantEntry = nonOtherAggregates
        .fold<MapEntry<DisplayRegion, double>?>(
          null,
          (previous, entry) => previous == null || entry.value > previous.value
              ? entry
              : previous,
        );
    final hasNonOtherStimulus = nonOtherAggregates.any(
      (entry) => entry.value > 0,
    );
    if (!hasNonOtherStimulus) {
      dominantEntry = otherAggregate > 0
          ? MapEntry<DisplayRegion, double>(DisplayRegion.other, otherAggregate)
          : null;
    }
    final dominantScore = (dominantEntry?.value ?? 0).clamp(0.0, 500.0);
    final balance = summary.balanceScore.clamp(0.0, 100.0).toDouble();
    final activeRegions = summary.mappableRegionCount;
    final totalRegions = summary.totalMappableRegions;
    final windowDays = summary.windowDays <= 0 ? 1 : summary.windowDays;
    final rangeLabel = periodWindow?.period.label ?? 'Selected period';
    final dateLabel =
        periodWindow?.dateLabel ?? formatShortDateRange(summary.window);
    final sessionsLabel =
        '${NumberFormatUtil.formatInt(summary.sessionCount)} sessions';

    final mappableScores =
        displayAggregates.entries
            .where((entry) => entry.key != DisplayRegion.other)
            .toList(growable: false)
          ..sort((a, b) => a.value.compareTo(b.value));
    final lowestEntry = mappableScores.isNotEmpty ? mappableScores.first : null;
    String? helperText;
    if (coachingCue.mode != BodyScoreCoachingMode.maintain) {
      helperText = coachingCue.detail == null
          ? coachingCue.headline
          : '${coachingCue.headline} ${coachingCue.detail}';
    }

    final onTargetCount = DisplayRegion.values
        .where((region) => region != DisplayRegion.other)
        .where((region) => (displayAggregates[region] ?? 0) >= 100)
        .length;

    String? dominantText;
    if (dominantEntry != null) {
      if (dominantEntry.key == DisplayRegion.other) {
        final dominantScoreLabel = NumberFormatUtil.formatDouble(
          dominantScore,
          decimalDigits: 0,
        );
        dominantText =
            'Highest vs goal: ${dominantEntry.key.label} ($dominantScoreLabel%).';
      } else {
        final compareRegion =
            lowestEntry?.key == dominantEntry.key && mappableScores.length > 1
            ? mappableScores[1]
            : lowestEntry;
        final compareLabel = compareRegion?.key.label;
        final compareScore = compareRegion != null
            ? NumberFormatUtil.formatDouble(
                compareRegion.value,
                decimalDigits: 0,
              )
            : null;
        final dominantLabel = dominantEntry.key.label;
        final dominantScoreLabel = NumberFormatUtil.formatDouble(
          dominantScore,
          decimalDigits: 0,
        );
        dominantText = compareLabel != null && compareScore != null
            ? 'Highest vs goal: $dominantLabel ($dominantScoreLabel% vs. '
                  '$compareLabel $compareScore%).'
            : 'Highest vs goal: $dominantLabel ($dominantScoreLabel%).';
      }
    }

    // Wave G §12.1: flat module — surface == canvas, no outline.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onOpenDetail,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Training balance',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            AppChip(
                              variant: AppChipVariant.data,
                              icon: Icons.event,
                              label: rangeLabel,
                              value: dateLabel,
                            ),
                            AppChip(
                              variant: AppChipVariant.data,
                              icon: Icons.timelapse,
                              label:
                                  '${NumberFormatUtil.formatInt(windowDays)} day window',
                              value: sessionsLabel,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Wave E §9: methodology copy demoted to labelSmall so
                        // score, radar and chips visually lead.
                        Text(
                          'Axes show % of weekly goal from the selected period, normalized to a weekly rate.',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (onPeriodChanged != null)
                        _PeriodSelector(
                          selected: selectedPeriod,
                          available: availablePeriods,
                          onSelected: onPeriodChanged!,
                        ),
                      if (onOpenDetail != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: IconButton(
                            tooltip: 'Open training balance',
                            onPressed: onOpenDetail,
                            icon: const Icon(Icons.chevron_right),
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(6),
                              minimumSize: const Size(32, 32),
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                              foregroundColor: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (helperText != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    helperText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (dominantText != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    dominantText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 420;
                  final maxExtent = isCompact
                      ? constraints.maxWidth
                      : constraints.maxWidth * 0.45;
                  final chartSize = maxExtent
                      .clamp(
                        isCompact ? 160.0 : 180.0,
                        isCompact ? 200.0 : 220.0,
                      )
                      .toDouble();

                  final chart = SizedBox(
                    width: chartSize,
                    height: chartSize,
                    child: BodyScoreRadar(
                      scoresByMuscleGroup: summary.regionScores,
                      weeklyTargetsByMuscleGroup: summary.weeklyTargets,
                      weeklyTotals: summary.weeklyEquivalentVolumes,
                    ),
                  );

                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(alignment: Alignment.center, child: chart),
                        const SizedBox(height: 16),
                        _BodyScoreStats(
                          summary: summary,
                          otherRegionBreakdown: otherRegionBreakdown,
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      chart,
                      const SizedBox(width: 20),
                      Expanded(
                        child: _BodyScoreStats(
                          summary: summary,
                          otherRegionBreakdown: otherRegionBreakdown,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppChip(
                    variant: AppChipVariant.data,
                    icon: Icons.auto_graph,
                    label: 'Balance',
                    value:
                        '${NumberFormatUtil.formatDouble(balance, decimalDigits: 0)}/100',
                  ),
                  AppChip(
                    variant: AppChipVariant.data,
                    icon: Icons.verified_outlined,
                    label: 'On-target regions',
                    value: '$onTargetCount/6',
                  ),
                  AppChip(
                    variant: AppChipVariant.data,
                    icon: Icons.fitness_center,
                    label: 'Highest vs goal',
                    value: dominantEntry == null
                        ? '—'
                        : '${dominantEntry.key.label} · ${NumberFormatUtil.formatDouble(dominantScore, decimalDigits: 0)}%',
                  ),
                  AppChip(
                    variant: AppChipVariant.data,
                    icon: Icons.grid_view,
                    label: 'Active muscles',
                    value: '$activeRegions / $totalRegions',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Map<DisplayRegion, double> _aggregateDisplayRegions(
    BodyScoreSummary summary,
  ) {
    final Map<DisplayRegion, double> totals = {
      for (final region in DisplayRegion.values) region: 0.0,
    };
    final Map<DisplayRegion, double> targets = {
      for (final region in DisplayRegion.values) region: 0.0,
    };

    for (final group in MuscleGroup.values) {
      final region = group.displayRegion;
      final double target = summary.weeklyTargets[group] ?? 0.0;
      if (target <= 0) continue;
      final double total = summary.weeklyEquivalentVolumes[group] ?? 0.0;
      totals[region] = (totals[region] ?? 0.0) + total;
      targets[region] = (targets[region] ?? 0.0) + target;
    }

    return {
      for (final region in DisplayRegion.values)
        region: (targets[region] ?? 0.0) > 0.0
            ? (totals[region]! / targets[region]!) * 100.0
            : 0.0,
    };
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.selected,
    required this.available,
    required this.onSelected,
  });

  final BodyScorePeriod selected;
  final List<BodyScorePeriod> available;
  final ValueChanged<BodyScorePeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return PopupMenuButton<BodyScorePeriod>(
      onSelected: onSelected,
      tooltip: 'Change period',
      itemBuilder: (context) => [
        for (final period in available)
          PopupMenuItem(value: period, child: Text(period.label)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected.label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _BodyScoreStats extends StatelessWidget {
  const _BodyScoreStats({
    required this.summary,
    required this.otherRegionBreakdown,
  });

  final BodyScoreSummary summary;
  final Map<String, double> otherRegionBreakdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = summary.mappableRegionShares.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final otherEntries =
        otherRegionBreakdown.entries.where((entry) => entry.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (otherEntries.isNotEmpty) ...[
          _OtherRegionCallout(exercises: otherEntries),
          const SizedBox(height: 12),
        ],
        Text(
          'Region distribution',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Text(
            'No mappable regions yet',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final entry in entries.take(4)) ...[
            _StatRow(
              label: entry.key.label,
              share: entry.value,
              score: summary.regionScores[entry.key] ?? 0,
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.share,
    required this.score,
  });

  final String label;
  final double share;
  final double score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: ValueKey<String>('body_score_stat_$label'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${NumberFormatUtil.formatDouble(score, decimalDigits: 0)}%',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${NumberFormatUtil.formatDouble(share * 100, decimalDigits: 0)}% share of training',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: share.clamp(0, 1),
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.6),
            valueColor: AlwaysStoppedAnimation(
              theme.colorScheme.primary.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }
}

class _OtherRegionCallout extends StatelessWidget {
  const _OtherRegionCallout({required this.exercises});

  final List<MapEntry<String, double>> exercises;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textColor = colorScheme.onSecondaryContainer;
    final displayExercises = exercises.take(6).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: colorScheme.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Exercises mapped to Other',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Update these exercises with a primary muscle to move them into a specific region.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: textColor.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in displayExercises)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${entry.key} · '
                    '${NumberFormatUtil.formatDouble(entry.value, decimalDigits: 1)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BodyScoreShimmer extends StatelessWidget {
  const _BodyScoreShimmer({required this.cardHeight});

  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Shimmer.fromColors(
        baseColor: theme.colorScheme.surfaceContainerHighest,
        highlightColor: theme.colorScheme.surfaceContainerHigh,
        child: Container(
          height: cardHeight,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _BodyScoreEmptyState extends StatelessWidget {
  const _BodyScoreEmptyState({
    required this.message,
    this.rangeLabel,
    this.onRetry,
  });

  final String message;
  final String? rangeLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.self_improvement, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Training balance',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (rangeLabel != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          rangeLabel!,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}
