import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../exercise_library/domain/models/exercise.dart';
import '../../../workout_logging/domain/models/workout_exercise.dart';
import '../../../workout_logging/domain/models/workout_session.dart';
import '../../../workout_logging/domain/models/workout_set.dart';
import '../models/muscle_group.dart';
import '../utils/time_periods.dart';
import '../utils/muscle_group_mapper.dart';

export '../models/muscle_group.dart';

const double _defaultHalfLife7 = 3.5;
const double _defaultHalfLife28 = 7.0;
const double _dominantHighThreshold = 140.0;
const double _lowThreshold = 70.0;
const double _lastStimulusNoiseFloor = 0.15;
const double _lastStimulusThreshold = 0.5;
const double _daysPerWeek = 7.0;

/// Phase 4 (training-balance revamp) volume-band factors. The min/max edges
/// of a region's weekly-set band are derived as factor x target. 0.6 maps to a
/// maintenance/MEV-style floor; 1.4 to an MRV-style ceiling.
const double _bandMinFactor = 0.6;
const double _bandMaxFactor = 1.4;

/// Strategy interface that converts a set into a hard-set
/// multiplier. Implementations can optionally cap per-session totals.
abstract class BodyScoreLoadStrategy {
  const BodyScoreLoadStrategy();

  /// Multiplier applied to the base set value for a region contribution.
  double multiplierForSet(BodyScoreLoadInput input);

  /// Optional soft cap applied to total session hard sets for a muscle group.
  double applySessionCap(MuscleGroup group, double total) => total;
}

/// Context passed to a [BodyScoreLoadStrategy] when translating a set into a
/// per-muscle-group hard-set contribution.
class BodyScoreLoadInput {
  const BodyScoreLoadInput({
    required this.set,
    required this.exercise,
    required this.kind,
    required this.muscleGroup,
    required this.groupRatio,
    required this.allGroupRatios,
    required this.baseSetValue,
    this.rir,
  });

  final WorkoutSet set;
  final Exercise exercise;
  final ExerciseKind kind;
  final MuscleGroup muscleGroup;
  final double groupRatio;
  final Map<MuscleGroup, double> allGroupRatios;
  final double baseSetValue;
  final double? rir;

  double? get rpe => set.rpe?.toDouble();

  bool get isCompound => allGroupRatios.length > 1;
}

class BodyScoreStrategy {
  const BodyScoreStrategy({
    required this.id,
    required this.label,
    required this.description,
    required this.loadStrategy,
  });

  final String id;
  final String label;
  final String description;
  final BodyScoreLoadStrategy loadStrategy;
}

class BodyScoreStrategies {
  const BodyScoreStrategies._();

  static const BodyScoreStrategy effectiveSets = BodyScoreStrategy(
    id: 'effective_sets',
    label: 'Hard sets',
    description:
        'Counts your hard working sets, giving extra credit to sets pushed close '
        'to failure, then shares each set across the muscles it trains.',
    loadStrategy: EffectiveSetsLoadStrategy(),
  );

  static const List<BodyScoreStrategy> defaults = [effectiveSets];
}

class BodyScoreConfig {
  BodyScoreConfig({
    this.weeklyTargets = defaultWeeklyTargetsByMuscleGroup,
    BodyScoreLoadStrategy? loadStrategy,
    this.ewma7HalfLife = _defaultHalfLife7,
    this.ewma28HalfLife = _defaultHalfLife28,
    this.perSessionSoftCap = 11.0,
    this.postCapSlope = 0.3,
  }) : loadStrategy =
           loadStrategy ??
           EffectiveSetsLoadStrategy(
             perSessionSoftCap: perSessionSoftCap,
             postCapSlope: postCapSlope,
           );

  final Map<MuscleGroup, double> weeklyTargets;
  final BodyScoreLoadStrategy loadStrategy;
  final double ewma7HalfLife;
  final double ewma28HalfLife;
  final double perSessionSoftCap;
  final double postCapSlope;

  BodyScoreConfig copyWith({
    Map<MuscleGroup, double>? weeklyTargets,
    BodyScoreLoadStrategy? loadStrategy,
    double? ewma7HalfLife,
    double? ewma28HalfLife,
    double? perSessionSoftCap,
    double? postCapSlope,
  }) {
    final double nextSoftCap = perSessionSoftCap ?? this.perSessionSoftCap;
    final double nextPostCapSlope = postCapSlope ?? this.postCapSlope;
    final BodyScoreLoadStrategy resolvedStrategy =
        loadStrategy ??
        (this.loadStrategy is EffectiveSetsLoadStrategy
            ? EffectiveSetsLoadStrategy(
                perSessionSoftCap: nextSoftCap,
                postCapSlope: nextPostCapSlope,
              )
            : this.loadStrategy);
    return BodyScoreConfig(
      weeklyTargets: weeklyTargets ?? this.weeklyTargets,
      loadStrategy: resolvedStrategy,
      ewma7HalfLife: ewma7HalfLife ?? this.ewma7HalfLife,
      ewma28HalfLife: ewma28HalfLife ?? this.ewma28HalfLife,
      perSessionSoftCap: nextSoftCap,
      postCapSlope: nextPostCapSlope,
    );
  }
}

/// A per-region min / target / max volume band, expressed in weekly SETS.
///
/// Phase 4 (training-balance revamp). [target] is the canonical weekly set goal
/// (summed from the same per-muscle-group [defaultWeeklyTargetsByMuscleGroup]
/// table the rest of the surface uses). [min] and [max] bound a sensible window
/// around it so the UI can render a band rather than a single line: a region
/// below [min] is genuinely under-stimulated, a region above [max] is likely
/// junk volume. The defaults map to a lightweight MEV/MAV/MRV-style spread:
///   - min    = [_bandMinFactor] (0.6) x target  -> maintenance / MEV floor
///   - target = the planned working volume        -> MAV
///   - max    = [_bandMaxFactor] (1.4) x target  -> MRV ceiling
/// The factors are deliberately conservative; tighten them later if a per-muscle
/// MEV/MAV/MRV config is introduced.
class RegionVolumeBand {
  const RegionVolumeBand({
    required this.min,
    required this.target,
    required this.max,
  });

  /// Lower edge of the band (weekly sets). Below this a region is under-trained.
  final double min;

  /// Planned weekly volume target (weekly sets).
  final double target;

  /// Upper edge of the band (weekly sets). Above this is likely excess volume.
  final double max;

  static const zero = RegionVolumeBand(min: 0, target: 0, max: 0);

  /// Derives a band from a single weekly [target] using the default factors.
  factory RegionVolumeBand.fromTarget(double target) {
    if (target <= 0) return RegionVolumeBand.zero;
    return RegionVolumeBand(
      min: target * _bandMinFactor,
      target: target,
      max: target * _bandMaxFactor,
    );
  }

  /// Where [sets] falls relative to the band: < 0 below min, 0..1 inside the
  /// min..max band, > 1 above max. Useful as a UI fill ratio.
  double fillRatio(double sets) {
    if (max <= min) return 0;
    return (sets - min) / (max - min);
  }

  bool isBelow(double sets) => sets < min;
  bool isAbove(double sets) => sets > max;
  bool contains(double sets) => sets >= min && sets <= max;
}

class BodyRegionMetrics {
  const BodyRegionMetrics({
    required this.volume,
    required this.sets,
    required this.minutes,
  });

  final double volume;
  final double sets;
  final double minutes;

  static const zero = BodyRegionMetrics(volume: 0, sets: 0, minutes: 0);

