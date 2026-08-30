import 'body_score_service.dart';

enum BodyScoreCoachingMode {
  maintain,
  addSets,
  redistributeSets,
  gatherMoreData,
}

class DisplayRegionStimulusSummary {
  const DisplayRegionStimulusSummary({
    required this.region,
    required this.actualWeeklyEquivalent,
    required this.weeklyTarget,
    required this.deficit,
    required this.excess,
  });

  final DisplayRegion region;
  final double actualWeeklyEquivalent;
  final double weeklyTarget;
  final double deficit;
  final double excess;

  double get percent =>
      weeklyTarget > 0 ? (actualWeeklyEquivalent / weeklyTarget) * 100.0 : 0.0;
}

class BodyScoreCoachingCue {
  const BodyScoreCoachingCue({
    required this.mode,
    required this.headline,
    this.detail,
    this.primaryRegion,
    this.secondaryRegion,
    this.setCount = 0,
  });

  final BodyScoreCoachingMode mode;
  final String headline;
  final String? detail;
  final DisplayRegion? primaryRegion;
  final DisplayRegion? secondaryRegion;
  final int setCount;
}

class BodyScoreCoach {
  const BodyScoreCoach._();

  static const double _underTargetThreshold = 100.0;
  static const double _severelyUnderTargetThreshold = 70.0;
  static const double _redistributionThreshold = 140.0;

  /// Aggregates each [DisplayRegion]'s actual-vs-target volume.
  ///
  /// [recencyAware] picks the actual-volume basis:
  /// - `true` (default): an EWMA blend that weights recent work heavily, so a
  ///   fresh hard day counts as real progress (used by the "next focus" nudge).
  /// - `false`: the FLAT period mean — exactly the basis the Training-balance
  ///   detail shows in its region tiles and balance score. The home card uses
  ///   this for its displayed verdict so it never claims "balanced" while the
  ///   detail it links to shows a region under target.
  static Map<DisplayRegion, DisplayRegionStimulusSummary>
  aggregateByDisplayRegion(
    BodyScoreSummary summary, {
    bool recencyAware = true,
  }) {
    final Map<DisplayRegion, double> actuals = {
      for (final region in DisplayRegion.values) region: 0.0,
    };
    final Map<DisplayRegion, double> targets = {
      for (final region in DisplayRegion.values) region: 0.0,
    };
    final Map<DisplayRegion, double> deficits = {
      for (final region in DisplayRegion.values) region: 0.0,
    };

    for (final group in MuscleGroup.values) {
      final region = group.displayRegion;
      final target = summary.weeklyTargets[group] ?? 0.0;
      if (target <= 0) continue;
      final actual = recencyAware
          ? _recencyWeeklyEquivalent(summary, group)
          : (summary.weeklyEquivalentVolumes[group] ?? 0.0);
      actuals[region] = (actuals[region] ?? 0.0) + actual;
      targets[region] = (targets[region] ?? 0.0) + target;
      deficits[region] =
          (deficits[region] ?? 0.0) +
          (target - actual).clamp(0.0, double.maxFinite);
    }

    return {
      for (final region in DisplayRegion.values)
        region: DisplayRegionStimulusSummary(
          region: region,
          actualWeeklyEquivalent: actuals[region] ?? 0.0,
          weeklyTarget: targets[region] ?? 0.0,
          deficit: deficits[region] ?? 0.0,
          excess: ((actuals[region] ?? 0.0) - (targets[region] ?? 0.0)).clamp(
            0.0,
            double.maxFinite,
          ),
        ),
    };
  }

