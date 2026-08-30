part of 'body_score_screen.dart';

class _RegionTile extends StatelessWidget {
  const _RegionTile({
    required this.overallSummary,
    required this.summary,
    required this.primaryStrategy,
    this.isCurrentWeek = false,
    this.onViewWorkouts,
  });

  final BodyScoreSummary? overallSummary;
  final _RegionSummary summary;
  final BodyScoreStrategy primaryStrategy;
  // Phase 1: when the in-progress current week is selected the per-region cue is
  // driven by the RAW raw-vs-target snapshot (sets this week vs the weekly
  // goal), not the paced cueForRegion - so the tile cue and the tile figure
  // read the same number.
  final bool isCurrentWeek;
  final VoidCallback? onViewWorkouts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primarySnapshot = summary.stimulusFor(primaryStrategy.id);

    final DateTime? lastStimulus = primarySnapshot?.lastStimulus;
    final lastTrained = lastStimulus != null
        ? DateFormat('EEE, MMM d').format(lastStimulus.toLocal())
        : 'never';

    // Wave G §12.1: flat region row — no card chrome, hairline dividers
    // between rows are provided by the parent list.
    return Padding(
      key: ValueKey<DisplayRegion>(summary.region),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1 + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.region.label,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Last trained: $lastTrained',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (onViewWorkouts != null)
                TextButton(
                  onPressed: onViewWorkouts,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.x1,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('View workouts'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.x1 + 4),
          Builder(
            builder: (context) {
              if (primarySnapshot == null) {
                return Text(
                  'Not trained in this period yet',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              String formatEs(double value) {
                final isWhole = (value - value.round()).abs() < 0.05;
                return NumberFormatUtil.formatDouble(
                  value,
                  decimalDigits: isWhole ? 0 : 1,
                );
              }

              // Phase 1 (current-week): one rounded display basis drives the
              // chip's value, color/zone AND the cue, so they can never
              // disagree (see [_currentWeekGoalDisplay]). Closed periods keep
              // the paced/raw fractional value + score-based color.
              final _GoalChipDisplay goal = isCurrentWeek
                  ? _currentWeekGoalDisplay(
                      done: primarySnapshot.ewma7,
                      target: primarySnapshot.weeklyTarget,
                    )
                  : _GoalChipDisplay(
                      value:
                          '${formatEs(primarySnapshot.ewma7)} / '
                          '${formatEs(primarySnapshot.weeklyTarget)}',
                      semantics:
                          'Weekly goal: '
                          '${formatEs(primarySnapshot.ewma7)} of '
                          '${formatEs(primarySnapshot.weeklyTarget)} weekly sets',
                      isMet: primarySnapshot.score >= 100,
                    );
              final Color scoreColor = goal.isMet
                  ? theme.colorScheme.tertiary
                  : AppColors.accentWarningAmber;
              // The goal chip shows sets-done / weekly-target (e.g. "12 / 14")
              // so the number and its goal reconcile at a glance and the target
              // is visible — colored green once on target, amber below. The
              // separate raw-count chip is intentionally dropped (it was the
              // same number a second time).
              final chips = <Widget>[
                AppChip(
                  variant: AppChipVariant.data,
                  icon: Icons.check_circle_outline,
                  label: 'Weekly goal',
                  value: goal.value,
                  color: scoreColor,
                  semanticsLabel: goal.semantics,
                ),
                AppChip(
                  variant: AppChipVariant.data,
                  icon: Icons.pie_chart_outline,
                  label: 'Share of training',
                  value:
                      '${NumberFormatUtil.formatDouble(primarySnapshot.share * 100, decimalDigits: 0)}%',
                ),
              ];
              final BodyScoreCoachingCue? coachingCue = isCurrentWeek
                  ? _currentWeekRegionCue(primarySnapshot, summary.region)
                  : (overallSummary != null
                        ? BodyScoreCoach.cueForRegion(
                            overallSummary!,
                            summary.region,
                          )
                        : null);
              if (coachingCue != null) {
                // Action guidance gets a distinct status treatment so it
                // reads as a prompt, not a factual data chip.
                chips.add(
                  AppChip(
                    variant: AppChipVariant.status,
                    color: theme.colorScheme.primary,
                    icon: Icons.tips_and_updates_outlined,
                    label: coachingCue.headline,
                    semanticsLabel: coachingCue.detail ?? coachingCue.headline,
                  ),
                );
              }
              return Wrap(spacing: 12, runSpacing: 8, children: chips);
            },
          ),
          if (summary.breakdown.isNotEmpty) ...[
            const SizedBox(height: 12),
            _MuscleBreakdownPanel(breakdown: summary.breakdown),
          ],
        ],
      ),
    );
  }
}

