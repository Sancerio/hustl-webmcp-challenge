import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';
import 'package:hustl_app/core/coaching/coach_explain_api.dart';
import 'package:hustl_app/core/coaching/explain_section.dart';
import 'package:hustl_app/core/coaching/training_explain_facts.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/widgets/animated_metric_text.dart';
import 'package:hustl_app/core/widgets/app_chip.dart';
import 'package:hustl_app/core/widgets/app_progress_ring.dart';
import 'package:hustl_app/core/widgets/app_section.dart';
import 'package:hustl_app/core/widgets/hustl_inline_skeleton.dart';
import 'package:hustl_app/core/widgets/hustl_menu_button.dart';
import 'package:hustl_app/core/widgets/screen_empty_state.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/preferences_service.dart';
import '../../../../core/utils/number_format_util.dart';
import '../../../../core/widgets/main_scaffold.dart';
import '../../domain/services/body_score_coach.dart';
import '../../domain/services/body_score_compute.dart';
import '../../domain/services/body_score_service.dart';
import '../../domain/utils/time_periods.dart';
import '../../../workout_logging/domain/models/workout_session.dart';
import '../../../workout_logging/domain/repositories/workout_repository.dart';
import '../widgets/body_score_radar.dart';
import '../widgets/body_heat_map.dart';
import '../widgets/body_score/overview_trend_sparkline.dart';
import '../widgets/body_score/this_week_by_region.dart';
import '../widgets/body_score/four_week_trend_strip.dart';

part 'body_score_screen.widgets1.dart';
part 'body_score_screen.widgets2.dart';
part 'body_score_screen.widgets3.dart';

enum BodyScoreRegionSort {
  score('Furthest from goal'),
  addSets('Biggest set gap'),
  recency('Most overdue'),
  stimulus('Most trained');

  const BodyScoreRegionSort(this.label);

  final String label;
}

class BodyScoreSnapshot {
  const BodyScoreSnapshot({
    required this.summary,
    required this.range,
    required this.label,
    this.isPartial = false,
  });

  final BodyScoreSummary summary;
  final DateTimeRange range;
  final String label;
  final bool isPartial;
}

class BodyScoreComparison {
  const BodyScoreComparison({
    required this.primary,
    this.current,
    this.currentLabel,
  });

  final BodyScoreSnapshot primary;
  final BodyScoreSnapshot? current;
  final String? currentLabel;

  double? percentChangeFromPrimary() {
    final currentScore = current?.summary.balanceScore;
    final primaryScore = primary.summary.balanceScore;
    if (currentScore == null || primaryScore == 0) return null;
    return ((currentScore - primaryScore) / primaryScore) * 100;
  }
}

/// Whether the Training-balance surface should render the loading skeleton
/// instead of its content.
///
/// Centralised + [visibleForTesting] so the production [build] decision and its
/// guard test share ONE source of truth. The [switchingPeriod] term is the
/// Phase-3 fix: when the user switches period, the synchronous
/// `setState(_selectedPeriod = ...)` flips the build into the new period's
/// branch a frame BEFORE the async recompute repopulates the period-specific
/// fields ([_currentWeekRegions] / [_trendWeeks] / ...). Holding the skeleton
/// while switching prevents that one stale/empty `[]` / `{}` frame. The error
/// state always wins (it has its own render path), so the skeleton is suppressed
/// when [hasError].
@visibleForTesting
bool bodyScoreShowSkeletonForTest({
  required bool switchingPeriod,
  required bool loading,
  required bool hasPrimarySummary,
  required bool hasRegionSummaries,
  required bool hasError,
}) {
  if (hasError) return false;
  if (switchingPeriod) return true;
  return loading && !hasPrimarySummary && !hasRegionSummaries;
}

/// Test-only hook for the [P2] period-switch desync guard: when non-null, the
/// NEXT [_recomputeSummaries] entry throws this error and clears the hook
/// (one-shot). Lets a widget test drive the [_onPeriodChanged] path where the
/// period pref WRITE succeeds but the RECOMPUTE throws - so the test can assert
/// the displayed period and the persisted pref stay consistent - WITHOUT having
/// to craft compute input that happens to blow up. Library-scoped (reachable by
/// the test in this package) and inert in production, where it is never set.
/// Mirrors the existing [bodyScoreShowSkeletonForTest] test seam.
@visibleForTesting
Object? debugBodyScoreRecomputeFailureForTest;

class BodyScoreScreen extends StatefulWidget {
  const BodyScoreScreen({super.key, this.initialSummary});

  final BodyScoreSummary? initialSummary;

  @override
  State<BodyScoreScreen> createState() => _BodyScoreScreenState();
}

class _BodyScoreScreenState extends State<BodyScoreScreen> {
  static const int _firstWeekday = DateTime.monday;
  final _prefs = GetIt.instance<PreferencesService>();
  final _workoutRepository = GetIt.instance<WorkoutRepository>();
  final List<BodyScoreStrategy> _strategies = BodyScoreStrategies.defaults;
  late final BodyScoreStrategy _primaryStrategy = _strategies.first;
  late final Map<String, BodyScoreService> _services = {
    for (final strategy in _strategies)
      strategy.id: BodyScoreService(
        config: BodyScoreConfig(loadStrategy: strategy.loadStrategy),
      ),
  };

  BodyScoreSummary? get _primarySummary => _summaries[_primaryStrategy.id];

  BodyScorePeriod _selectedPeriod = BodyScorePeriod.defaultPeriod;
  BodyScorePeriodWindow? _selectedWindow;
  BodyScoreRegionSort _regionSort = BodyScoreRegionSort.score;
  bool _showActiveOnly = true;

  // Opt-in "Coach explains my numbers" narrative on the training-balance
  // surface. Read once on mount; the note is fetched LAZILY (only when the
  // user taps the affordance) and only when this is true + there are >=2
  // sessions, so it stays entirely off the load path and never narrates a
  // gather-more-data screen.
  bool _coachExplainsOptIn = false;
  final _explainApi = CoachExplainApi();

  bool _loading = true;
  // True for the brief window between selecting a new period and its async
  // recompute landing. While set, the surface renders the loading skeleton
  // instead of the period-specific content - otherwise the synchronous
  // `setState(_selectedPeriod = ...)` would flip the build into (e.g.) the
  // current-week branch one frame BEFORE the recompute repopulates
  // `_currentWeekRegions` / `_trendWeeks`, rendering empty `[]` / `{}` fields
  // for a frame. Cleared by `_recomputeSummaries`'s final setState on success
  // AND by `_onPeriodChanged`'s `finally` on either path - so a throwing prefs
  // write or recompute can never strand the surface in a permanent skeleton.
  bool _switchingPeriod = false;
  // Monotonic switch id. Each `_onPeriodChanged` claims the next id; its
  // `finally` only clears `_switchingPeriod` if it is STILL the latest switch,
  // so a fast double-switch (a second tap landing while the first awaits) does
  // not let the first switch's `finally` drop the skeleton out from under the
  // second's in-flight recompute.
  int _periodSwitchToken = 0;
  String? _error;
  List<WorkoutSession> _sessions = const [];
  Map<String, BodyScoreSummary?> _summaries = const {};
  Map<DisplayRegion, _RegionSummary> _regionSummaries = const {};
  Map<String, Map<MuscleGroup, BodyRegionMetrics>> _heatmapMetricsByStrategy =
      const {};
  Map<MuscleGroup, Map<String, double>> _heatmapExercises = const {};
  // Phase 1/3: RAW summed sets THIS week per muscle group, from the canonical
  // summary's BodyScoreSummary.setsByGroup. Drives the current-week headline
  // figures + cue (raw-vs-target, NOT the paced score).
  Map<MuscleGroup, double> _currentWeekRawSets = const {};
  // Phase 4: TRUE integer physical-set count per display region this week, from
  // BodyScoreSummary.physicalSetsByDisplayRegion. Drives the integer set figure
  // so the cue and the bars never contradict (e.g. 9.5-vs-10 / 10).
  Map<DisplayRegion, int> _currentWeekPhysicalSets = const {};
  // Phase 2/3: the sorted (furthest-behind-first) per-display-region raw
  // sets-this-week vs goal that drive the "This week, by region" IA, and the
  // last-4-ISO-weeks per-region trend points for the demoted trend strip.
  List<CurrentWeekRegionSummary> _currentWeekRegions = const [];
  List<WeeklyRegionPoint> _trendWeeks = const [];
  Map<String, Map<MuscleGroup, double>> _weeklyTargetsByStrategy = const {};
  BodyScoreComparison? _comparison;