  /// Builds the single headline verdict for the period.
  ///
  /// [recencyAware] selects the volume basis (see [aggregateByDisplayRegion]).
  /// The home card passes `false` so its verdict is computed from the same flat
  /// per-region basis the detail surfaces, keeping the two screens in agreement.
  static BodyScoreCoachingCue overallCue(
    BodyScoreSummary summary, {
    bool recencyAware = true,
  }) {
    final summaries =
        aggregateByDisplayRegion(summary, recencyAware: recencyAware).values
            .where((region) => region.region != DisplayRegion.other)
            .where((region) => region.weeklyTarget > 0)
            .toList(growable: false);
    if (summaries.isEmpty) {
      return const BodyScoreCoachingCue(
        mode: BodyScoreCoachingMode.maintain,
        headline: 'Keep training consistently.',
      );
    }

    final under =
        summaries
            .where((region) => region.percent < _underTargetThreshold)
            .toList(growable: false)
          ..sort((a, b) => a.percent.compareTo(b.percent));
    final over =
        summaries
            .where((region) => region.percent >= _redistributionThreshold)
            .toList(growable: false)
          ..sort((a, b) => b.percent.compareTo(a.percent));

    if (summary.sessionCount <= 1 && under.isNotEmpty) {
      final firstUnder = under.first;
      return BodyScoreCoachingCue(
        mode: BodyScoreCoachingMode.gatherMoreData,
        headline: 'Log 1 more session before rebalancing.',
        detail:
            '${firstUnder.region.label} is trailing so far, but this period is still thin on data.',
        primaryRegion: firstUnder.region,
      );
    }

    if (under.isNotEmpty && over.isNotEmpty) {
      final firstUnder = under.first;
      final firstOver = over.first;
      if (firstUnder.percent <= _severelyUnderTargetThreshold) {
        final shiftSets =
            _boundedSetCount(
              firstUnder.deficit,
              fallbackMin: 2,
              fallbackMax: 4,
              upperBound: firstOver.excess,
            ) ??
            2;
        return BodyScoreCoachingCue(
          mode: BodyScoreCoachingMode.redistributeSets,
          headline:
              'Shift $shiftSets sets from ${firstOver.region.label.toLowerCase()} to ${firstUnder.region.label.toLowerCase()}.',
          detail:
              '${firstOver.region.label} is well over target while ${firstUnder.region.label} is lagging.',
          primaryRegion: firstUnder.region,
          secondaryRegion: firstOver.region,
          setCount: shiftSets,
        );
      }
    }

    if (under.isNotEmpty) {
      final firstUnder = under.first;
      final addSets =
          _boundedSetCount(
            firstUnder.deficit,
            fallbackMin: 1,
            fallbackMax: 20,
          ) ??
          1;
      return BodyScoreCoachingCue(
        mode: BodyScoreCoachingMode.addSets,
        headline:
            'Add $addSets ${firstUnder.region.label.toLowerCase()} ${addSets == 1 ? 'set' : 'sets'}.',
        detail:
            '${firstUnder.region.label} is ${firstUnder.percent.toStringAsFixed(0)}% of weekly goal in this selected period.',
        primaryRegion: firstUnder.region,
        setCount: addSets,
      );
    }

    return const BodyScoreCoachingCue(
      mode: BodyScoreCoachingMode.maintain,
      headline: 'Balanced across regions.',
      detail: 'Keep your current distribution and progress the loads.',
    );
  }