  BodyRegionMetrics add(BodyRegionMetrics other) {
    return BodyRegionMetrics(
      volume: volume + other.volume,
      sets: sets + other.sets,
      minutes: minutes + other.minutes,
    );
  }

  BodyRegionMetrics copyWith({double? volume, double? sets, double? minutes}) {
    return BodyRegionMetrics(
      volume: volume ?? this.volume,
      sets: sets ?? this.sets,
      minutes: minutes ?? this.minutes,
    );
  }
}

class RegionStimulusDay {
  const RegionStimulusDay({required this.date, required this.esByMuscleGroup});

  final DateTime date;
  final Map<MuscleGroup, double> esByMuscleGroup;
}

class RegionStimulus {
  const RegionStimulus({
    required this.muscleGroup,
    required this.totalVolume,
    required this.weeklyEquivalent,
    required this.ewma7,
    required this.ewma28,
    required this.score,
    required this.share,
    required this.weeklyTarget,
    required this.lastStimulus,
    required this.deficit,
    required this.trend,
    required this.isDominant,
    required this.isUnderTarget,
    this.rawSets = 0,
    this.physicalSets = 0,
  });

  final MuscleGroup muscleGroup;
  final double totalVolume;
  final double weeklyEquivalent;
  final double ewma7;
  final double ewma28;
  final double score;
  final double share;
  final double weeklyTarget;
  final DateTime? lastStimulus;
  final double deficit;
  final double trend;
  final bool isDominant;
  final bool isUnderTarget;

  /// Phase 3: RAW summed working sets for this group over the window
  /// (`baseSet x groupRatio`; see [BodyScoreSummary.setsByGroup]).
  final double rawSets;

  /// Phase 4: integer count of physical working sets training this group
  /// (see [BodyScoreSummary.physicalSetsByGroup]).
  final int physicalSets;
}

class BodyScoreSummary {
  const BodyScoreSummary._({
    required this.window,
    required this.sessionCount,
    required this.regionTotals,
    required this.weeklyEquivalentVolumes,
    required this.regionShares,
    required this.regionScores,
    required this.ewma7,
    required this.ewma28,
    required this.weeklyTargets,
    required this.balanceScore,
    required this.dominantRegion,
    required this.dominantRatio,
    required this.dominantRegions,
    required this.timeline,
    required this.lastStimulus,
    required this.recommendedSets,
    required this.regionTrends,
    required this.topExercises,
    required this.setsByGroup,
    required this.physicalSetsByGroup,
    required this.physicalSetsByDisplayRegion,
  });

  static const Duration defaultWindow = Duration(days: 28);

  final DateTimeRange window;
  final int sessionCount;
  final Map<MuscleGroup, double> regionTotals;
  final Map<MuscleGroup, double> weeklyEquivalentVolumes;
  final Map<MuscleGroup, double> regionShares;
  final Map<MuscleGroup, double> regionScores;
  final Map<MuscleGroup, double> ewma7;
  final Map<MuscleGroup, double> ewma28;
  final Map<MuscleGroup, double> weeklyTargets;
  final double balanceScore;
  final MuscleGroup dominantRegion;
  final double dominantRatio;
  final List<MuscleGroup> dominantRegions;
  final List<RegionStimulusDay> timeline;
  final Map<MuscleGroup, DateTime?> lastStimulus;
  final Map<MuscleGroup, double> recommendedSets;
  final Map<MuscleGroup, double> regionTrends;
  final Map<MuscleGroup, Map<String, double>> topExercises;

  /// Phase 3 (training-balance revamp): RAW summed working SETS per muscle group
  /// over [window] - the exact same figure [BodyScoreService.aggregateForRange]
  /// surfaces via [BodyRegionMetrics.sets] (`baseSet x groupRatio`, so a set
  /// shared across muscles contributes a fraction to each). This flows raw sets
  /// through the canonical [BodyScoreService.summarize] / compute path so callers
  /// no longer need a separate `aggregateForRange` pass. Unlike the weighted
  /// effective-volume figures, this carries NO effort / rep / cap weighting.
  final Map<MuscleGroup, double> setsByGroup;

  /// Phase 4 (training-balance revamp): the count of ACTUAL physical working
  /// sets that trained each muscle group over [window], as whole integers. Every
  /// completed non-warmup set that touches a region counts as 1 for that region
  /// (a compound set training chest + triceps counts as 1 chest set AND 1
  /// triceps set). This is distinct from [setsByGroup] (the fractional
  /// `baseSet x groupRatio` raw figure) and from
  /// [weeklyEquivalentVolumes] / [regionScores] (the weighted "approx hard sets"
  /// figure, which applies effort/rep multipliers and can read fractional, e.g.
  /// 9.5). Use this when the UI must show a real integer set count.
  final Map<MuscleGroup, int> physicalSetsByGroup;

  /// Phase 4 (training-balance revamp): the per-display-region weekly-set
  /// [RegionVolumeBand] (min/target/max), derived from the canonical weekly
  /// targets summed per region. Only targeted regions are present.
  Map<DisplayRegion, RegionVolumeBand> get bandsByDisplayRegion {
    final Map<DisplayRegion, double> regionTargets = {
      for (final region in DisplayRegion.values) region: 0.0,
    };
    for (final group in MuscleGroup.values) {
      final region = group.displayRegion;
      if (region == DisplayRegion.other) continue;
      final target = weeklyTargets[group] ?? 0.0;
      if (target <= 0) continue;
      regionTargets[region] = (regionTargets[region] ?? 0.0) + target;
    }
    return {
      for (final region in DisplayRegion.values)
        if (region != DisplayRegion.other && (regionTargets[region] ?? 0.0) > 0.0)
          region: RegionVolumeBand.fromTarget(regionTargets[region]!),
    };
  }

  /// Phase 4: weekly-set [RegionVolumeBand] for one display [region], or
  /// [RegionVolumeBand.zero] when the region has no target.
  RegionVolumeBand bandForDisplayRegion(DisplayRegion region) =>
      bandsByDisplayRegion[region] ?? RegionVolumeBand.zero;

  /// Phase 3: RAW summed working sets per display region (see [setsByGroup]).
  Map<DisplayRegion, double> get setsByDisplayRegion {
    final Map<DisplayRegion, double> totals = {
      for (final region in DisplayRegion.values) region: 0.0,
    };
    for (final entry in setsByGroup.entries) {
      final region = entry.key.displayRegion;
      totals[region] = (totals[region] ?? 0.0) + entry.value;
    }
    return Map<DisplayRegion, double>.unmodifiable(totals);
  }

  /// Phase 3: RAW summed working sets for one display [region] (see
  /// [setsByGroup]). 0 when the region was untrained.
  double setsForDisplayRegion(DisplayRegion region) =>
      setsByDisplayRegion[region] ?? 0.0;

  /// Phase 4: integer count of DISTINCT physical working sets that trained each
  /// display region over [window]. Deduped per set: a single set that trains two
  /// muscles in the SAME display region (e.g. a Hack Squat touching Quads +
  /// Glutes, both -> Legs) contributes AT MOST 1 to that region, NOT the sum of
  /// its per-muscle [physicalSetsByGroup] counts. A set spanning two DIFFERENT
  /// display regions still counts 1 in each. This feeds the current-week integer
  /// bars/cues, so summing the per-group counts here would mark a region in range
  /// or over max too early.
  final Map<DisplayRegion, int> physicalSetsByDisplayRegion;

