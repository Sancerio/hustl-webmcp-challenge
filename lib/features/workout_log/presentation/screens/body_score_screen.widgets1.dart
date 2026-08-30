part of 'body_score_screen.dart';

/// Wave I — data as hero: the body score as a ring with the numeral big in its
/// centre. The ring fills to `score / 100` in the status hue; the status read
/// ("Great balance" / "Good balance" / "Room to balance") sits beside it.
class _BalanceHero extends StatelessWidget {
  const _BalanceHero({
    required this.score,
    required this.statusColor,
    required this.statusLabel,
    this.caption = 'Balance score',
  });

  final double score;
  final Color statusColor;
  final String statusLabel;
  // The label above the status chip and the ring semantics - "Balance score"
  // normally, "Evenness" when the card is demoted into "Trends & detail".
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final progress = (score / 100).clamp(0.0, 1.0);

    final heroNumberStyle = TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: 44,
      height: 1.0,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.2,
      color: colors.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AppProgressRing(
          progress: progress,
          size: 132,
          strokeWidth: 13,
          color: statusColor,
          trackColor: colors.outlineVariant.withValues(alpha: 0.5),
          semanticsLabel: caption,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Focal hero numeral — counts up as the score resolves.
              AnimatedMetricText(
                value: score,
                style: heroNumberStyle,
                semanticsLabel: caption,
              ),
              const SizedBox(height: 2),
              Text(
                '/ 100',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
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
                caption,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              AppChip(
                variant: AppChipVariant.status,
                color: statusColor,
                label: statusLabel,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PeriodPillSelector extends StatelessWidget {
  const _PeriodPillSelector({
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
      tooltip: 'Change period',
      onSelected: onSelected,
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

class _RegionSummary {
  const _RegionSummary({
    required this.region,
    Map<String, _RegionStimulusSnapshot>? stimuliByStrategy,
    List<_ExerciseContribution>? exercises,
    List<_MuscleGroupBreakdown>? breakdown,
    this.lastTrained,
  }) : stimuliByStrategy = stimuliByStrategy ?? const {},
       exercises = exercises ?? const [],
       breakdown = breakdown ?? const [];

  static const Object _noUpdate = Object();

  final DisplayRegion region;
  final Map<String, _RegionStimulusSnapshot> stimuliByStrategy;
  final List<_ExerciseContribution> exercises;
  final List<_MuscleGroupBreakdown> breakdown;
  final DateTime? lastTrained;

  _RegionStimulusSnapshot? stimulusFor(String strategyId) =>
      stimuliByStrategy[strategyId];

  bool get hasWorkouts =>
      stimuliByStrategy.values.any((snapshot) => snapshot.windowVolume > 0);

  bool get hasOtherCallout =>
      region == DisplayRegion.other && exercises.isNotEmpty;

  _RegionSummary addStimulus(
    String strategyId,
    _RegionStimulusSnapshot snapshot,
  ) {
    final updated = Map<String, _RegionStimulusSnapshot>.from(stimuliByStrategy)
      ..[strategyId] = snapshot;
    return copyWith(stimuliByStrategy: updated);
  }

  _RegionSummary copyWith({
    Map<String, _RegionStimulusSnapshot>? stimuliByStrategy,
    List<_ExerciseContribution>? exercises,
    List<_MuscleGroupBreakdown>? breakdown,
    Object? lastTrained = _noUpdate,
  }) {
    return _RegionSummary(
      region: region,
      stimuliByStrategy: stimuliByStrategy ?? this.stimuliByStrategy,
      exercises: exercises ?? this.exercises,
      breakdown: breakdown ?? this.breakdown,
      lastTrained: identical(lastTrained, _noUpdate)
          ? this.lastTrained
          : lastTrained as DateTime?,
    );
  }
}

class _RegionStimulusSnapshot {
  const _RegionStimulusSnapshot({
    required this.score,
    required this.share,
    required this.ewma7,
    required this.ewma28,
    required this.recommendedSets,
    required this.lastStimulus,
    required this.trend,
    required this.weeklyTarget,
    required this.isDominant,
    required this.isUnderTarget,
    required this.windowVolume,
  });

  final double score;
  final double share;
  final double ewma7;
  final double ewma28;
  final double recommendedSets;
  final DateTime? lastStimulus;
  final double trend;
  final double weeklyTarget;
  final bool isDominant;
  final bool isUnderTarget;
  final double windowVolume;
}

class _ExerciseContribution {
  const _ExerciseContribution({required this.name, required this.volume});

  final String name;
  final double volume;
}