  static BodyScoreCoachingCue cueForRegion(
    BodyScoreSummary summary,
    DisplayRegion region,
  ) {
    final regionSummary = aggregateByDisplayRegion(summary)[region];
    if (regionSummary == null || regionSummary.weeklyTarget <= 0) {
      return const BodyScoreCoachingCue(
        mode: BodyScoreCoachingMode.maintain,
        headline: 'No target set for this region.',
      );
    }

    final overall = overallCue(summary);
    if (overall.mode == BodyScoreCoachingMode.gatherMoreData) {
      return BodyScoreCoachingCue(
        mode: BodyScoreCoachingMode.gatherMoreData,
        headline: 'Log 1 more session before rebalancing.',
        detail:
            'This selected period is still too thin for confident region-level advice.',
        primaryRegion: region,
      );
    }
    if (overall.mode == BodyScoreCoachingMode.redistributeSets) {
      if (overall.primaryRegion == region) {
        return BodyScoreCoachingCue(
          mode: overall.mode,
          headline:
              'Shift ${overall.setCount} sets in from ${overall.secondaryRegion!.label.toLowerCase()}.',
          detail:
              '${region.label} is under target; reallocate volume before adding more total work.',
          primaryRegion: overall.primaryRegion,
          secondaryRegion: overall.secondaryRegion,
          setCount: overall.setCount,
        );
      }
      if (overall.secondaryRegion == region) {
        return BodyScoreCoachingCue(
          mode: overall.mode,
          headline:
              'Shift ${overall.setCount} sets out to ${overall.primaryRegion!.label.toLowerCase()}.',
          detail:
              '${region.label} is ahead of target and can donate volume without losing balance.',
          primaryRegion: overall.primaryRegion,
          secondaryRegion: overall.secondaryRegion,
          setCount: overall.setCount,
        );
      }
    }
    if (overall.mode == BodyScoreCoachingMode.addSets &&
        overall.primaryRegion == region) {
      return overall;
    }

    if (regionSummary.percent >= _underTargetThreshold) {
      return BodyScoreCoachingCue(
        mode: BodyScoreCoachingMode.maintain,
        headline: '${region.label} is on target.',
        detail:
            'Keep this muscle group at roughly the same weekly share of training.',
        primaryRegion: region,
      );
    }

    final addSets =
        _boundedSetCount(
          regionSummary.deficit,
          fallbackMin: 1,
          fallbackMax: 20,
        ) ??
        1;
    return BodyScoreCoachingCue(
      mode: BodyScoreCoachingMode.addSets,
      headline:
          'Add $addSets ${region.label.toLowerCase()} ${addSets == 1 ? 'set' : 'sets'}.',
      detail:
          '${region.label} is ${regionSummary.percent.toStringAsFixed(0)}% of weekly goal in this selected period.',
      primaryRegion: region,
      setCount: addSets,
    );
  }

  /// Recency-aware weekly-equivalent volume for a muscle group.
  ///
  /// The summary's [BodyScoreSummary.weeklyEquivalentVolumes] is a flat mean
  /// over the whole window, which dilutes a recent hard day across every idle
  /// day in the period and pushes the "add N sets" recommendation far too high.
  /// We instead blend the fast and slow EWMA rates (which already weight recent
  /// work heavily) so a fresh session counts as real progress without a single
  /// day collapsing the longer trend. When EWMA data is unavailable (e.g. the
  /// synthetic [BodyScoreSummary.calculate] path used in tests), all three rates
  /// coincide, so this reduces exactly to the flat weekly equivalent.
  static double _recencyWeeklyEquivalent(
    BodyScoreSummary summary,
    MuscleGroup group,
  ) {
    final flat = summary.weeklyEquivalentVolumes[group] ?? 0.0;
    final ewma7 = summary.ewma7[group];
    final ewma28 = summary.ewma28[group];
    if (ewma7 == null || ewma28 == null) {
      return flat;
    }
    return (ewma7 + ewma28) / 2.0;
  }

  /// Phase 1 (training-balance revamp): a RAW current-week display-region
  /// summary - summed sets THIS week vs the weekly goal, NOT the paced
  /// (vol/days)*7 figure (which inflates mid-week). [rawSetsByGroup] is the
  /// per-muscle-group RAW set count from
  /// [BodyScoreService.aggregateForRange] / [BodyRegionMetrics.sets]; targets
  /// come from the same weekly-target table the rest of the surface uses.
  ///
  /// Phase 4 (training-balance revamp): pass [physicalSetsByRegion] (the TRUE
  /// integer physical-set count per display region from
  /// [BodyScoreSummary.physicalSetsByDisplayRegion]) and/or [bandsByRegion] (the
  /// per-region [RegionVolumeBand] from [BodyScoreSummary.bandsByDisplayRegion])
  /// to drive the integer-count display + min/target/max band. When omitted the
  /// summary degrades to the rounded raw figure + a single target tick (the
  /// Phase 1 behaviour), so the Home focus card path is unchanged.
  static Map<DisplayRegion, CurrentWeekRegionSummary>
  currentWeekByDisplayRegion(
    Map<MuscleGroup, double> rawSetsByGroup, {
    Map<MuscleGroup, double> weeklyTargets = defaultWeeklyTargetsByMuscleGroup,
    Map<DisplayRegion, int>? physicalSetsByRegion,
    Map<DisplayRegion, RegionVolumeBand>? bandsByRegion,
  }) {
    final Map<DisplayRegion, double> sets = {
      for (final region in DisplayRegion.values) region: 0.0,
    };
    final Map<DisplayRegion, double> targets = {
      for (final region in DisplayRegion.values) region: 0.0,
    };
    for (final group in MuscleGroup.values) {
      final region = group.displayRegion;
      final target = weeklyTargets[group] ?? 0.0;
      if (target <= 0) continue;
      targets[region] = (targets[region] ?? 0.0) + target;
      sets[region] = (sets[region] ?? 0.0) + (rawSetsByGroup[group] ?? 0.0);
    }
    return {
      for (final region in DisplayRegion.values)
        region: CurrentWeekRegionSummary(
          region: region,
          rawSets: sets[region] ?? 0.0,
          weeklyTarget: targets[region] ?? 0.0,
          physicalSets: physicalSetsByRegion?[region],
          band: bandsByRegion?[region],
        ),
    };
  }