  /// Phase 4: integer physical-set count for one muscle [group].
  int physicalSetsForGroup(MuscleGroup group) => physicalSetsByGroup[group] ?? 0;

  double get totalVolume => regionTotals.values.fold<double>(
    0,
    (previous, value) => previous + value,
  );

  List<MuscleGroup> get mappableMuscleGroups => MuscleGroup.values
      .where(
        (group) => group != MuscleGroup.other && group != MuscleGroup.fullBody,
      )
      .where((group) => (weeklyTargets[group] ?? 0.0) > 0.0)
      .toList(growable: false);

  Map<MuscleGroup, double> get mappableRegionShares =>
      Map<MuscleGroup, double>.unmodifiable({
        for (final group in mappableMuscleGroups)
          group: regionShares[group] ?? 0,
      });

  int get mappableRegionCount => mappableMuscleGroups
      .where((group) => (regionShares[group] ?? 0) > 0)
      .length;

  int get totalMappableRegions => mappableMuscleGroups.length;

  int get activeRegionCount =>
      regionShares.values.where((value) => value > 0).length;

  int get windowDays => inclusiveDays(window);

  bool isRegionDominant(MuscleGroup group) => dominantRegions.contains(group);

  bool isRegionUnderTarget(MuscleGroup group) =>
      (weeklyTargets[group] ?? 0.0) > 0.0 && (regionScores[group] ?? 0) < 100.0;

  bool isRegionSeverelyUnderTarget(MuscleGroup group) =>
      (weeklyTargets[group] ?? 0.0) > 0.0 &&
      (regionScores[group] ?? 0) <= _lowThreshold;

  double deficitForRegion(MuscleGroup group) => recommendedSets[group] ?? 0;

  static BodyScoreSummary fromComputation({
    required DateTimeRange window,
    required int sessionCount,
    required Map<MuscleGroup, RegionStimulus> regions,
    required Map<MuscleGroup, Map<String, double>> topExercises,
    required List<RegionStimulusDay> timeline,
    Map<DisplayRegion, int> physicalSetsByDisplayRegion = const {},
  }) {
    final Map<MuscleGroup, double> totals = {
      for (final entry in regions.entries) entry.key: entry.value.totalVolume,
    };
    final Map<MuscleGroup, double> weeklyEquivalentVolumes = {
      for (final entry in regions.entries)
        entry.key: entry.value.weeklyEquivalent,
    };
    final Map<MuscleGroup, double> shares = {
      for (final entry in regions.entries) entry.key: entry.value.share,
    };
    final Map<MuscleGroup, double> scores = {
      for (final entry in regions.entries) entry.key: entry.value.score,
    };
    final Map<MuscleGroup, double> ewma7 = {
      for (final entry in regions.entries) entry.key: entry.value.ewma7,
    };
    final Map<MuscleGroup, double> ewma28 = {
      for (final entry in regions.entries) entry.key: entry.value.ewma28,
    };
    final Map<MuscleGroup, double> targets = {
      for (final entry in regions.entries) entry.key: entry.value.weeklyTarget,
    };
    final Map<MuscleGroup, DateTime?> lastStimulus = {
      for (final entry in regions.entries) entry.key: entry.value.lastStimulus,
    };
    final Map<MuscleGroup, double> recommendedSets = {
      for (final entry in regions.entries) entry.key: entry.value.deficit,
    };
    final Map<MuscleGroup, double> trends = {
      for (final entry in regions.entries) entry.key: entry.value.trend,
    };
    final Map<MuscleGroup, double> setsByGroup = {
      for (final entry in regions.entries) entry.key: entry.value.rawSets,
    };
    final Map<MuscleGroup, int> physicalSetsByGroup = {
      for (final entry in regions.entries) entry.key: entry.value.physicalSets,
    };
    final List<MuscleGroup> dominantRegions = regions.values
        .where((value) => value.isDominant)
        .map((value) => value.muscleGroup)
        .toList();
    final MuscleGroup dominantRegion = regions.values.fold(
      MuscleGroup.upperPecs,
      (previous, stimulus) => stimulus.score > (scores[previous] ?? 0)
          ? stimulus.muscleGroup
          : previous,
    );
    final double dominantRatio = shares[dominantRegion] ?? 0;
    final double balance = _balanceScore(
      _displayRegionScores(regions).values.toList(),
    );

    return BodyScoreSummary._(
      window: window,
      sessionCount: sessionCount,
      regionTotals: Map<MuscleGroup, double>.unmodifiable(totals),
      weeklyEquivalentVolumes: Map<MuscleGroup, double>.unmodifiable(
        weeklyEquivalentVolumes,
      ),
      regionShares: Map<MuscleGroup, double>.unmodifiable(shares),
      regionScores: Map<MuscleGroup, double>.unmodifiable(scores),
      ewma7: Map<MuscleGroup, double>.unmodifiable(ewma7),
      ewma28: Map<MuscleGroup, double>.unmodifiable(ewma28),
      weeklyTargets: Map<MuscleGroup, double>.unmodifiable(targets),
      balanceScore: balance,
      dominantRegion: dominantRegion,
      dominantRatio: dominantRatio,
      dominantRegions: List<MuscleGroup>.unmodifiable(dominantRegions),
      timeline: List<RegionStimulusDay>.unmodifiable(timeline),
      lastStimulus: Map<MuscleGroup, DateTime?>.unmodifiable(lastStimulus),
      recommendedSets: Map<MuscleGroup, double>.unmodifiable(recommendedSets),
      regionTrends: Map<MuscleGroup, double>.unmodifiable(trends),
      topExercises: {
        for (final entry in topExercises.entries)
          entry.key: Map<String, double>.unmodifiable(entry.value),
      },
      setsByGroup: Map<MuscleGroup, double>.unmodifiable(setsByGroup),
      physicalSetsByGroup: Map<MuscleGroup, int>.unmodifiable(
        physicalSetsByGroup,
      ),
      physicalSetsByDisplayRegion: Map<DisplayRegion, int>.unmodifiable({
        for (final region in DisplayRegion.values)
          region: physicalSetsByDisplayRegion[region] ?? 0,
      }),
    );
  }