  static const Duration _heatmapLookback = Duration(days: 28);

  BodyScoreService get _primaryService => _services[_primaryStrategy.id]!;

  @override
  void initState() {
    super.initState();
    if (widget.initialSummary != null) {
      _summaries = {_primaryStrategy.id: widget.initialSummary};
    }
    _init();
  }

  bool _isTestEnv() {
    final bindingType = WidgetsBinding.instance.runtimeType.toString();
    return bindingType.contains('TestWidgetsFlutterBinding') ||
        bindingType.contains('AutomatedTestWidgetsFlutterBinding');
  }

  Future<void> _init() async {
    // Read the persisted period via the SHARED helper so the one-time
    // current-week migration runs regardless of which surface (this detail or
    // the Home focus card) loads first - the migration is centralised in
    // [readPersistedBodyScorePeriod], never duplicated here.
    _selectedPeriod = await readPersistedBodyScorePeriod(_prefs);
    final coachExplains = await _prefs.getCoachExplainsEnabled();
    if (mounted && coachExplains != _coachExplainsOptIn) {
      setState(() => _coachExplainsOptIn = coachExplains);
    }
    if (!mounted) return;
    await _loadSessions();
  }

  Future<void> _loadSessions() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final startDate = _earliestRequiredStart(now);
      final sessions = await _workoutRepository.getWorkoutSessions(
        startDate: startDate,
      );
      if (!mounted) return;
      final completed = sessions
          .where((session) => session.isCompleted)
          .toList();
      setState(() {
        _sessions = completed;
      });
      await _recomputeSummaries();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load workouts';
        _sessions = const [];
        _regionSummaries = const {};
        _heatmapMetricsByStrategy = const {};
        _weeklyTargetsByStrategy = const {};
        _heatmapExercises = const {};
        _comparison = null;
      });
    }
  }

  DateTime _earliestRequiredStart(DateTime now) {
    final starts = BodyScorePeriod.values
        .map(
          (period) =>
              period.resolve(now, firstWeekday: _firstWeekday).range.start,
        )
        .toList();
    return starts.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  int _recomputeToken = 0;

  Future<void> _recomputeSummaries() async {
    // One-shot test hook: simulate a recompute failure AFTER any prior await
    // (e.g. a successful period pref write) has already landed, so the test can
    // exercise the [P2] write-succeeds/recompute-throws path. No-op in prod.
    final injectedFailure = debugBodyScoreRecomputeFailureForTest;
    if (injectedFailure != null) {
      debugBodyScoreRecomputeFailureForTest = null;
      throw injectedFailure;
    }
    final anchor = DateTime.now();
    final window = _selectedPeriod.resolve(anchor, firstWeekday: _firstWeekday);
    final heatmapRange = rollingRangeToToday(
      days: _heatmapLookback.inDays,
      anchor: anchor,
    );
    _selectedWindow = window;

    // Offload the heavy O(sessions × exercises × sets) summarize work to a
    // background isolate so period changes never jank the UI thread. Tests run
    // it synchronously to stay deterministic (no isolate spawn under pump).
    final token = ++_recomputeToken;
    final request = BodyScoreComputeRequest(
      sessions: _sessions,
      strategyIds: [for (final s in _strategies) s.id],
      windowRange: window.range,
      heatmapRange: heatmapRange,
    );
    final computeResult = _isTestEnv()
        ? runBodyScoreCompute(request)
        : await computeBodyScoreSummaries(request);
    // Drop stale results if a newer recompute started while we were waiting.
    if (!mounted || token != _recomputeToken) return;

    final Map<String, BodyScoreSummary?> summariesByStrategy =
        computeResult.windowSummaries;
    final Map<String, BodyScoreSummary?> heatmapSummaries =
        computeResult.heatmapSummaries;

    // Phase 1/3: for the in-progress current week the headline figures + cue are
    // driven by RAW summed sets vs the weekly goal (NOT the paced score, which
    // inflates a partial week). These come straight from the primary summary's
    // [BodyScoreSummary.setsByGroup] (the canonical raw `baseSet x groupRatio`
    // figure, identical to a separate aggregateForRange pass), so no extra
    // aggregation is needed. Phase 4: the integer physical-set count and the
    // per-region volume bands ride the SAME summary, so the bars can show the
    // true integer count + min/target/max band.
    final BodyScoreSummary? currentWeekSummary =
        _selectedPeriod.isCurrentWeek
        ? summariesByStrategy[_primaryStrategy.id]
        : null;
    final Map<MuscleGroup, double> currentWeekRawSets =
        currentWeekSummary?.setsByGroup ?? const {};
    final Map<DisplayRegion, int> currentWeekPhysicalSets =
        currentWeekSummary?.physicalSetsByDisplayRegion ?? const {};
    final Map<DisplayRegion, RegionVolumeBand> currentWeekBands =
        currentWeekSummary?.bandsByDisplayRegion ?? const {};
    final Map<DisplayRegion, _RegionSummary> summaries = {
      for (final region in DisplayRegion.values)
        region: _RegionSummary(region: region),
    };

    final fallbackExercises = _primaryService.aggregateExerciseVolumeForRange(
      _sessions,
      window.range,
      topExercisesPerRegion: 12,
    );

    for (final strategy in _strategies) {
      final summary = summariesByStrategy[strategy.id];
      if (summary == null) continue;
      final displayPercents = _aggregateDisplayPercents(summary);
      final bool anyLowScore = displayPercents.values
          .where((value) => value > 0)
          .any((value) => value <= 70.0);

      for (final region in DisplayRegion.values) {
        final snapshot = _snapshotForDisplayRegion(
          summary,
          region,
          percentOverride: displayPercents[region] ?? 0.0,
          anyLowScore: anyLowScore,
        );
        summaries[region] = summaries[region]!.addStimulus(
          strategy.id,
          snapshot,
        );

        if (strategy.id == _primaryStrategy.id) {
          // Current week: replace the paced figures with RAW summed sets vs the
          // weekly goal so the headline number, its color, the sort key and the
          // per-region cue all read the SAME raw-vs-target value.
          if (_selectedPeriod.isCurrentWeek) {
            final rawRegion = BodyScoreCoach.currentWeekByDisplayRegion(
              currentWeekRawSets,
              weeklyTargets: summary.weeklyTargets,
              physicalSetsByRegion: currentWeekPhysicalSets,
              bandsByRegion: currentWeekBands,
            )[region];
            if (rawRegion != null) {
              summaries[region] = summaries[region]!.addStimulus(
                strategy.id,
                _withRawCurrentWeek(snapshot, rawRegion),
              );
            }
          }
          final mergedExercises = _mergeTopExercisesForDisplayRegion(
            primary: summary.topExercises,
            fallback: fallbackExercises,
            region: region,
            limit: 12,
          );
          summaries[region] = summaries[region]!.copyWith(
            exercises: [
              for (final entry in mergedExercises.entries)
                _ExerciseContribution(name: entry.key, volume: entry.value),
            ],
            breakdown: _breakdownForDisplayRegion(summary, region),
            lastTrained: snapshot.lastStimulus,
          );
        }
      }
    }

    final Map<String, Map<MuscleGroup, BodyRegionMetrics>> heatmapMetrics = {};
    final Map<String, Map<MuscleGroup, double>> weeklyTargetsByStrategy = {};
    for (final strategy in _strategies) {
      final summary = heatmapSummaries[strategy.id];
      final weeklyTargets =
          summary?.weeklyTargets ?? _services[strategy.id]!.weeklyTargets;
      weeklyTargetsByStrategy[strategy.id] = weeklyTargets;
      heatmapMetrics[strategy.id] = {
        for (final group in MuscleGroup.values)
          group: summary == null
              ? BodyRegionMetrics.zero
              : BodyRegionMetrics(
                  volume: summary.ewma7[group] ?? 0,
                  sets: summary.regionTotals[group] ?? 0,
                  minutes: 0,
                ),
      };
    }

    final exercises = _primaryService.aggregateExerciseVolumeForRange(
      _sessions,
      heatmapRange,
      topExercisesPerRegion: 4,
    );

    final comparison = _buildComparison(
      anchor: anchor,
      window: window,
      primary: summariesByStrategy[_primaryStrategy.id],
    );

    // Phase 2: the sorted (furthest-behind first) per-display-region raw
    // sets-vs-goal list the "This week, by region" IA renders. Built from the
    // SAME raw-vs-target API the Phase 1 cue uses so every figure reconciles.
    final primaryWeeklyTargets =
        summariesByStrategy[_primaryStrategy.id]?.weeklyTargets ??
        _primaryService.weeklyTargets;
    final currentWeekRegions = _selectedPeriod.isCurrentWeek
        ? _sortedCurrentWeekRegions(
            currentWeekRawSets,
            primaryWeeklyTargets,
            physicalSetsByRegion: currentWeekPhysicalSets,
            bandsByRegion: currentWeekBands,
          )
        : const <CurrentWeekRegionSummary>[];

    // Phase 3: the last-4-ISO-weeks per-region trend points (rightmost = this
    // week, in progress) for the demoted trend strip. The in-progress week's
    // bar reuses the deduped per-display-region counts the isolate ALREADY
    // computed for the headline ([currentWeekPhysicalSets]) - byte-identical to
    // the headline window - so the rightmost bar matches the headline by
    // construction, with no redundant main-thread recompute of that week.
    final trendWeeks = _selectedPeriod.isCurrentWeek
        ? _buildTrendWeeks(
            anchor,
            primaryWeeklyTargets,
            inProgressPhysicalSets: currentWeekPhysicalSets,
          )
        : const <WeeklyRegionPoint>[];

    if (!mounted) return;
    setState(() {
      _summaries = summariesByStrategy;
      _regionSummaries = summaries;
      _heatmapMetricsByStrategy = heatmapMetrics;
      _weeklyTargetsByStrategy = weeklyTargetsByStrategy;
      _heatmapExercises = {
        for (final entry in exercises.entries)
          entry.key: Map<String, double>.from(entry.value),
      };
      _comparison = comparison;
      _currentWeekRawSets = currentWeekRawSets;
      _currentWeekPhysicalSets = currentWeekPhysicalSets;
      _currentWeekRegions = currentWeekRegions;
      _trendWeeks = trendWeeks;
      // The period-specific fields above now match _selectedPeriod, so the
      // surface can render the switched-to period without a stale/empty frame.
      _switchingPeriod = false;
    });
  }

  /// Phase 2: the sorted (furthest-behind first) per-display-region raw
  /// sets-vs-goal summaries the "This week, by region" IA renders. Targeted,
  /// non-Other regions only; ties broken by the bigger raw gap then by name so
  /// the order is deterministic for goldens/tests.
  static List<CurrentWeekRegionSummary> _sortedCurrentWeekRegions(
    Map<MuscleGroup, double> rawSetsByGroup,
    Map<MuscleGroup, double> weeklyTargets, {
    Map<DisplayRegion, int> physicalSetsByRegion = const {},
    Map<DisplayRegion, RegionVolumeBand> bandsByRegion = const {},
  }) {
    final byRegion = BodyScoreCoach.currentWeekByDisplayRegion(
      rawSetsByGroup,
      weeklyTargets: weeklyTargets,
      physicalSetsByRegion: physicalSetsByRegion,
      bandsByRegion: bandsByRegion,
    );
    final regions = byRegion.values
        .where((r) => r.region != DisplayRegion.other)
        .where((r) => r.weeklyTarget > 0)
        .toList(growable: false);
    // Sort by the DISPLAYED percent / gap (what the bars + do-next actually show)
    // so the largest DISPLAYED gap is recommended first: a 5 / 10 primary ranks
    // ahead of a 9 / 10 secondary-heavy region. When physical counts are absent
    // (Phase 1 path) [displayPercent] reduces to the raw percent, so this is a
    // no-op there. Ties broken by the bigger displayed gap, then by name for a
    // deterministic order for goldens/tests.
    final sorted = [...regions]..sort((a, b) {
      final cmp = a.displayPercent.compareTo(b.displayPercent);
      if (cmp != 0) return cmp;
      final gapCmp = b.displayGap.compareTo(a.displayGap);
      if (gapCmp != 0) return gapCmp;
      return a.region.label.compareTo(b.region.label);
    });
    return sorted;
  }

  /// Phase 3: the last four ISO weeks (oldest -> newest; the last entry is the
  /// in-progress current week) summed to display regions, for the trend strip.
  ///
  /// Each week's per-region figure is the SAME DEDUPED integer physical-set
  /// basis the headline bars use ([BodyScoreSummary.physicalSetsByDisplayRegion]
  /// - a set training two muscles in one display region counts ONCE), computed
  /// per week range via [BodyScoreService.summarize]. The old path summed the
  /// raw fractional [aggregateForRange] `sets` (`baseSet x groupRatio`, which
  /// double-counts a compound set across the muscles it trains), so the same
  /// in-progress week could read e.g. Legs 16 / 14 (emerald, met) in the strip
  /// while the headline showed Legs 8 / 10 (amber, under). Reading the deduped
  /// physical count here keeps every trend week internally consistent AND makes
  /// the rightmost (in-progress) bar match the headline exactly.
  ///
  /// Perf: the in-progress (i=0) week reuses [inProgressPhysicalSets] - the
  /// deduped counts the isolate ALREADY computed for the headline window - so
  /// the rightmost bar equals the headline by construction with NO redundant
  /// recompute. The 3 CLOSED weeks use the LIGHTWEIGHT cache-backed
  /// [BodyScoreService.physicalSetsByDisplayRegionForRange] tally (only the
  /// deduped per-region accumulation) instead of a full [summarize] pass, so
  /// the trend no longer runs the heavy EWMA / timeline / score work it never
  /// reads on the UI thread.
  List<WeeklyRegionPoint> _buildTrendWeeks(
    DateTime anchor,
    Map<MuscleGroup, double> weeklyTargets, {
    required Map<DisplayRegion, int> inProgressPhysicalSets,
  }) {
    final Map<DisplayRegion, double> targetsByRegion = {
      for (final region in DisplayRegion.values) region: 0.0,
    };
    for (final group in MuscleGroup.values) {
      final target = weeklyTargets[group] ?? 0.0;
      if (target <= 0) continue;
      targetsByRegion[group.displayRegion] =
          (targetsByRegion[group.displayRegion] ?? 0.0) + target;
    }

    final thisWeekStart = startOfWeek(anchor, firstWeekday: _firstWeekday);
    final weeks = <WeeklyRegionPoint>[];
    const int weekCount = 4;
    for (var i = weekCount - 1; i >= 0; i--) {
      final start = thisWeekStart.subtract(Duration(days: 7 * i));
      final bool inProgress = i == 0;
      // The in-progress week runs start->now; closed weeks run the full Mon->Sun.
      final end = inProgress
          ? anchor
          : start
                .add(const Duration(days: 7))
                .subtract(const Duration(microseconds: 1));
      // Same DEDUPED per-display-region physical-set basis the headline rides.
      // In-progress week: reuse the isolate's already-computed headline counts
      // (byte-identical window) so the rightmost bar == headline with no
      // recompute. Closed weeks: the lightweight cache-backed per-range tally -
      // just the deduped accumulation, NOT the heavy EWMA/timeline/score work.
      final Map<DisplayRegion, int> physicalByRegion = inProgress
          ? inProgressPhysicalSets
          : _primaryService.physicalSetsByDisplayRegionForRange(
              _sessions,
              DateTimeRange(start: start, end: end),
            );
      final Map<DisplayRegion, double> setsByRegion = {
        for (final region in DisplayRegion.values)
          region: (targetsByRegion[region] ?? 0.0) > 0
              ? (physicalByRegion[region] ?? 0).toDouble()
              : 0.0,
      };
      weeks.add(
        WeeklyRegionPoint(
          label: DateFormat('MMM d').format(start),
          setsByRegion: setsByRegion,
          targetsByRegion: targetsByRegion,
          inProgress: inProgress,
        ),
      );
    }
    return weeks;
  }

  /// Rebuilds a region snapshot so its displayed figures are RAW current-week
  /// sets vs the weekly goal (Phase 1 headline), not the paced period figures.
  /// [windowVolume] is preserved (it drives the active/recency filters), so a
  /// region trained this week still passes the "recently trained" gate.
  static _RegionStimulusSnapshot _withRawCurrentWeek(
    _RegionStimulusSnapshot base,
    CurrentWeekRegionSummary raw,
  ) {
    // The collapsed "Trends & detail" / "Muscle groups" detail rows derive their
    // shown value (`ewma7.round()`), their on/under state and the "Add about N
    // sets" copy from THIS snapshot. They must read the SAME basis as the
    // headline bars / do-next, which key off [CurrentWeekRegionSummary.displaySets]
    // / [displayGap] (the rounded display figure - the true physical-set count
    // when present, else the rounded raw figure). Plumbing the raw fractional
    // `rawSets` / raw gap here instead let secondary-heavy work read e.g. 9 / 10
    // in the headline but 5 / 10 + "Add about 5 sets" in the detail row for the
    // SAME region. Feeding [displaySets] / [displayGap] keeps both telling one
    // story. On the non-current-week / Home-focus path physical counts are
    // absent, so [displaySets]/[displayGap] reduce to `rawSets.round()` / the raw
    // gap and those surfaces are unchanged.
    return _RegionStimulusSnapshot(
      score: raw.displayPercent,
      share: base.share,
      ewma7: raw.displaySets.toDouble(),
      ewma28: base.ewma28,
      recommendedSets: raw.displayGap.toDouble(),
      lastStimulus: base.lastStimulus,
      trend: base.trend,
      weeklyTarget: raw.weeklyTarget,
      isDominant: false,
      isUnderTarget: !raw.isMet,
      windowVolume: base.windowVolume,
    );
  }

  BodyScoreComparison? _buildComparison({
    required DateTime anchor,
    required BodyScorePeriodWindow window,
    required BodyScoreSummary? primary,
  }) {
    if (primary == null) return null;
    final primarySnapshot = BodyScoreSnapshot(
      summary: primary,
      range: window.range,
      label: window.period.label,
    );
    DateTimeRange? currentRange;
    String? currentLabel;
    switch (window.period) {
      case BodyScorePeriod.currentWeek:
        // The current week IS the in-progress period - there is no separate
        // "this week so far" comparison to draw against it.
        break;
      case BodyScorePeriod.lastFullWeek:
        currentRange = currentWeekToNow(anchor, firstWeekday: _firstWeekday);
        currentLabel = 'This week so far';
        break;
      case BodyScorePeriod.lastFullMonth:
        currentRange = currentMonthToNow(anchor);
        currentLabel = 'This month so far';
        break;
      case BodyScorePeriod.last4FullWeeks:
        break;
    }

    BodyScoreSnapshot? currentSnapshot;
    if (currentRange != null) {
      final currentSummary = _primaryService.summarize(
        _sessions,
        range: currentRange,
      );
      if (currentSummary != null) {
        currentSnapshot = BodyScoreSnapshot(
          summary: currentSummary,
          range: currentRange,
          label: currentLabel ?? 'Current period',
          isPartial: true,
        );
      }
    }

    return BodyScoreComparison(
      primary: primarySnapshot,
      current: currentSnapshot,
      currentLabel: currentLabel,
    );
  }

  static Iterable<MuscleGroup> _mappableGroupsFor(DisplayRegion region) {
    return MuscleGroup.values.where((group) {
      if (group == MuscleGroup.other || group == MuscleGroup.fullBody) {
        return false;
      }
      return group.displayRegion == region;
    });
  }

  static double _periodWeeklyEquivalentForGroup(
    BodyScoreSummary summary,
    MuscleGroup group,
  ) {
    return summary.weeklyEquivalentVolumes[group] ?? 0.0;
  }

  static Map<DisplayRegion, double> _aggregateDisplayPercents(
    BodyScoreSummary summary,
  ) {
    final Map<DisplayRegion, double> aggregatedTotals = {
      for (final region in DisplayRegion.values) region: 0.0,
    };
    final Map<DisplayRegion, double> aggregatedTargets = {
      for (final region in DisplayRegion.values) region: 0.0,
    };

    for (final group in MuscleGroup.values) {
      final region = group.displayRegion;
      final target = summary.weeklyTargets[group] ?? 0.0;
      if (target <= 0) continue;
      aggregatedTotals[region] =
          (aggregatedTotals[region] ?? 0.0) +
          _periodWeeklyEquivalentForGroup(summary, group);
      aggregatedTargets[region] = (aggregatedTargets[region] ?? 0.0) + target;
    }

    return {
      for (final region in DisplayRegion.values)
        region: (aggregatedTargets[region] ?? 0.0) > 0.0
            ? (aggregatedTotals[region]! / aggregatedTargets[region]!) * 100.0
            : 0.0,
    };
  }

  static _RegionStimulusSnapshot _snapshotForDisplayRegion(
    BodyScoreSummary summary,
    DisplayRegion region, {
    required double percentOverride,
    required bool anyLowScore,
  }) {
    double ewma7 = 0.0;
    double ewma28 = 0.0;
    double share = 0.0;
    double weeklyTarget = 0.0;
    double recommendedSets = 0.0;
    double trend = 0.0;
    double windowVolume = 0.0;
    DateTime? lastStimulus;

    for (final group in MuscleGroup.values) {
      if (group.displayRegion != region) continue;
      if ((summary.weeklyTargets[group] ?? 0.0) <= 0.0) continue;
      ewma7 += _periodWeeklyEquivalentForGroup(summary, group);
      ewma28 += summary.ewma28[group] ?? 0.0;
      share += summary.regionShares[group] ?? 0.0;
      weeklyTarget += summary.weeklyTargets[group] ?? 0.0;
      recommendedSets += summary.recommendedSets[group] ?? 0.0;
      trend += summary.regionTrends[group] ?? 0.0;
      windowVolume += summary.regionTotals[group] ?? 0.0;
      final candidate = summary.lastStimulus[group];
      if (candidate == null) continue;
      if (lastStimulus == null || candidate.isAfter(lastStimulus)) {
        lastStimulus = candidate;
      }
    }

    final score = percentOverride;
    return _RegionStimulusSnapshot(
      score: score,
      share: share,
      ewma7: ewma7,
      ewma28: ewma28,
      recommendedSets: recommendedSets,
      lastStimulus: lastStimulus,
      trend: trend,
      weeklyTarget: weeklyTarget,
      isDominant: score >= 140.0 && anyLowScore,
      isUnderTarget: score < 100.0,
      windowVolume: windowVolume,
    );
  }

  static Map<String, double> _mergeTopExercisesForDisplayRegion({
    required Map<MuscleGroup, Map<String, double>> primary,
    required Map<MuscleGroup, Map<String, double>> fallback,
    required DisplayRegion region,
    required int limit,
  }) {
    final Map<String, double> merged = {};

    for (final group in MuscleGroup.values.where(
      (g) => g.displayRegion == region,
    )) {
      final exercises = primary[group] ?? fallback[group] ?? const {};
      for (final entry in exercises.entries) {
        if (entry.value <= 0) continue;
        merged.update(
          entry.key,
          (value) => value + entry.value,
          ifAbsent: () => entry.value,
        );
      }
    }

    final sorted = merged.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map<String, double>.fromEntries(sorted.take(limit));
  }

  static List<_MuscleGroupBreakdown> _breakdownForDisplayRegion(
    BodyScoreSummary summary,
    DisplayRegion region,
  ) {
    final List<_MuscleGroupBreakdown> breakdown = [
      for (final group in _mappableGroupsFor(region))
        if ((summary.weeklyTargets[group] ?? 0.0) > 0.0)
          _MuscleGroupBreakdown(
            group: group,
            score: summary.regionScores[group] ?? 0.0,
            ewma7: summary.ewma7[group] ?? 0.0,
            weeklyTarget: summary.weeklyTargets[group] ?? 0.0,
            recommendedSets: summary.recommendedSets[group] ?? 0.0,
            lastStimulus: summary.lastStimulus[group],
          ),
    ];
    breakdown.sort((a, b) => a.score.compareTo(b.score));
    return breakdown;
  }

  List<_RegionSummary> get _visibleSummaries {
    final now = DateTime.now();
    final summaries = _regionSummaries.values.where((summary) {
      if (summary.region == DisplayRegion.other) return false;
      final snapshot = summary.stimulusFor(_primaryStrategy.id);
      return isRegionVisibleForTest(
        hasSnapshot: snapshot != null,
        weeklyTarget: snapshot?.weeklyTarget ?? 0.0,
        isUnderTarget: snapshot?.isUnderTarget ?? false,
        windowVolume: snapshot?.windowVolume ?? 0.0,
        lastStimulus: snapshot?.lastStimulus,
        showActiveOnly: _showActiveOnly,
        isCurrentWeek: _selectedPeriod.isCurrentWeek,
        now: now,
      );
    }).toList();

    switch (_regionSort) {
      case BodyScoreRegionSort.score:
        summaries.sort((a, b) {
          final aSnapshot = a.stimulusFor(_primaryStrategy.id);
          final bSnapshot = b.stimulusFor(_primaryStrategy.id);
          final aScore = aSnapshot?.score ?? double.infinity;
          final bScore = bSnapshot?.score ?? double.infinity;
          final cmp = aScore.compareTo(bScore);
          if (cmp != 0) return cmp;
          final aDeficit = aSnapshot?.recommendedSets ?? 0;
          final bDeficit = bSnapshot?.recommendedSets ?? 0;
          final deficitCmp = bDeficit.compareTo(aDeficit);
          if (deficitCmp != 0) return deficitCmp;
          final aShare = aSnapshot?.share ?? 0;
          final bShare = bSnapshot?.share ?? 0;
          return bShare.compareTo(aShare);
        });
        break;
      case BodyScoreRegionSort.addSets:
        summaries.sort((a, b) {
          final aSnapshot = a.stimulusFor(_primaryStrategy.id);
          final bSnapshot = b.stimulusFor(_primaryStrategy.id);
          final aDeficit = aSnapshot?.recommendedSets ?? 0;
          final bDeficit = bSnapshot?.recommendedSets ?? 0;
          final cmp = bDeficit.compareTo(aDeficit);
          if (cmp != 0) return cmp;
          final aScore = aSnapshot?.score ?? double.infinity;
          final bScore = bSnapshot?.score ?? double.infinity;
          return aScore.compareTo(bScore);
        });
        break;
      case BodyScoreRegionSort.stimulus:
        summaries.sort((a, b) {
          final aShare = a.stimulusFor(_primaryStrategy.id)?.share ?? 0;
          final bShare = b.stimulusFor(_primaryStrategy.id)?.share ?? 0;
          final cmp = bShare.compareTo(aShare);
          if (cmp != 0) return cmp;
          final aScore = a.stimulusFor(_primaryStrategy.id)?.score ?? 0;
          final bScore = b.stimulusFor(_primaryStrategy.id)?.score ?? 0;
          return aScore.compareTo(bScore);
        });
        break;
      case BodyScoreRegionSort.recency:
        summaries.sort((a, b) {
          final aLastStimulus = a
              .stimulusFor(_primaryStrategy.id)
              ?.lastStimulus;
          final bLastStimulus = b
              .stimulusFor(_primaryStrategy.id)
              ?.lastStimulus;
          final aDate = aLastStimulus ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = bLastStimulus ?? DateTime.fromMillisecondsSinceEpoch(0);
          final cmp = aDate.compareTo(bDate);
          if (cmp != 0) return cmp;
          final aScore = a.stimulusFor(_primaryStrategy.id)?.score ?? 0;
          final bScore = b.stimulusFor(_primaryStrategy.id)?.score ?? 0;
          return aScore.compareTo(bScore);
        });
        break;
    }
    return summaries;
  }

  Future<void> _onPeriodChanged(BodyScorePeriod period) async {
    if (_selectedPeriod == period) return;
    final previousPeriod = _selectedPeriod;
    // Claim this switch. A later switch bumps the token; this switch's `finally`
    // then knows it is stale and leaves `_switchingPeriod` for the newer switch
    // to clear, so a fast double-tap never drops the skeleton mid-recompute.
    final switchToken = ++_periodSwitchToken;
    // Flip the period AND raise the switching flag in the SAME frame so the
    // build never renders the new period's branch against the old period's
    // (now mismatched) derived fields. The skeleton holds until either the
    // awaited recompute's setState lands (success) or the `finally` runs
    // (error) - it can no longer be stranded on forever.
    setState(() {
      _selectedPeriod = period;
      _switchingPeriod = true;
      // Clear any prior error so this switch starts from a clean slate; if it
      // throws below we re-raise the error UI in the catch.
      _error = null;
    });
    // Did the persisted pref actually take the NEW period? Flipped true the
    // instant `setRawString` returns. The catch reads this to snap the DISPLAYED
    // `_selectedPeriod` onto whatever is ACTUALLY persisted, so the in-memory
    // selection and the stored pref can never diverge - which would otherwise
    // let the next app load silently jump to a period the user was just told
    // failed to switch (the [P2] fix-introduced desync).
    var persistedNew = false;
    try {
      await _prefs.setRawString(bodyScorePeriodPrefKey, period.id);
      persistedNew = true;
      await _recomputeSummaries();
    } catch (_) {
      if (!mounted || switchToken != _periodSwitchToken) return;
      // The prefs write or the recompute threw. Surface the normal error UI
      // (which does NOT depend on the period-specific derived fields) instead
      // of leaving a permanent skeleton, and pin the displayed period to the
      // value that is ACTUALLY persisted so the two never desync:
      //   - persistedNew: the write SUCCEEDED (pref = new period) and only the
      //     recompute threw. KEEP `_selectedPeriod = period` so the displayed
      //     period matches the stored pref; the error UI lets the user retry the
      //     recompute for the (already-persisted) new period. Snapping back here
      //     would leave the pref on the new period while the screen showed the
      //     old one - the next load would then jump to the new period.
      //   - !persistedNew: the write itself threw, so the pref still holds the
      //     previous period. Snap `_selectedPeriod` back to `previousPeriod` so
      //     the display and the pref are consistently on the previous period.
      setState(() {
        if (!persistedNew) {
          _selectedPeriod = previousPeriod;
        }
        _error = 'Unable to switch period';
      });
    } finally {
      // Only the latest switch clears the flag; a stale (superseded) switch
      // leaves it for the newer in-flight switch to clear on its own terminal
      // setState. On success the recompute already cleared it; setting false
      // again here is a harmless idempotent no-op.
      if (mounted && switchToken == _periodSwitchToken && _switchingPeriod) {
        setState(() => _switchingPeriod = false);
      }
    }
  }

  void _onViewWorkouts(DisplayRegion region) {
    final router = GoRouter.of(context);
    final regionParam = Uri.encodeComponent(region.key);
    final rangeDays =
        (_selectedWindow ??
                _selectedPeriod.resolve(
                  DateTime.now(),
                  firstWeekday: _firstWeekday,
                ))
            .dayCount;
    // History is a TAB branch — switch the branch (go), keeping the region /
    // range query so the tab opens filtered. Pushing it would leave a stray
    // back button and the bottom nav stuck on Progress.
    router.go('/history?region=$regionParam&range=$rangeDays');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Shared predicate (see [bodyScoreShowSkeletonForTest]) so the production
    // skeleton decision and its guard test never drift. The `switchingPeriod`
    // term is the Phase-3 fix: it holds the skeleton across the async recompute
    // when switching periods, so the surface never renders the switched-to
    // period's branch against the previous period's (now empty) derived fields.
    final showSpinner = bodyScoreShowSkeletonForTest(
      switchingPeriod: _switchingPeriod,
      loading: _loading,
      hasPrimarySummary: _primarySummary != null,
      hasRegionSummaries: _regionSummaries.isNotEmpty,
      hasError: _error != null,
    );

    return MainScaffold(
      appBar: AppBar(
        title: const Text('Training balance'),
        automaticallyImplyLeading: false,
        // Adaptive leading: a back button when pushed (the normal case, from
        // Progress), the account avatar at a root. Consistent with every other
        // screen's app bar.
        leading: const HustlMenuButton(),
      ),
      child: showSpinner
          ? const HustlInlineSkeleton()
          : RefreshIndicator(
              onRefresh: _loadSessions,
              child: ListView(
                padding: AppSpacing.screen,
                physics: const AlwaysScrollableScrollPhysics(),
                children: [_buildResponsiveBody(theme)],
              ),
            ),
    );
  }

  /// Picks the single-column (phone / tablet portrait) or two-column (wide)
  /// arrangement. Below 900 the original single-column sequence is emitted
  /// unchanged; at/above 880 the overview hero leads a left column while the
  /// heat map, region controls and region rows flow into a right column.
  Widget _buildResponsiveBody(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final selectedWindow =
            _selectedWindow ??
            _selectedPeriod.resolve(
              DateTime.now(),
              firstWeekday: _firstWeekday,
            );

        // Try the two-column split only on wide viewports AND only when there
        // is genuine detail content (heat map / regions / callout) to fill the
        // right pane. Error and empty states have no detail content, so they
        // fall through to the single-column path below and render unchanged.
        // The current-week IA is a full-width headline (status line + bars +
        // do-next), so it always uses the single-column path; the two-column
        // split is reserved for the closed-period radar-led layout.
        if (constraints.maxWidth >= 880 &&
            _error == null &&
            !_selectedPeriod.isCurrentWeek) {
          final left = _overviewBlocks(theme, selectedWindow);
          final right = _detailBlocks(theme, selectedWindow);
          // Need a hero for the left column AND detail content for the right —
          // otherwise an empty pane would look broken, so use one column.
          if (left.isNotEmpty && right.isNotEmpty) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: left,
                  ),
                ),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: right,
                  ),
                ),
              ],
            );
          }
        }

        // Single column — phones, tablet portrait, and any wide view with no
        // detail content. Byte-for-byte the original sequence.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _buildContent(theme),
        );
      },
    );
  }

  List<Widget> _buildContent(ThemeData theme) {
    final selectedWindow =
        _selectedWindow ??
        _selectedPeriod.resolve(DateTime.now(), firstWeekday: _firstWeekday);
    final widgets = <Widget>[];

    if (_error != null) {
      widgets.add(_ErrorMessage(message: _error!, onRetry: _loadSessions));
      return widgets;
    }

    // Phase 2: for the in-progress current week the "This week, by region" IA is
    // the HEADLINE - status line + region bars + do-next answer "am I balanced?"
    // and "what do I do?" BEFORE any chart. The radar / heat map / 0-100 score /
    // 27-muscle granularity are demoted into a collapsible "Trends & detail".
    if (_selectedPeriod.isCurrentWeek) {
      return _buildCurrentWeekContent(theme, selectedWindow);
    }

    final primarySummary = _primarySummary;
    if (primarySummary != null) {
      widgets.add(
        _buildOverviewCard(theme, primarySummary, selectedWindow, _comparison),
      );
      // Hairline section break between the flat overview and the heat map.
      widgets.add(const Divider());
    }

    if (_heatmapMetricsByStrategy.isNotEmpty) {
      widgets.add(_buildHeatMapCard());
      widgets.add(const SizedBox(height: AppSpacing.x2));
    }

    final otherSummary = _regionSummaries[DisplayRegion.other];
    final showOtherCallout = otherSummary?.hasOtherCallout ?? false;
    final summaries = _visibleSummaries;
    final hasRegionTiles = summaries.isNotEmpty;

    if (!hasRegionTiles && !showOtherCallout) {
      widgets.add(_EmptyState(rangeLabel: selectedWindow.labelWithDate));
      return widgets;
    }

    if (hasRegionTiles) {
      widgets.add(_buildRegionControls(theme));
      widgets.add(const SizedBox(height: AppSpacing.x2));
    }

    if (showOtherCallout) {
      widgets.add(
        _OtherRegionCallout(
          exercises: otherSummary!.exercises.take(12).toList(growable: false),
        ),
      );
      widgets.add(const SizedBox(height: AppSpacing.x2));
    }

    // Wave G §12.1: region rows are FLAT — separated by hairline dividers.
    if (hasRegionTiles) {
      widgets.addAll(_buildRegionRows(summaries));
    }

    widgets.add(const SizedBox(height: AppSpacing.x3));
    return widgets;
  }

  /// Phase 2/3: the current-week layout - the "This week, by region" headline IA
  /// up top, then the demoted "Trends & detail" collapsible (radar / heat map /
  /// 0-100 evenness / 27-muscle granularity + the 4-week trend strip).
  List<Widget> _buildCurrentWeekContent(
    ThemeData theme,
    BodyScorePeriodWindow selectedWindow,
  ) {
    final widgets = <Widget>[];
    final hasIa = _currentWeekRegions.isNotEmpty;

    // Keep the period selector reachable at the top - the old overview header
    // that carried it is now demoted into the "Trends & detail" collapsible.
    widgets.add(
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              'This week, by region',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _PeriodPillSelector(
            selected: _selectedPeriod,
            available: BodyScorePeriod.values,
            onSelected: _onPeriodChanged,
          ),
        ],
      ),
    );
    widgets.add(const SizedBox(height: AppSpacing.x2));

    // No targeted region trained this week yet AND no detail to show -> empty.
    final summaries = _visibleSummaries;
    final otherSummary = _regionSummaries[DisplayRegion.other];
    final showOtherCallout = otherSummary?.hasOtherCallout ?? false;
    if (!hasIa && summaries.isEmpty && !showOtherCallout) {
      widgets.add(_EmptyState(rangeLabel: selectedWindow.labelWithDate));
      return widgets;
    }

    if (hasIa) {
      widgets.add(
        ThisWeekByRegion(
          dayOfWeek: currentWeekDayOf(selectedWindow.range),
          regions: _currentWeekRegions,
          sessionCount: _primarySummary?.sessionCount ?? 0,
          onTapRegion: _onViewWorkouts,
          onDoNext: _onViewWorkouts,
        ),
      );
      widgets.add(const SizedBox(height: AppSpacing.x3));
    }

    // Everything chart-led is demoted below the fold into one collapsible.
    final detail = _trendsAndDetailChildren(theme, selectedWindow);
    if (detail.isNotEmpty) {
      widgets.add(_TrendsAndDetailSection(children: detail));
      widgets.add(const SizedBox(height: AppSpacing.x3));
    }
    return widgets;
  }

  /// The children of the demoted "Trends & detail" collapsible: the 4-week trend
  /// strip first (Phase 3), then the radar / 0-100 evenness overview card, the
  /// heat map, and the flat 27-muscle region rows.
  List<Widget> _trendsAndDetailChildren(
    ThemeData theme,
    BodyScorePeriodWindow selectedWindow,
  ) {
    final widgets = <Widget>[];

    if (_trendWeeks.isNotEmpty) {
      widgets.add(FourWeekTrendStrip(weeks: _trendWeeks));
      widgets.add(const Divider(height: AppSpacing.x4));
    }

    final primarySummary = _primarySummary;
    if (primarySummary != null) {
      widgets.add(
        _buildOverviewCard(
          theme,
          primarySummary,
          selectedWindow,
          _comparison,
          evennessContext: true,
        ),
      );
      widgets.add(const Divider());
    }

    if (_heatmapMetricsByStrategy.isNotEmpty) {
      widgets.add(_buildHeatMapCard());
      widgets.add(const SizedBox(height: AppSpacing.x2));
    }

    final otherSummary = _regionSummaries[DisplayRegion.other];
    final showOtherCallout = otherSummary?.hasOtherCallout ?? false;
    final summaries = _visibleSummaries;
    final hasRegionTiles = summaries.isNotEmpty;

    if (hasRegionTiles) {
      widgets.add(_buildRegionControls(theme));
      widgets.add(const SizedBox(height: AppSpacing.x2));
    }

    if (showOtherCallout) {
      widgets.add(
        _OtherRegionCallout(
          exercises: otherSummary!.exercises.take(12).toList(growable: false),
        ),
      );
      widgets.add(const SizedBox(height: AppSpacing.x2));
    }

    if (hasRegionTiles) {
      widgets.addAll(_buildRegionRows(summaries));
    }

    return widgets;
  }

  /// Wide left column: the overview hero (score ring + balance trend + radar).
  /// Mirrors the leading blocks of the single-column layout.
  List<Widget> _overviewBlocks(
    ThemeData theme,
    BodyScorePeriodWindow selectedWindow,
  ) {
    final widgets = <Widget>[];
    final primarySummary = _primarySummary;
    if (primarySummary != null) {
      widgets.add(
        _buildOverviewCard(theme, primarySummary, selectedWindow, _comparison),
      );
    }
    return widgets;
  }

  /// Wide right column: heat map, region controls, the Other callout, and the
  /// flat region rows. Mirrors the trailing blocks of the single-column layout.
  List<Widget> _detailBlocks(
    ThemeData theme,
    BodyScorePeriodWindow selectedWindow,
  ) {
    final widgets = <Widget>[];

    if (_heatmapMetricsByStrategy.isNotEmpty) {
      widgets.add(_buildHeatMapCard());
      widgets.add(const SizedBox(height: AppSpacing.x2));
    }

    final otherSummary = _regionSummaries[DisplayRegion.other];
    final showOtherCallout = otherSummary?.hasOtherCallout ?? false;
    final summaries = _visibleSummaries;
    final hasRegionTiles = summaries.isNotEmpty;

    if (hasRegionTiles) {
      widgets.add(_buildRegionControls(theme));
      widgets.add(const SizedBox(height: AppSpacing.x2));
    }

    if (showOtherCallout) {
      widgets.add(
        _OtherRegionCallout(
          exercises: otherSummary!.exercises.take(12).toList(growable: false),
        ),
      );
      widgets.add(const SizedBox(height: AppSpacing.x2));
    }

    if (hasRegionTiles) {
      widgets.addAll(_buildRegionRows(summaries));
    }

    if (widgets.isNotEmpty) {
      widgets.add(const SizedBox(height: AppSpacing.x3));
    }
    return widgets;
  }

  // Wave G §12.1: region rows are FLAT — separated by hairline dividers.
  List<Widget> _buildRegionRows(List<_RegionSummary> summaries) {
    final rows = <Widget>[const SectionHeader('Muscle groups')];
    for (var i = 0; i < summaries.length; i++) {
      if (i > 0) rows.add(const Divider());
      rows.add(
        _RegionTile(
          overallSummary: _primarySummary,
          summary: summaries[i],
          primaryStrategy: _primaryStrategy,
          isCurrentWeek: _selectedPeriod.isCurrentWeek,
          onViewWorkouts: summaries[i].hasWorkouts
              ? () => _onViewWorkouts(summaries[i].region)
              : null,
        ),
      );
    }
    return rows;
  }

  /// Builds the PII-free, pre-rounded `TrainingFacts` payload the shared
  /// "explain any number" endpoint expects for the `training` domain, from the
  /// in-hand [summary] + [cue]. Numbers are rounded HERE (the contract says the
  /// model receives values, never formulas), and only the on-screen display
  /// signals travel — no raw sessions, no PII.
  Map<String, dynamic> _buildTrainingFacts(
    BodyScoreSummary summary,
    BodyScoreCoachingCue cue,
    BodyScorePeriodWindow window,
  ) {
    // The six display-region coverage percents, the same values the radar /
    // region rows render. For the in-progress current week the cue + bars are
    // driven by the RAW summed-sets-vs-target basis, NOT the paced (vol/days)*7
    // weekly equivalent (see [_trainingFactsRegions]).
    final regions = _trainingFactsRegions(
      summary: summary,
      isCurrentWeek: _selectedPeriod.isCurrentWeek,
      currentWeekRawSets: _currentWeekRawSets,
    );

    // The lagging region the cue is about; the dominant (highest-vs-goal) region.
    final lagging = cue.primaryRegion?.label;
    final dominant = summary.dominantRegion.displayRegion == DisplayRegion.other
        ? null
        : summary.dominantRegion.displayRegion.label;

    final cueDetail = cue.detail ?? '';

    return {
      'balanceScore': summary.balanceScore.round(),
      'regions': regions,
      'laggingRegion': lagging,
      'dominantRegion': dominant,
      'cueHeadline': cue.headline,
      'cueDetail': cueDetail,
      'setCount': cue.setCount,
      'sessionCount': summary.sessionCount,
      'windowDays': summary.windowDays,
      'windowLabel': window.period.label,
    };
  }

  /// The per-display-region coverage percents the coach-explain `regions` payload
  /// cites, pre-rounded. The basis MUST match what the user sees on screen: for
  /// the in-progress current week the cue + region bars read the RAW summed-sets-
  /// vs-target basis ([BodyScoreCoach.currentWeekByDisplayRegion] over
  /// [currentWeekRawSets]), so the explain facts read the SAME raw basis there,
  /// not the paced (vol/days)*7 [_aggregateDisplayPercents] weekly equivalent
  /// (which inflates an in-progress week and would let the facts call a region
  /// over 100% while the visible cue says "add sets"). Closed periods keep the
  /// paced basis the rest of the closed-period surface uses.
  static List<Map<String, dynamic>> _trainingFactsRegions({
    required BodyScoreSummary summary,
    required bool isCurrentWeek,
    required Map<MuscleGroup, double> currentWeekRawSets,
  }) {
    final Map<DisplayRegion, double> percents = isCurrentWeek
        ? {
            for (final entry in BodyScoreCoach.currentWeekByDisplayRegion(
              currentWeekRawSets,
              weeklyTargets: summary.weeklyTargets,
            ).entries)
              entry.key: entry.value.percent,
          }
        : _aggregateDisplayPercents(summary);
    return [
      for (final region in DisplayRegion.values)
        if (region != DisplayRegion.other)
          {
            'name': region.label,
            'percentOfGoal': (percents[region] ?? 0.0).round(),
          },
    ];
  }

  Widget _buildOverviewCard(
    ThemeData theme,
    BodyScoreSummary summary,
    BodyScorePeriodWindow window,
    BodyScoreComparison? comparison, {
    // Phase 2: when the card is shown DEMOTED inside the current-week "Trends &
    // detail" collapsible, the 0-100 score is relabelled "Evenness" (the
    // distribution lens, not the hero) and the duplicate period header is hidden
    // - the period selector already sits at the top of the headline IA.
    bool evennessContext = false,
  }) {
    final colorScheme = theme.colorScheme;
    final balance = summary.balanceScore;
    // Phase 1: the in-progress current week uses the RAW raw-vs-target cue
    // (summed sets vs the weekly goal) so the headline never nags with a paced
    // percentage; the closed periods keep the existing paced verdict.
    final coachingCue = _selectedPeriod.isCurrentWeek
        ? BodyScoreCoach.currentWeekCue(
            _currentWeekRawSets,
            weeklyTargets: summary.weeklyTargets,
            physicalSetsByRegion: _currentWeekPhysicalSets,
          )
        : BodyScoreCoach.overallCue(summary);

    // Determine status. Kind by default: a low balance is the orange warning
    // hue, never red — red is reserved for destructive failures, not "your
    // training is uneven".
    final Color statusColor;
    final String statusLabel;
    if (balance >= 80) {
      statusColor = colorScheme.tertiary;
      statusLabel = evennessContext ? 'Very even' : 'Great balance';
    } else if (balance >= 60) {
      statusColor = colorScheme.primary;
      statusLabel = evennessContext ? 'Fairly even' : 'Good balance';
    } else {
      statusColor = AppColors.accentWarningAmber;
      statusLabel = evennessContext ? 'Uneven' : 'Uneven balance';
    }

    final dailyTotals = [
      for (final day in summary.timeline)
        day.esByMuscleGroup.values.fold<double>(0, (sum, v) => sum + v),
    ];

    // Wave G §12.1: flat module — surface == canvas, no outline. The radar
    // inside makes this read as a block; structure comes from type + hairlines.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!evennessContext) ...[
            _buildSummaryHeader(theme, window, summary, comparison),
            const SizedBox(height: AppSpacing.x2),
          ],
          // Wave I — data as hero: the balance score is a ring with the number
          // BIG in its centre, the status read beside it. The hue follows the
          // score (emerald great / blue good / amber room-to-balance).
          _BalanceHero(
            score: balance,
            statusColor: statusColor,
            statusLabel: statusLabel,
            caption: evennessContext ? 'Evenness' : 'Balance score',
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(
            'How evenly your hard training is spread across your muscles — '
            'higher is more balanced.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (dailyTotals.length >= 3) ...[
            const SizedBox(height: AppSpacing.x2),
            OverviewTrendSparkline(dailyTotals: dailyTotals),
          ],
          const SizedBox(height: AppSpacing.x2),
          // Action hint (if applicable). Hidden in the demoted evenness context -
          // the headline "Do next" list already carries the actionable cue, so
          // the buried card stays a pure distribution lens.
          if (!evennessContext &&
              coachingCue.mode != BodyScoreCoachingMode.maintain) ...[
            // Wave G §12.1: borderless flat tint strip — quiet prompt.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.x1 + 4),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: AppRadius.controlRadius,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      coachingCue.detail == null
                          ? coachingCue.headline
                          : '${coachingCue.headline} ${coachingCue.detail}',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
            // Opt-in coach note: a quiet "Explain my numbers" affordance under
            // the cue. Gated on >=2 sessions (never narrate the gather-more-data
            // state) + the opt-in. The note is purely additive — the cue above
            // and the regions below stay authoritative.
            if (_coachExplainsOptIn && summary.sessionCount >= 2) ...[
              const SizedBox(height: AppSpacing.x1),
              // Build the facts ONCE and use the SAME map for the fetch and the
              // reset key, so the key reflects exactly what the note explains.
              Builder(
                builder: (context) {
                  final trainingFacts =
                      _buildTrainingFacts(summary, coachingCue, window);
                  return CoachExplainSection(
                    fetchNarrative: () => _explainApi.explain('training', trainingFacts),
                    // Reset the note when ANY explained fact changes — region
                    // percents, lagging/dominant region, cue text, set count, and
                    // window included — derived from the FULL facts map (Finding 3),
                    // so a stale note never hangs above fresh data.
                    resetKey: trainingExplainResetKey(trainingFacts),
                  );
                },
              ),
            ],
            const SizedBox(height: AppSpacing.x2),
          ],
          // Radar chart
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 650;
              final chartSize = isCompact ? 180.0 : 200.0;
              final chart = SizedBox(
                width: chartSize,
                height: chartSize,
                child: BodyScoreRadar(
                  scoresByMuscleGroup: summary.regionScores,
                  weeklyTargetsByMuscleGroup: summary.weeklyTargets,
                  weeklyTotals: summary.weeklyEquivalentVolumes,
                ),
              );

              // Wave I: the sessions / muscles-trained / highest-vs-goal meta is
              // grouped into a rounded surface card so it reads as an object,
              // not a flat strip.
              final statsChips = Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.all(AppSpacing.x2),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    AppChip(
                      variant: AppChipVariant.data,
                      icon: Icons.calendar_today_outlined,
                      label: 'Sessions',
                      value: NumberFormatUtil.formatInt(summary.sessionCount),
                    ),
                    AppChip(
                      variant: AppChipVariant.data,
                      icon: Icons.grid_view,
                      label: 'Muscles trained',
                      value:
                          '${summary.mappableRegionCount} of ${summary.totalMappableRegions}',
                    ),
                    AppChip(
                      variant: AppChipVariant.data,
                      icon: Icons.fitness_center,
                      label: 'Highest vs goal',
                      value: summary.dominantRegion.label,
                    ),
                  ],
                ),
              );

              if (isCompact) {
                return Column(
                  children: [
                    Align(alignment: Alignment.center, child: chart),
                    const SizedBox(height: AppSpacing.x2),
                    statsChips,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  chart,
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        statsChips,
                        const SizedBox(height: 12),
                        // Wave E §9: methodology copy demoted.
                        Text(
                          'Each muscle as a % of its weekly goal, averaged to a per-week pace for the period you picked.',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader(
    ThemeData theme,
    BodyScorePeriodWindow window,
    BodyScoreSummary summary,
    BodyScoreComparison? comparison,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'Balance',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _PeriodPillSelector(
              selected: _selectedPeriod,
              available: BodyScorePeriod.values,
              onSelected: _onPeriodChanged,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(window.labelWithDate, style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _buildHeatMapCard() {
    return BodyHeatMap(
      metricsByStrategy: _heatmapMetricsByStrategy,
      strategies: _strategies,
      weeklyTargetsByStrategy: _weeklyTargetsByStrategy,
      initialStrategyId: _primaryStrategy.id,
      breakdown: _heatmapExercises,
      lookback: _heatmapLookback,
      loading: _loading,
    );
  }

  Widget _buildRegionControls(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sort muscles by',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        // Wrapping AppChip row replaces the heavy form dropdown + filter chip.
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final sort in BodyScoreRegionSort.values)
              AppChip(
                variant: AppChipVariant.filter,
                label: sort.label,
                selected: _regionSort == sort,
                onTap: () {
                  if (_regionSort == sort) return;
                  Haptics.selection();
                  setState(() => _regionSort = sort);
                },
              ),
            AppChip(
              variant: AppChipVariant.filter,
              icon: _showActiveOnly
                  ? Icons.check
                  : Icons.visibility_off_outlined,
              label: 'Recently trained only',
              selected: _showActiveOnly,
              onTap: () {
                Haptics.selection();
                setState(() => _showActiveOnly = !_showActiveOnly);
              },
            ),
          ],
        ),
      ],
    );
  }
}