/// Builds the per-region status cue for the in-progress current week from the
/// already-rounded RAW snapshot (sets this week vs the weekly goal), so the
/// tile cue and the tile's "Weekly goal" figure read the same number. When the
/// region has met its goal it reads "done", never a nag.
BodyScoreCoachingCue? _currentWeekRegionCue(
  _RegionStimulusSnapshot? snapshot,
  DisplayRegion region,
) {
  if (snapshot == null || snapshot.weeklyTarget <= 0) return null;
  // Met-check and gap on the SAME rounded/display basis the headline renders
  // (`done.round() / target.round()`), matching `CurrentWeekRegionSummary.isMet`
  // / `BodyScoreCoach.currentWeekCue`. Comparing the raw fractional doubles here
  // would classify e.g. 9.5 vs a 10 target as under target and nag "Add about 1
  // set" while the tile shows "10 / 10 sets - done." Compare the displayed
  // integers so a displayed 10 / 10 is met with no nag.
  final int done = snapshot.ewma7.round();
  final int target = snapshot.weeklyTarget.round();
  if (done >= target) {
    return BodyScoreCoachingCue(
      mode: BodyScoreCoachingMode.maintain,
      headline: '${region.label} $done / $target sets - done.',
      primaryRegion: region,
    );
  }
  final int add = (target - done).clamp(1, 999).toInt();
  return BodyScoreCoachingCue(
    mode: BodyScoreCoachingMode.addSets,
    headline:
        'Add about $add ${region.label.toLowerCase()} '
        '${add == 1 ? 'set' : 'sets'}.',
    primaryRegion: region,
    setCount: add,
  );
}

/// Whether a region row is shown under the current filter.
///
/// With the default "Recently trained only" filter ([showActiveOnly]) a region
/// is normally kept only when it carries recent volume (>= 2 sets in the window)
/// or was trained in the last 21 days, which hides zero-volume rows.
///
/// Codex [P2] (PR #384): for the in-progress CURRENT WEEK the headline cue can
/// recommend a targeted region that has ZERO sets logged so far (e.g. "add chest
/// sets" at 0/10 when only core was trained this week). Under the default filter
/// that zero-volume row would be hidden, so the cue would name a region absent
/// from the list. The whole point of the weekly view is to SEE your gaps, so for
/// the current week we keep every targeted UNDER-target region visible by
/// default - the cue's recommended region is therefore always on screen. CLOSED
/// periods are unchanged: their recency/volume gate still hides dormant rows.
///
/// Exposed for testing so the filter logic can be asserted without standing up
/// the whole screen; the production [_BodyScoreScreenState._visibleSummaries]
/// getter calls it directly.
@visibleForTesting
bool isRegionVisibleForTest({
  required bool hasSnapshot,
  required double weeklyTarget,
  required bool isUnderTarget,
  required double windowVolume,
  required DateTime? lastStimulus,
  required bool showActiveOnly,
  required bool isCurrentWeek,
  required DateTime now,
}) {
  if (!showActiveOnly) {
    return true;
  }
  if (!hasSnapshot) return false;
  // Current week: never hide a targeted, under-target region - it is exactly the
  // kind of gap the cue points at, and hiding it would orphan the cue.
  if (isCurrentWeek && weeklyTarget > 0 && isUnderTarget) {
    return true;
  }
  final bool meetsVolume = windowVolume >= 2.0;
  final bool meetsRecency =
      lastStimulus != null && now.difference(lastStimulus).inDays <= 21;
  return meetsVolume || meetsRecency;
}