  static BodyScoreSummary? calculate({
    required Map<MuscleGroup, double> volumes,
    required DateTimeRange window,
    required int sessionCount,
    double? balanceOverride,
    MuscleGroup? dominantOverride,
  }) {
    if (volumes.isEmpty) return null;
    final totalVolume = volumes.values.fold<double>(
      0,
      (previous, element) => previous + element,
    );
    if (totalVolume <= 0) return null;

    final Map<MuscleGroup, RegionStimulus> regions = {};
    for (final group in MuscleGroup.values) {
      final volume = volumes[group] ?? 0;
      final share = totalVolume > 0
          ? (volume / totalVolume).clamp(0.0, 1.0)
          : 0.0;
      final target = defaultWeeklyTargetsByMuscleGroup[group] ?? 10.0;
      final score = target > 0 ? (volume / target * 100.0) : 0.0;
      regions[group] = RegionStimulus(
        muscleGroup: group,
        totalVolume: volume,
        weeklyEquivalent: volume,
        ewma7: volume,
        ewma28: volume,
        score: score,
        share: share,
        weeklyTarget: target,
        lastStimulus: null,
        deficit: math.max(0, target - volume),
        trend: 0,
        isDominant: false,
        isUnderTarget: target > 0 && score < 100,
      );
    }
    final summary = BodyScoreSummary.fromComputation(
      window: window,
      sessionCount: sessionCount,
      regions: regions,
      topExercises: const {},
      timeline: const [],
    );
    if (balanceOverride != null || dominantOverride != null) {
      final double balance = balanceOverride ?? summary.balanceScore;
      final MuscleGroup dominant = dominantOverride ?? summary.dominantRegion;
      final double dominantRatio = summary.regionShares[dominant] ?? 0;
      return BodyScoreSummary._(
        window: summary.window,
        sessionCount: summary.sessionCount,
        regionTotals: summary.regionTotals,
        weeklyEquivalentVolumes: summary.weeklyEquivalentVolumes,
        regionShares: summary.regionShares,
        regionScores: summary.regionScores,
        ewma7: summary.ewma7,
        ewma28: summary.ewma28,
        weeklyTargets: summary.weeklyTargets,
        balanceScore: balance,
        dominantRegion: dominant,
        dominantRatio: dominantRatio,
        dominantRegions: summary.dominantRegions,
        timeline: summary.timeline,
        lastStimulus: summary.lastStimulus,
        recommendedSets: summary.recommendedSets,
        regionTrends: summary.regionTrends,
        topExercises: summary.topExercises,
        setsByGroup: summary.setsByGroup,
        physicalSetsByGroup: summary.physicalSetsByGroup,
        physicalSetsByDisplayRegion: summary.physicalSetsByDisplayRegion,
      );
    }
    return summary;
  }

  static double _balanceScore(List<double> regionScores) {
    final filtered = regionScores
        .where((value) => value > 0)
        .toList(growable: false);
    if (filtered.isEmpty) {
      return 0;
    }
    final mean =
        filtered.reduce((value, element) => value + element) / filtered.length;
    if (mean == 0) return 0;
    final variance =
        filtered
            .map((value) => math.pow(value - mean, 2))
            .reduce((value, element) => value + element) /
        filtered.length;
    final cv = math.sqrt(variance) / mean;
    final score = (100 - 100 * cv).clamp(0.0, 100.0);
    return score;
  }

  static Map<DisplayRegion, double> _displayRegionScores(
    Map<MuscleGroup, RegionStimulus> regions,
  ) {
    final Map<DisplayRegion, double> totals = {
      for (final region in DisplayRegion.values) region: 0.0,
    };
    final Map<DisplayRegion, double> targets = {
      for (final region in DisplayRegion.values) region: 0.0,
    };
    for (final entry in regions.entries) {
      final group = entry.key;
      final region = group.displayRegion;
      if (region == DisplayRegion.other) continue;
      final target = entry.value.weeklyTarget;
      if (target <= 0) continue;
      totals[region] = (totals[region] ?? 0.0) + entry.value.weeklyEquivalent;
      targets[region] = (targets[region] ?? 0.0) + target;
    }
    return {
      for (final region in DisplayRegion.values)
        if (region != DisplayRegion.other && (targets[region] ?? 0.0) > 0.0)
          region: (totals[region]! / targets[region]!) * 100.0,
    };
  }
}

class EffectiveSetsLoadStrategy extends BodyScoreLoadStrategy {
  const EffectiveSetsLoadStrategy({
    this.repRangeBands = const [
      RepRangeBand(min: 5, max: 30, factor: 1.0),
      RepRangeBand(min: 3, max: 4, factor: 0.85),
      RepRangeBand(min: 31, max: 40, factor: 0.85),
      RepRangeBand(min: 1, max: 2, factor: 0.7),
      RepRangeBand(min: 41, max: 99, factor: 0.7),
    ],
    this.rirEffort = const {0: 1.0, 1: 1.0, 2: 0.9, 3: 0.75, 4: 0.6, 5: 0.4},
    this.defaultCompoundEffort = 0.85,
    this.defaultIsolationEffort = 0.9,
    this.perSessionSoftCap = 11.0,
    this.postCapSlope = 0.3,
  });

  final List<RepRangeBand> repRangeBands;
  final Map<int, double> rirEffort;
  final double defaultCompoundEffort;
  final double defaultIsolationEffort;
  final double perSessionSoftCap;
  final double postCapSlope;

  @override
  double multiplierForSet(BodyScoreLoadInput input) {
    if (input.baseSetValue <= 0 || input.groupRatio <= 0) {
      return 0;
    }
    final repFactor = _repFactor(input.set.reps);
    final effort = _effortFactor(input);
    return repFactor * effort;
  }

  @override
  double applySessionCap(MuscleGroup group, double total) {
    if (perSessionSoftCap.isInfinite || perSessionSoftCap <= 0) {
      return total;
    }
    if (total <= perSessionSoftCap) return total;
    final over = total - perSessionSoftCap;
    return perSessionSoftCap + over * postCapSlope;
  }

  double _repFactor(int reps) {
    for (final band in repRangeBands) {
      if (reps >= band.min && reps <= band.max) {
        return band.factor;
      }
    }
    return repRangeBands.isEmpty ? 1.0 : repRangeBands.last.factor;
  }

  double _effortFactor(BodyScoreLoadInput input) {
    final double? rir = input.rir;
    if (rir != null) {
      final rounded = rir.round().clamp(0, 5);
      return rirEffort[rounded] ?? defaultCompoundEffort;
    }
    final double? rpe = input.rpe;
    if (rpe != null) {
      final inferred = _inferRirFromRpe(rpe);
      final rounded = inferred.round().clamp(0, 5);
      return rirEffort[rounded] ?? defaultCompoundEffort;
    }
    return input.isCompound ? defaultCompoundEffort : defaultIsolationEffort;
  }

  double _inferRirFromRpe(double rpe) {
    if (rpe >= 9.5) return 0;
    if (rpe >= 9.0) return 1;
    if (rpe >= 8.0) return 2;
    if (rpe >= 7.0) return 3;
    if (rpe >= 6.0) return 4;
    return 5;
  }
}

class BodyScoreService {
  BodyScoreService({MuscleGroupMapper? mapper, BodyScoreConfig? config})
    : _mapper = mapper ?? MuscleGroupMapper(),
      _config = config ?? BodyScoreConfig();

  final MuscleGroupMapper _mapper;
  final BodyScoreConfig _config;
  final Map<String, _CachedSessionMetrics> _cache = {};

  Map<MuscleGroup, double> get weeklyTargets =>
      Map<MuscleGroup, double>.unmodifiable(_config.weeklyTargets);

  Map<MuscleGroup, BodyRegionMetrics> aggregateForRange(
    List<WorkoutSession> sessions,
    DateTimeRange range,
  ) {
    final filtered = sessions
        .where((session) {
          return _sessionOverlapsRange(session, range.start, range.end);
        })
        .toList(growable: false);
    return _aggregateSessions(filtered);
  }

  Map<MuscleGroup, BodyRegionMetrics> aggregateForRollingWindow(
    List<WorkoutSession> sessions, {
    Duration window = const Duration(days: 7),
    DateTime? anchor,
  }) {
    final range = _resolvedWindow(window: window, anchor: anchor);
    final filtered = sessions
        .where((session) {
          return _sessionOverlapsRange(session, range.start, range.end);
        })
        .toList(growable: false);
    return _aggregateSessions(filtered);
  }