  /// Phase 1 headline cue for the in-progress current week: the RAW gap to the
  /// weekly goal for the most-behind targeted region. When every targeted
  /// region has met its goal there is NO nag - it reads as done. The figures
  /// the cue cites are the SAME raw-vs-target numbers the region headline shows
  /// (no EWMA / pace in the headline).
  static BodyScoreCoachingCue currentWeekCue(
    Map<MuscleGroup, double> rawSetsByGroup, {
    Map<MuscleGroup, double> weeklyTargets = defaultWeeklyTargetsByMuscleGroup,
    Map<DisplayRegion, int>? physicalSetsByRegion,
  }) {
    final summaries =
        currentWeekByDisplayRegion(
              rawSetsByGroup,
              weeklyTargets: weeklyTargets,
              physicalSetsByRegion: physicalSetsByRegion,
            ).values
            .where((region) => region.region != DisplayRegion.other)
            .where((region) => region.weeklyTarget > 0)
            .toList(growable: false);
    if (summaries.isEmpty) {
      return const BodyScoreCoachingCue(
        mode: BodyScoreCoachingMode.maintain,
        headline: 'Keep training consistently.',
      );
    }

    // Met-check on the SAME integer display basis the region headline renders
    // (it shows `displaySets / weeklyTarget.round()`, where displaySets is the
    // TRUE physical-set count when present, else the rounded raw figure). Using
    // the raw fractional value here would classify e.g. 9.5 raw vs a 10 target
    // as under target and nag "Add about 1 set" while the detail renders
    // "10 / 10 sets this week". Compare the displayed integers so 10/10 is met.
    // Order by the DISPLAYED percent so the largest DISPLAYED gap is recommended
    // first (matching the "This week, by region" bars + do-next). When physical
    // counts are absent (Home focus card path) [displayPercent] reduces to the
    // raw percent, so that path is unchanged.
    final under =
        summaries
            .where((region) => !region.isMet)
            .toList(growable: false)
          ..sort((a, b) => a.displayPercent.compareTo(b.displayPercent));

    if (under.isEmpty) {
      return const BodyScoreCoachingCue(
        mode: BodyScoreCoachingMode.maintain,
        headline: 'Every region has hit its weekly goal.',
        detail: 'Nice - your week is balanced across regions so far.',
      );
    }

    final firstUnder = under.first;
    // Gap to goal on the SAME integer display basis as the met-check and the
    // region headline (displaySets vs the rounded target), so the cue and the
    // headline reconcile (no 9.5-vs-10/10 contradiction).
    final int add = firstUnder.displayGap.clamp(1, 999);
    final region = firstUnder.region.label.toLowerCase();
    return BodyScoreCoachingCue(
      mode: BodyScoreCoachingMode.addSets,
      headline: 'Add about $add $region ${add == 1 ? 'set' : 'sets'}.',
      detail:
          '${firstUnder.region.label} is ${firstUnder.displaySets} / '
          '${firstUnder.weeklyTarget.round()} sets this week.',
      primaryRegion: firstUnder.region,
      setCount: add,
    );
  }