/// Test-only entry point into the private current-week region cue helper.
///
/// Builds a minimal [_RegionStimulusSnapshot] carrying just the raw current-week
/// volume ([ewma7]) and [weeklyTarget] that [_currentWeekRegionCue] reads, so a
/// test can assert the presentation cue stays consistent with the displayed
/// rounded `done / target` figure (e.g. 9.5 vs 10 reads met at 10 / 10).
@visibleForTesting
BodyScoreCoachingCue? currentWeekRegionCueForTest({
  required double ewma7,
  required double weeklyTarget,
  required DisplayRegion region,
}) {
  return _currentWeekRegionCue(
    _RegionStimulusSnapshot(
      score: 0,
      share: 0,
      ewma7: ewma7,
      ewma28: 0,
      recommendedSets: 0,
      lastStimulus: null,
      trend: 0,
      weeklyTarget: weeklyTarget,
      isDominant: false,
      isUnderTarget: false,
      windowVolume: ewma7,
    ),
    region,
  );
}

/// The rounded current-week "Weekly goal" chip display: the SINGLE basis for
/// the chip's value, its semantics, AND its met/under color/zone, so the three
/// can never disagree (the bug: a chip painted amber from a raw 95% score while
/// its rounded value and the cue both read a met 10 / 10).
class _GoalChipDisplay {
  const _GoalChipDisplay({
    required this.value,
    required this.semantics,
    required this.isMet,
  });

  final String value;
  final String semantics;
  final bool isMet;
}

/// Rounds the RAW current-week sets ([done]) and weekly goal ([target]) to the
/// displayed integers ONCE, then derives the chip value, semantics AND met
/// state from those same integers. So 9.5 / 10 renders "10 / 10" met (green),
/// 4.4 / 10 renders "4 / 10" under (amber) - consistent with
/// [_currentWeekRegionCue] and [CurrentWeekRegionSummary.isMet].
_GoalChipDisplay _currentWeekGoalDisplay({
  required double done,
  required double target,
}) {
  final int doneInt = done.round();
  final int targetInt = target.round();
  return _GoalChipDisplay(
    value: '$doneInt / $targetInt',
    semantics: 'Weekly goal: $doneInt of $targetInt weekly sets',
    isMet: doneInt >= targetInt,
  );
}

/// Test-only entry point into the rounded current-week goal-chip display, so a
/// test can assert the chip's value AND its met/under color basis stay on the
/// same rounded integers (9.5 / 10 -> "10 / 10" met; 4.4 / 10 -> "4 / 10"
/// under) without standing up the whole region tile.
@visibleForTesting
({String value, String semantics, bool isMet}) currentWeekGoalDisplayForTest({
  required double done,
  required double target,
}) {
  final display = _currentWeekGoalDisplay(done: done, target: target);
  return (
    value: display.value,
    semantics: display.semantics,
    isMet: display.isMet,
  );
}