  Map<MuscleGroup, Map<String, double>> aggregateExerciseVolumeForRange(
    List<WorkoutSession> sessions,
    DateTimeRange range, {
    int topExercisesPerRegion = 5,
  }) {
    assert(topExercisesPerRegion > 0, 'topExercisesPerRegion must be > 0');
    final filtered = sessions
        .where((session) {
          return _sessionOverlapsRange(session, range.start, range.end);
        })
        .toList(growable: false);

    final Map<MuscleGroup, Map<String, double>> totals = {
      for (final group in MuscleGroup.values) group: <String, double>{},
    };

    for (final session in filtered) {
      final stimulus = _computeSessionStimulus(session);
      for (final group in MuscleGroup.values) {
        final exercises = stimulus.exerciseVolumes[group];
        if (exercises == null) continue;
        final groupTotals = totals[group]!;
        for (final entry in exercises.entries) {
          if (entry.value <= 0) continue;
          groupTotals.update(
            entry.key,
            (value) => value + entry.value,
            ifAbsent: () => entry.value,
          );
        }
      }
    }

    final Map<MuscleGroup, Map<String, double>> rounded = {};
    for (final group in MuscleGroup.values) {
      final entries = totals[group]!.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final limitedEntries = entries
          .take(topExercisesPerRegion)
          .map((entry) => MapEntry(entry.key, _round(entry.value, 1)));
      rounded[group] = Map<String, double>.fromEntries(limitedEntries);
    }
    return rounded;
  }

  Map<MuscleGroup, Map<String, double>> aggregateExerciseVolumeForRollingWindow(
    List<WorkoutSession> sessions, {
    Duration window = const Duration(days: 7),
    DateTime? anchor,
    int topExercisesPerRegion = 5,
  }) {
    final resolved = _resolvedWindow(window: window, anchor: anchor);
    return aggregateExerciseVolumeForRange(
      sessions,
      resolved,
      topExercisesPerRegion: topExercisesPerRegion,
    );
  }

  Map<MuscleGroup, Map<String, double>> aggregateExercisesForSession(
    WorkoutSession session, {
    int topExercisesPerRegion = 4,
    double minVolume = 0.1,
  }) {
    assert(topExercisesPerRegion > 0, 'topExercisesPerRegion must be > 0');
    final stimulus = _computeSessionStimulus(session);
    final Map<MuscleGroup, Map<String, double>> result = {};
    for (final group in MuscleGroup.values) {
      final exercises = stimulus.exerciseVolumes[group];
      if (exercises == null || exercises.isEmpty) continue;
      final entries =
          exercises.entries.where((entry) => entry.value >= minVolume).toList()
            ..sort((a, b) => b.value.compareTo(a.value));
      if (entries.isEmpty) continue;
      result[group] = {
        for (final entry in entries.take(topExercisesPerRegion))
          entry.key: _round(entry.value, 1),
      };
    }
    return result;
  }