  static int? _boundedSetCount(
    double deficit, {
    required int fallbackMin,
    required int fallbackMax,
    double? upperBound,
  }) {
    final normalized = deficit.ceil();
    if (normalized <= 0 && (upperBound == null || upperBound <= 0)) {
      return null;
    }
    final maxAllowed = upperBound == null ? fallbackMax : upperBound.floor();
    if (maxAllowed <= 0) {
      return null;
    }
    return normalized.clamp(
      fallbackMin,
      maxAllowed.clamp(fallbackMin, fallbackMax),
    );
  }
}

/// A RAW current-week (Phase 1) per-display-region summary: summed sets this
/// week vs the weekly goal. Unlike [DisplayRegionStimulusSummary] this carries
/// no pace / EWMA - the figure is exactly the sets logged in the in-progress
/// week, compared directly to the target.
///
/// Phase 4 (training-balance revamp): when [physicalSets] (the TRUE integer
/// physical-set count) and/or [band] (the min/target/max [RegionVolumeBand]) are
/// supplied, the surface renders the integer count and the volume band. They are
/// optional so the Phase 1 path (Home focus card) degrades to the rounded raw
/// figure + a single target tick unchanged.
class CurrentWeekRegionSummary {
  const CurrentWeekRegionSummary({
    required this.region,
    required this.rawSets,
    required this.weeklyTarget,
    this.physicalSets,
    this.band,
  });

  final DisplayRegion region;
  final double rawSets;
  final double weeklyTarget;

  /// Phase 4: the TRUE integer count of physical working sets that trained this
  /// region this week (from [BodyScoreSummary.physicalSetsByDisplayRegion]).
  /// When null the surface falls back to `rawSets.round()`.
  final int? physicalSets;

  /// Phase 4: the min/target/max weekly-set band for this region (from
  /// [BodyScoreSummary.bandsByDisplayRegion]). When null the surface renders a
  /// single target tick.
  final RegionVolumeBand? band;

  /// The integer set figure the surface displays. Prefers the TRUE physical-set
  /// count ([physicalSets]) so e.g. ten physical sets read 10, never the
  /// fractional 9.5 the raw `baseSet x groupRatio` figure would round to. Falls
  /// back to the rounded raw figure when the integer count is unavailable
  /// (Phase 1 path / synthetic summaries).
  int get displaySets => physicalSets ?? rawSets.round();

  double get percent =>
      weeklyTarget > 0 ? (rawSets / weeklyTarget) * 100.0 : 0.0;

  /// Percent-of-target on the SAME integer display basis the surface renders
  /// ([displaySets] vs the rounded weekly target), used to ORDER the current-week
  /// IA so the largest DISPLAYED gap is recommended first. When the true physical
  /// count is supplied this reflects what the user actually sees (e.g. a 5 / 10
  /// primary outranks a 9 / 10 secondary-heavy region); when it is absent (the
  /// Phase 1 / synthetic path) [displaySets] is `rawSets.round()`, so this stays
  /// in lock-step with the raw [percent].
  double get displayPercent {
    final target = weeklyTarget.round();
    return target > 0 ? (displaySets / target) * 100.0 : 0.0;
  }

  /// The DISPLAYED gap to goal (rounded target minus [displaySets], floored at 0)
  /// - the exact figure the do-next / headline cite. Sorting the current-week IA
  /// by this (largest first) keeps the bar colour, the pip, [isMet], the do-next
  /// and the order all telling one story.
  int get displayGap =>
      (weeklyTarget.round() - displaySets).clamp(0, 1 << 30).toInt();

  /// Met on the SAME integer display basis the surface renders
  /// (`displaySets / weeklyTarget.round()`), so a displayed 10 / 10 reads as met
  /// and is never marked under target or nagged - whether the integer basis is
  /// the true physical-set count or the rounded raw figure.
  ///
  /// This is the ONE on-target predicate the whole current-week surface shares:
  /// the bar colour (emerald only when met), the on/under pip, the headline, and
  /// the do-next all key off it, so an under-target region can never read as
  /// met/green while the pip stays empty.
  bool get isMet => displaySets >= weeklyTarget.round();
}