/// Reconciles the current-week HEADLINE figure with the LEGACY detail-row
/// snapshot for ONE region, so a test can prove the collapsed "Trends & detail"
/// / "Muscle groups" rows show the SAME numbers as the headline bars / do-next.
///
/// Builds a [CurrentWeekRegionSummary] from the raw summed sets + the TRUE
/// physical-set count (the headline basis), then runs it through
/// [_BodyScoreScreenState._withRawCurrentWeek] (the legacy region-snapshot path)
/// and re-derives what the detail row renders: its value (`ewma7.round()`), its
/// "Add about N sets" gap, and the per-region cue. Returns BOTH the headline
/// display basis ([CurrentWeekRegionSummary.displaySets] / [displayGap]) and the
/// detail-row basis so the test can assert they match (e.g. both 9 / 10, never a
/// headline 9 / 10 vs a detail 5 / 10).
@visibleForTesting
({
  int headlineSets,
  int headlineGap,
  bool headlineMet,
  int detailSets,
  int detailGap,
  BodyScoreCoachingCue? detailCue,
})
currentWeekHeadlineVsDetailForTest({
  required DisplayRegion region,
  required double rawSets,
  required double weeklyTarget,
  int? physicalSets,
}) {
  final raw = CurrentWeekRegionSummary(
    region: region,
    rawSets: rawSets,
    weeklyTarget: weeklyTarget,
    physicalSets: physicalSets,
  );
  // A neutral base snapshot that carries this region's training so the row would
  // render; the display figures all come from [_withRawCurrentWeek].
  final base = _RegionStimulusSnapshot(
    score: 0,
    share: 0,
    ewma7: rawSets,
    ewma28: 0,
    recommendedSets: 0,
    lastStimulus: null,
    trend: 0,
    weeklyTarget: weeklyTarget,
    isDominant: false,
    isUnderTarget: false,
    windowVolume: rawSets,
  );
  final detail = _BodyScoreScreenState._withRawCurrentWeek(base, raw);
  return (
    headlineSets: raw.displaySets,
    headlineGap: raw.displayGap,
    headlineMet: raw.isMet,
    // Exactly what the collapsed detail row renders for the current week.
    detailSets: detail.ewma7.round(),
    detailGap: detail.recommendedSets.round(),
    detailCue: _currentWeekRegionCue(detail, region),
  );
}

/// Test-only entry point into the private coach-explain `regions` builder.
///
/// Mirrors the production call in [_BodyScoreScreenState._buildTrainingFacts]:
/// for the in-progress current week the per-region `percentOfGoal` figures come
/// from the RAW summed-sets-vs-target basis ([currentWeekRawSets]) so the
/// coach-explain facts match the on-screen cue + bars; closed periods keep the
/// paced basis. Lets a test assert the basis branch without standing up the
/// whole screen.
@visibleForTesting
List<Map<String, dynamic>> trainingFactsRegionsForTest({
  required BodyScoreSummary summary,
  required bool isCurrentWeek,
  required Map<MuscleGroup, double> currentWeekRawSets,
}) {
  return _BodyScoreScreenState._trainingFactsRegions(
    summary: summary,
    isCurrentWeek: isCurrentWeek,
    currentWeekRawSets: currentWeekRawSets,
  );
}

class _MuscleGroupBreakdown {
  const _MuscleGroupBreakdown({
    required this.group,
    required this.score,
    required this.ewma7,
    required this.weeklyTarget,
    required this.recommendedSets,
    required this.lastStimulus,
  });

  final MuscleGroup group;
  final double score;
  final double ewma7;
  final double weeklyTarget;
  final double recommendedSets;
  final DateTime? lastStimulus;
}

class _MuscleBreakdownPanel extends StatelessWidget {
  const _MuscleBreakdownPanel({required this.breakdown});

  final List<_MuscleGroupBreakdown> breakdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Text('Muscle breakdown', style: theme.textTheme.bodyLarge),
      // Cross-basis note: the region chip above reads the DEDUPED current-week
      // set count (e.g. "Legs 10 / 10 done"), but these per-muscle figures are a
      // DIFFERENT lens - each muscle's paced share of its own weekly goal
      // ((vol/days)*7 vs target). They are not the same number and need not
      // agree with the chip, so this is labelled explicitly to keep the %s from
      // being read as the headline set count.
      subtitle: Text(
        '${breakdown.length} muscles · paced share of each weekly goal',
        style: theme.textTheme.bodySmall,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Each muscle's paced % of its own weekly goal — a different lens "
              'from the set count above.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        for (final item in breakdown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.group.label,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                Text(
                  '${NumberFormatUtil.formatDouble(item.score, decimalDigits: 0)}%',
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