  BodyScoreSummary? summarize(
    List<WorkoutSession> sessions, {
    Duration window = BodyScoreSummary.defaultWindow,
    DateTime? anchor,
    DateTimeRange? range,
  }) {
    final DateTimeRange resolvedRange = _resolvedWindow(
      window: window,
      anchor: anchor,
      range: range,
    );
    final DateTime start = resolvedRange.start;
    final DateTime end = resolvedRange.end;
    final relevantSessions = sessions
        .where((session) {
          return _sessionOverlapsRange(session, start, end);
        })
        .toList(growable: false);
    if (relevantSessions.isEmpty) {
      return null;
    }

    final Map<DateTime, Map<MuscleGroup, double>> dailyTotals = {};
    final Map<MuscleGroup, double> totalVolume = _zeroVolumeMap();
    // Phase 3: RAW summed sets per group (baseSet x groupRatio) - matches
    // aggregateForRange / BodyRegionMetrics.sets. Phase 4: integer physical-set
    // count per group. Both accumulate over the window via the canonical path.
    final Map<MuscleGroup, double> totalRawSets = _zeroVolumeMap();
    final Map<MuscleGroup, int> totalPhysicalSets = {
      for (final group in MuscleGroup.values) group: 0,
    };
    // Phase 4: window total of physical sets per DISPLAY region, deduped per set
    // (a set spanning two muscles in one region counts once for that region).
    final Map<DisplayRegion, int> totalPhysicalSetsByDisplayRegion = {
      for (final region in DisplayRegion.values) region: 0,
    };
    final Map<MuscleGroup, Map<String, double>> exerciseTotals = {
      for (final group in MuscleGroup.values) group: <String, double>{},
    };

    for (final session in relevantSessions) {
      final stimulus = _computeSessionStimulus(session);
      final DateTime performedAt = session.endTime ?? session.startTime;
      final DateTime dayKey = DateTime(
        performedAt.year,
        performedAt.month,
        performedAt.day,
      );
      final map = dailyTotals.putIfAbsent(dayKey, _zeroVolumeMap);
      for (final group in MuscleGroup.values) {
        final volume = stimulus.regionVolumes[group] ?? 0;
        if (volume <= 0) continue;
        map[group] = (map[group] ?? 0) + volume;
        totalVolume[group] = (totalVolume[group] ?? 0) + volume;
      }
      for (final group in MuscleGroup.values) {
        totalRawSets[group] =
            (totalRawSets[group] ?? 0) + (stimulus.regionSets[group] ?? 0);
        totalPhysicalSets[group] =
            (totalPhysicalSets[group] ?? 0) +
            (stimulus.regionPhysicalSets[group] ?? 0);
      }
      for (final region in DisplayRegion.values) {
        totalPhysicalSetsByDisplayRegion[region] =
            (totalPhysicalSetsByDisplayRegion[region] ?? 0) +
            (stimulus.regionPhysicalSetsByDisplayRegion[region] ?? 0);
      }
      for (final group in MuscleGroup.values) {
        final exercises = stimulus.exerciseVolumes[group];
        if (exercises == null) continue;
        final groupTotals = exerciseTotals[group]!;
        for (final entry in exercises.entries) {
          if (entry.value <= 0) continue;
          groupTotals.update(
            entry.key,
            (value) => value + entry.value,
            ifAbsent: () => entry.value,
          );
        }
      }
    }

    final bool hasStimulus = totalVolume.values.any(
      (value) => value > 0 && value.isFinite,
    );
    if (!hasStimulus) {
      return null;
    }

    final DateTime startDay = DateTime(start.year, start.month, start.day);
    final DateTime endDay = DateTime(end.year, end.month, end.day);
    final int totalDays = endDay.difference(startDay).inDays + 1;
    final List<DateTime> allDays = [
      for (int i = 0; i < totalDays; i++) startDay.add(Duration(days: i)),
    ];

    // The EWMA + last-stimulus scans only ever need to start at the FIRST day
    // that actually carries data (clamped to the range start), not at [startDay].
    // The EWMA recurrence seeds both accumulators at 0 and `dailyTotals` only
    // holds keys for days a session fell on, so every day before the earliest
    // session day is 0 for *every* group and leaves the accumulators at exactly
    // 0 - iterating them is provably a no-op (bit-identical result). Skipping
    // that leading run keeps the heavy O(span-days x groups) loops proportional
    // to the DATA span rather than the (possibly multi-year) requested range, so
    // a wide range over a sparse/old history never janks the frame loop. On
    // Flutter web `compute()` runs inline on the UI thread, so this guard
    // matters there especially. [totalDays], [periodWeeklyVolumes] and the
    // full-span [timeline] below are deliberately left on the full [startDay..
    // endDay] span - only the two decay scans are trimmed.
    final DateTime ewmaStartDay = dailyTotals.isEmpty
        ? startDay
        : () {
            DateTime earliest = dailyTotals.keys.first;
            for (final day in dailyTotals.keys) {
              if (day.isBefore(earliest)) earliest = day;
            }
            // A session straddling [start] can yield a dayKey before [startDay];
            // never scan before the range start (those days aren't in allDays).
            return earliest.isBefore(startDay) ? startDay : earliest;
          }();
    final int ewmaStartIndex = endDay.difference(ewmaStartDay).inDays >= 0
        ? math.max(0, ewmaStartDay.difference(startDay).inDays)
        : 0;
    final List<DateTime> scanDays = ewmaStartIndex == 0
        ? allDays
        : allDays.sublist(ewmaStartIndex);

    final double alpha7 = _alphaFromHalfLife(_config.ewma7HalfLife);
    final double alpha28 = _alphaFromHalfLife(_config.ewma28HalfLife);

    final Map<MuscleGroup, _RegionAggregate> aggregates = {
      for (final group in MuscleGroup.values)
        group: _RegionAggregate(totalVolume: totalVolume[group] ?? 0),
    };

    for (final group in MuscleGroup.values) {
      double prev7 = 0;
      double prev28 = 0;
      for (final day in scanDays) {
        final double value = dailyTotals[day]?[group] ?? 0;
        prev7 = alpha7 * value + (1 - alpha7) * prev7;
        prev28 = alpha28 * value + (1 - alpha28) * prev28;
      }
      aggregates[group] = aggregates[group]!.copyWith(
        ewma7: prev7 * _daysPerWeek,
        ewma28: prev28 * _daysPerWeek,
      );
    }

    final Map<MuscleGroup, DateTime?> lastStimulus = {
      for (final group in MuscleGroup.values) group: null,
    };
    for (final group in MuscleGroup.values) {
      for (final day in scanDays.reversed) {
        final double value = dailyTotals[day]?[group] ?? 0;
        if (value < _lastStimulusNoiseFloor) {
          continue;
        }
        if (value >= _lastStimulusThreshold) {
          lastStimulus[group] = day;
          break;
        }
      }
    }

    final Map<MuscleGroup, double> periodWeeklyVolumes = {
      for (final group in MuscleGroup.values)
        group: totalDays > 0
            ? ((aggregates[group]!.totalVolume / totalDays) * _daysPerWeek)
            : 0.0,
    };
    final double totalPeriodWeeklyVolume = periodWeeklyVolumes.values
        .fold<double>(0, (sum, volume) => sum + volume);

    final Map<MuscleGroup, double> scores = {};
    for (final group in MuscleGroup.values) {
      final double target = _config.weeklyTargets[group] ?? 10.0;
      final double weeklyEquivalent = periodWeeklyVolumes[group] ?? 0.0;
      scores[group] = target > 0 ? (weeklyEquivalent / target * 100) : 0;
    }
    final bool anyLowScore = MuscleGroup.values.any((group) {
      final double target = _config.weeklyTargets[group] ?? 10.0;
      if (target <= 0) return false;
      return (scores[group] ?? 0.0) <= _lowThreshold;
    });

    final Map<MuscleGroup, RegionStimulus> regions = {};
    for (final group in MuscleGroup.values) {
      final _RegionAggregate aggregate = aggregates[group]!;
      final double target = _config.weeklyTargets[group] ?? 10.0;
      final double score = scores[group] ?? 0;
      final double weeklyEquivalent = periodWeeklyVolumes[group] ?? 0.0;
      final double share = totalPeriodWeeklyVolume > 0
          ? (weeklyEquivalent / totalPeriodWeeklyVolume)
          : 0;
      regions[group] = RegionStimulus(
        muscleGroup: group,
        totalVolume: aggregate.totalVolume,
        weeklyEquivalent: weeklyEquivalent,
        ewma7: aggregate.ewma7,
        ewma28: aggregate.ewma28,
        score: score,
        share: share.isFinite ? share : 0,
        weeklyTarget: target,
        lastStimulus: lastStimulus[group],
        deficit: math.max(0, target - weeklyEquivalent),
        trend: aggregate.ewma7 - aggregate.ewma28,
        isDominant: score >= _dominantHighThreshold && anyLowScore,
        isUnderTarget: target > 0 && score < 100,
        // Round raw sets to 2dp to match aggregateForRange / _roundTotals so
        // setsByGroup and a direct aggregateForRange call agree exactly.
        rawSets: _round(totalRawSets[group] ?? 0, 2),
        physicalSets: totalPhysicalSets[group] ?? 0,
      );
    }

    final List<RegionStimulusDay> timeline = [
      for (final day in allDays)
        RegionStimulusDay(
          date: day,
          esByMuscleGroup: Map<MuscleGroup, double>.unmodifiable({
            for (final group in MuscleGroup.values)
              group: () {
                final double value = dailyTotals[day]?[group] ?? 0;
                return value >= _lastStimulusNoiseFloor ? value : 0.0;
              }(),
          }),
        ),
    ];

    final summary = BodyScoreSummary.fromComputation(
      window: resolvedRange,
      sessionCount: relevantSessions.length,
      regions: regions,
      topExercises: exerciseTotals,
      timeline: timeline,
      physicalSetsByDisplayRegion: totalPhysicalSetsByDisplayRegion,
    );
    return summary;
  }

  void clearCache() => _cache.clear();

  Map<MuscleGroup, BodyRegionMetrics> _aggregateSessions(
    List<WorkoutSession> sessions,
  ) {
    final totals = _emptyMetricsMap();
    for (final session in sessions) {
      final sessionMetrics = _metricsForSession(session);
      for (final entry in sessionMetrics.entries) {
        totals[entry.key] = totals[entry.key]!.add(entry.value);
      }
    }
    return UnmodifiableMapView(_roundTotals(totals));
  }

  Map<MuscleGroup, BodyRegionMetrics> _metricsForSession(
    WorkoutSession session,
  ) {
    return _cachedSessionMetrics(session).metrics;
  }

  /// Returns the cached per-session metrics + deduped per-display-region
  /// physical-set count, recomputing (and re-caching) only on a signature miss.
  _CachedSessionMetrics _cachedSessionMetrics(WorkoutSession session) {
    final cacheKey = session.id;
    final signature = _sessionSignature(session);
    final existing = _cache[cacheKey];
    if (existing != null && existing.signature == signature) {
      return existing;
    }

    final computed = _computeSessionStimulus(session);
    final entry = _CachedSessionMetrics(
      signature: signature,
      metrics: _metricsFromStimulus(computed),
      physicalSetsByDisplayRegion: Map<DisplayRegion, int>.unmodifiable(
        computed.regionPhysicalSetsByDisplayRegion,
      ),
    );
    _cache[cacheKey] = entry;
    return entry;
  }

  /// Lightweight per-range trend tally: the SAME deduped integer
  /// physical-set-per-display-region basis the headline bars ride
  /// ([BodyScoreSummary.physicalSetsByDisplayRegion]), summed over the sessions
  /// overlapping [range] - WITHOUT the heavy EWMA timeline / scores / exercise
  /// totals [summarize] also computes (and which the trend strip never reads).
  ///
  /// Cache-backed via [_cachedSessionMetrics], so flipping through the last few
  /// weeks for the trend strip reuses each session's already-computed stimulus
  /// instead of re-running the O(sessions x exercises x sets) work per week.
  Map<DisplayRegion, int> physicalSetsByDisplayRegionForRange(
    List<WorkoutSession> sessions,
    DateTimeRange range,
  ) {
    final Map<DisplayRegion, int> totals = {
      for (final region in DisplayRegion.values) region: 0,
    };
    for (final session in sessions) {
      if (!_sessionOverlapsRange(session, range.start, range.end)) continue;
      final perSession = _cachedSessionMetrics(session).physicalSetsByDisplayRegion;
      for (final region in DisplayRegion.values) {
        final count = perSession[region] ?? 0;
        if (count == 0) continue;
        totals[region] = (totals[region] ?? 0) + count;
      }
    }
    return totals;
  }

  _SessionStimulus _computeSessionStimulus(WorkoutSession session) {
    final contributions = _buildSetContributions(session);
    final totalDurationSets = contributions
        .where((c) => c.countsForDuration)
        .length;
    final sessionDurationSeconds = session.duration.inSeconds.toDouble().clamp(
      0.0,
      double.maxFinite,
    );
    final perSetDurationSeconds = totalDurationSets == 0
        ? 0.0
        : sessionDurationSeconds / totalDurationSets;

    final Map<MuscleGroup, double> rawVolumes = _zeroVolumeMap();
    final Map<MuscleGroup, double> setCounts = _zeroVolumeMap();
    // Phase 4: true integer count of physical working sets per region. Each
    // completed non-warmup set that trains a region adds 1 (NOT baseSet*ratio),
    // so a region worked by 10 physical sets reads 10, not a fractional figure.
    final Map<MuscleGroup, int> physicalSetCounts = {
      for (final group in MuscleGroup.values) group: 0,
    };
    // Phase 4: integer count of physical working sets per DISPLAY region,
    // DEDUPED per set. A single set that trains two muscles in the SAME display
    // region (e.g. a Hack Squat touching Quads + Glutes, both -> Legs) must add
    // 1 to that region, not 1 per muscle. Summing [physicalSetCounts] across the
    // region would double-count, so we tally distinct display regions per set.
    final Map<DisplayRegion, int> physicalSetCountsByDisplayRegion = {
      for (final region in DisplayRegion.values) region: 0,
    };
    final Map<MuscleGroup, double> minutes = _zeroVolumeMap();
    final Map<MuscleGroup, Map<String, double>> exerciseVolumes = {
      for (final group in MuscleGroup.values) group: <String, double>{},
    };

    for (final contribution in contributions) {
      final durationBase = contribution.countsForDuration
          ? perSetDurationSeconds
          : 0.0;
      // Display regions this single set actually trained (>0 volume). Used to
      // add 1 physical set per DISPLAY region for THIS set, never one-per-muscle.
      final Set<DisplayRegion> setDisplayRegions = <DisplayRegion>{};
      for (final entry in contribution.normalizedWeights.entries) {
        final muscleGroup = entry.key;
        final ratio = entry.value;
        if (ratio <= 0) continue;
        final volume = _volumeForSet(
          set: contribution.set,
          exercise: contribution.exercise,
          kind: contribution.kind,
          muscleGroup: muscleGroup,
          groupRatio: ratio,
          normalizedWeights: contribution.normalizedWeights,
          baseSet: contribution.baseSet,
        );
        if (volume <= 0) continue;
        rawVolumes[muscleGroup] = (rawVolumes[muscleGroup] ?? 0) + volume;
        setCounts[muscleGroup] =
            (setCounts[muscleGroup] ?? 0) + (contribution.baseSet * ratio);
        if (contribution.baseSet > 0) {
          physicalSetCounts[muscleGroup] =
              (physicalSetCounts[muscleGroup] ?? 0) + 1;
          setDisplayRegions.add(muscleGroup.displayRegion);
        }
        minutes[muscleGroup] =
            (minutes[muscleGroup] ?? 0) + (durationBase / 60.0 * ratio);
        final groupExercises = exerciseVolumes[muscleGroup]!;
        groupExercises.update(
          contribution.displayName,
          (value) => value + volume,
          ifAbsent: () => volume,
        );
      }
      // This set contributes AT MOST 1 to each display region it touched, so a
      // Quads + Glutes set (both -> Legs) adds 1 Legs set, not 2.
      for (final region in setDisplayRegions) {
        physicalSetCountsByDisplayRegion[region] =
            (physicalSetCountsByDisplayRegion[region] ?? 0) + 1;
      }
    }

    final Map<MuscleGroup, double> cappedVolumes = _zeroVolumeMap();
    for (final group in MuscleGroup.values) {
      final raw = rawVolumes[group] ?? 0;
      final capped = _config.loadStrategy
          .applySessionCap(group, raw)
          .clamp(0.0, double.infinity);
      cappedVolumes[group] = capped;
      final Map<String, double> exercises = exerciseVolumes[group]!;
      if (raw > 0 && raw != capped) {
        final scale = capped / raw;
        exercises.updateAll((key, value) => value * scale);
      }
    }

    return _SessionStimulus(
      regionVolumes: cappedVolumes,
      regionSets: setCounts,
      regionPhysicalSets: physicalSetCounts,
      regionPhysicalSetsByDisplayRegion: physicalSetCountsByDisplayRegion,
      regionMinutes: minutes,
      exerciseVolumes: exerciseVolumes,
    );
  }

  Map<MuscleGroup, BodyRegionMetrics> _metricsFromStimulus(
    _SessionStimulus stimulus,
  ) {
    final Map<MuscleGroup, BodyRegionMetrics> totals = _emptyMetricsMap();
    for (final group in MuscleGroup.values) {
      totals[group] = BodyRegionMetrics(
        volume: stimulus.regionVolumes[group] ?? 0,
        sets: stimulus.regionSets[group] ?? 0,
        minutes: stimulus.regionMinutes[group] ?? 0,
      );
    }
    return totals;
  }

  List<_SetContribution> _buildSetContributions(WorkoutSession session) {
    final List<_SetContribution> contributions = [];
    for (final workoutExercise in session.exercises) {
      final weights = _regionWeightsForExercise(workoutExercise);
      if (weights.isEmpty) continue;
      final normalized = _normalizedRegionWeights(weights);
      final baseSet = workoutExercise.exercise.kind == ExerciseKind.cardio
          ? 0.0
          : 1.0;
      final displayName = workoutExercise.exercise.name.isNotEmpty
          ? workoutExercise.exercise.name
          : 'Unnamed Exercise';
      for (final set in workoutExercise.sets) {
        if (!set.isCompleted) continue;
        if (set.setType == SetType.warmup) continue;
        contributions.add(
          _SetContribution(
            set: set,
            exercise: workoutExercise.exercise,
            kind: workoutExercise.exercise.kind,
            normalizedWeights: normalized,
            baseSet: baseSet,
            countsForDuration: baseSet > 0,
            displayName: displayName,
          ),
        );
      }
    }
    return contributions;
  }

  int _sessionSignature(WorkoutSession session) {
    final timestamp =
        (session.lastUpdatedAt ?? session.endTime ?? session.startTime)
            .millisecondsSinceEpoch;
    final exerciseSignatures = <int>[];
    for (final workoutExercise in session.exercises) {
      final exercise = workoutExercise.exercise;
      final slug = exercise.slug?.trim().toLowerCase() ?? '';
      final name = exercise.name.trim().toLowerCase();
      final normalizedMuscles = <String>[];
      final seen = <String>{};
      for (final muscle in exercise.muscles) {
        final cleaned = muscle.trim().toLowerCase();
        if (cleaned.isEmpty || !seen.add(cleaned)) continue;
        normalizedMuscles.add(cleaned);
      }
      normalizedMuscles.sort();
      final musclesSignature = normalizedMuscles.isEmpty
          ? 0
          : Object.hashAll(normalizedMuscles);
      final exerciseSignature = Object.hash(
        exercise.kind,
        slug,
        name,
        normalizedMuscles.length,
        musclesSignature,
      );
      exerciseSignatures.add(exerciseSignature);
    }
    final combinedExercisesSignature = Object.hashAll(exerciseSignatures);
    return Object.hash(timestamp, combinedExercisesSignature);
  }

  Map<MuscleGroup, BodyRegionMetrics> _roundTotals(
    Map<MuscleGroup, BodyRegionMetrics> totals,
  ) {
    final rounded = <MuscleGroup, BodyRegionMetrics>{};
    for (final group in MuscleGroup.values) {
      final current = totals[group] ?? BodyRegionMetrics.zero;
      rounded[group] = BodyRegionMetrics(
        volume: _round(current.volume, 1),
        sets: _round(current.sets, 2),
        minutes: _round(current.minutes, 1),
      );
    }
    return rounded;
  }

  Map<MuscleGroup, double> _normalizedRegionWeights(
    Map<MuscleGroup, double> weights,
  ) {
    if (weights.isEmpty) {
      return {MuscleGroup.other: 1.0};
    }
    final filtered = <MuscleGroup, double>{
      for (final entry in weights.entries)
        if (entry.value > 0) entry.key: entry.value,
    };
    if (filtered.isEmpty) {
      return {MuscleGroup.other: 1.0};
    }
    return filtered;
  }

  Map<MuscleGroup, double> _regionWeightsForExercise(
    WorkoutExercise workoutExercise,
  ) {
    final Exercise exercise = workoutExercise.exercise;
    final muscles = exercise.muscles;
    if (muscles.isEmpty) {
      return {MuscleGroup.other: 1.0};
    }
    final weights = <MuscleGroup, double>{};
    final normalizedMuscles = muscles
        .map((muscle) => muscle.trim())
        .where((muscle) => muscle.isNotEmpty)
        .toList(growable: false);
    if (normalizedMuscles.isEmpty) {
      return {MuscleGroup.other: 1.0};
    }
    for (var i = 0; i < normalizedMuscles.length; i++) {
      final muscle = normalizedMuscles[i];
      final group = _mapper.groupFor(muscle);
      final weight = i == 0 ? 1.0 : 0.5;
      weights.update(group, (value) => value + weight, ifAbsent: () => weight);
    }
    if (weights.length > 1 && weights.containsKey(MuscleGroup.other)) {
      weights.remove(MuscleGroup.other);
    }
    return weights;
  }

  double _volumeForSet({
    required WorkoutSet set,
    required Exercise exercise,
    required ExerciseKind kind,
    required MuscleGroup muscleGroup,
    required double groupRatio,
    required Map<MuscleGroup, double> normalizedWeights,
    required double baseSet,
  }) {
    if (kind == ExerciseKind.cardio || groupRatio <= 0 || baseSet <= 0) {
      return 0.0;
    }
    final input = BodyScoreLoadInput(
      set: set,
      exercise: exercise,
      kind: kind,
      muscleGroup: muscleGroup,
      groupRatio: groupRatio,
      allGroupRatios: normalizedWeights,
      baseSetValue: baseSet,
    );
    final multiplier = _config.loadStrategy.multiplierForSet(input);
    return baseSet * groupRatio * multiplier;
  }

  DateTimeRange _resolvedWindow({
    Duration window = BodyScoreSummary.defaultWindow,
    DateTime? anchor,
    DateTimeRange? range,
  }) {
    if (range != null) return range;
    final int windowDays = math.max(
      (window.inMicroseconds / Duration.microsecondsPerDay).ceil(),
      1,
    );
    return rollingRangeToToday(days: windowDays, anchor: anchor);
  }

  bool _sessionOverlapsRange(
    WorkoutSession session,
    DateTime start,
    DateTime end,
  ) {
    final sessionStart = session.startTime;
    final sessionEnd = session.endTime ?? session.startTime;
    if (sessionEnd.isBefore(start)) return false;
    if (sessionStart.isAfter(end)) return false;
    return true;
  }

  Map<MuscleGroup, BodyRegionMetrics> _emptyMetricsMap() {
    return {
      for (final group in MuscleGroup.values) group: BodyRegionMetrics.zero,
    };
  }

  static Map<MuscleGroup, double> _zeroVolumeMap() {
    return {for (final group in MuscleGroup.values) group: 0.0};
  }

  double _round(double value, int precision) {
    if (precision <= 0) {
      return value.roundToDouble();
    }
    final factor = math.pow(10, precision).toDouble();
    return (value * factor).roundToDouble() / factor;
  }
}

class _SessionStimulus {
  const _SessionStimulus({
    required this.regionVolumes,
    required this.regionSets,
    required this.regionPhysicalSets,
    required this.regionPhysicalSetsByDisplayRegion,
    required this.regionMinutes,
    required this.exerciseVolumes,
  });

  final Map<MuscleGroup, double> regionVolumes;
  final Map<MuscleGroup, double> regionSets;
  final Map<MuscleGroup, int> regionPhysicalSets;
  /// Phase 4: physical working sets per DISPLAY region for this session, deduped
  /// per set (a set touching two muscles in one region counts once).
  final Map<DisplayRegion, int> regionPhysicalSetsByDisplayRegion;
  final Map<MuscleGroup, double> regionMinutes;
  final Map<MuscleGroup, Map<String, double>> exerciseVolumes;
}

class _SetContribution {
  const _SetContribution({
    required this.set,
    required this.exercise,
    required this.kind,
    required this.normalizedWeights,
    required this.baseSet,
    required this.countsForDuration,
    required this.displayName,
  });

  final WorkoutSet set;
  final Exercise exercise;
  final ExerciseKind kind;
  final Map<MuscleGroup, double> normalizedWeights;
  final double baseSet;
  final bool countsForDuration;
  final String displayName;
}

class _RegionAggregate {
  const _RegionAggregate({
    required this.totalVolume,
    this.ewma7 = 0,
    this.ewma28 = 0,
  });

  final double totalVolume;
  final double ewma7;
  final double ewma28;

  _RegionAggregate copyWith({
    double? totalVolume,
    double? ewma7,
    double? ewma28,
  }) {
    return _RegionAggregate(
      totalVolume: totalVolume ?? this.totalVolume,
      ewma7: ewma7 ?? this.ewma7,
      ewma28: ewma28 ?? this.ewma28,
    );
  }
}

class _CachedSessionMetrics {
  const _CachedSessionMetrics({
    required this.signature,
    required this.metrics,
    required this.physicalSetsByDisplayRegion,
  });

  final int signature;
  final Map<MuscleGroup, BodyRegionMetrics> metrics;
  // Phase 4 deduped per-set physical-set count per DISPLAY region for THIS
  // session (a set touching two muscles in one region counts once). Cached
  // alongside [metrics] so the lightweight per-range trend tally
  // ([physicalSetsByDisplayRegionForRange]) never re-runs the heavy stimulus.
  final Map<DisplayRegion, int> physicalSetsByDisplayRegion;
}

class RepRangeBand {
  const RepRangeBand({
    required this.min,
    required this.max,
    required this.factor,
  });

  final int min;
  final int max;
  final double factor;
}

double _alphaFromHalfLife(double halfLifeDays) {
  return 1 - math.pow(0.5, 1 / halfLifeDays).toDouble();
}
