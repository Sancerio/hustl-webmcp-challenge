import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hustl_app/core/coaching/coach_insight.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_coach.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_service.dart';
import 'package:hustl_app/features/workout_log/domain/utils/muscle_group_mapper.dart';
import 'package:hustl_app/features/workout_log/domain/utils/time_periods.dart';

import '../models/workout_session.dart';

enum NextWorkoutFocusTone { balanced, build, rebalance, earlySignal }

class NextWorkoutFocusPlan {
  const NextWorkoutFocusPlan({
    required this.headline,
    required this.detail,
    required this.statusLabel,
    required this.primaryRegion,
    required this.primaryPercent,
    required this.exerciseSuggestions,
    required this.tone,
    required this.windowLabel,
    required this.confidence,
    this.secondaryRegion,
    this.suggestedSets = 0,
    this.daysSincePrimaryStimulus,
    this.secondaryPercent,
    this.readinessNote,
  });

  final String headline;
  final String detail;
  final String statusLabel;
  final DisplayRegion primaryRegion;
  final DisplayRegion? secondaryRegion;
  final int suggestedSets;
  final int? daysSincePrimaryStimulus;
  final int primaryPercent;
  final int? secondaryPercent;
  final List<String> exerciseSuggestions;
  final NextWorkoutFocusTone tone;

  /// The data-window label for the SAME period the Training-balance detail uses
  /// (e.g. "last 4 weeks", "last full month"). Shown beside the confidence cue
  /// so the card never mislabels its window.
  final String windowLabel;

  /// Confidence DERIVED from how much data backs the verdict in the window —
  /// never asserted "high" unconditionally.
  final CoachConfidence confidence;

  /// Optional readiness context line — the "should I push today?" answer — mapped
  /// from the day's recovery band by [NextWorkoutFocusService.readinessNoteFor].
  /// Deliberately conservative (see that mapping): non-null ONLY on the lowest
  /// ("Recharge") or highest ("Charged") band with usable, non-low-confidence
  /// signal; `null` on ordinary days, thin data, or no readiness at all, so the
  /// card renders pixel-identically to today.
  final String? readinessNote;
}

class NextWorkoutFocusService {
  NextWorkoutFocusService({
    BodyScoreService? bodyScoreService,
    // Phase 1: default to the in-progress current week so the Home focus card
    // and the Training-balance detail share ONE window (the detail's new
    // default). Callers still pass the user's persisted selection so the two
    // surfaces stay aligned when the user picks a closed period.
    BodyScorePeriod period = BodyScorePeriod.defaultPeriod,
    int firstWeekday = DateTime.monday,
  }) : _bodyScoreService = bodyScoreService ?? BodyScoreService(),
       _period = period,
       _firstWeekday = firstWeekday;

  final BodyScoreService _bodyScoreService;

  /// The Training-balance period the card aligns to. Defaults to the SAME
  /// default the detail uses ([BodyScorePeriod.defaultPeriod] - the in-progress
  /// current week) and is passed the user's persisted selection so the card
  /// never reads over a different window than the detail it links to.
  final BodyScorePeriod _period;
  final int _firstWeekday;

  NextWorkoutFocusPlan? build(
    List<WorkoutSession> sessions, {
    DateTime? anchor,
    DailyRecoverySnapshot? readiness,
  }) {
    final completed = sessions
        .where((session) => session.isCompleted)
        .toList(growable: false);
    if (completed.isEmpty) {
      return null;
    }

    final now = anchor ?? DateTime.now();
    // The readiness context line is a pure annotation on top of the (unchanged)
    // body-balance verdict. Computed once and carried through whichever plan
    // path builds below; `null` on every ordinary/thin-data day so the card is
    // unchanged from today.
    final readinessNote = readinessNoteFor(readiness);
    // PRIMARY: resolve the SAME window the detail computes (persisted period),
    // not a rolling 28-day window — so the two surfaces share one data window
    // and the card never contradicts the detail's confident closed-period
    // verdict.
    final window = _period.resolve(now, firstWeekday: _firstWeekday);
    final summary = _bodyScoreService.summarize(
      completed,
      range: window.range,
    );
    if (summary != null) {
      // CURRENT WEEK: the detail derives its verdict + region figures from RAW
      // summed sets vs the weekly goal (NOT the paced (sets/days)*7 weekly
      // equivalent, which inflates an in-progress week). Compute the SAME raw
      // basis here so Home's current-week verdict matches the detail exactly,
      // instead of the paced overallCue which can call a region balanced/over
      // target mid-week. The closed-period paths keep their paced behaviour.
      final rawCurrentWeek = _period.isCurrentWeek
          ? _buildRawCurrentWeek(completed, window.range, summary)
          : null;
      return _planFromSummary(
        summary: summary,
        completed: completed,
        now: now,
        windowLabel: _windowLabel(_period),
        // Closed-period confidence is DERIVED from how much data backs the
        // verdict — never forced.
        confidenceOverride: null,
        rawCurrentWeek: rawCurrentWeek,
        readinessNote: readinessNote,
      );
    }

    // FALLBACK (CLOSED PERIODS ONLY): the selected *closed* period ends before
    // the current partial week, so a user whose only completed sessions are
    // *this* week yields a null closed-period summary and the home focus card
    // would disappear even though history exists. Fall back to the pre-#378
    // rolling-to-today window so the early-signal card still renders.
    //
    // This rolling read is GATED to closed periods. When the selected period is
    // the in-progress current week (the Phase 1 default), an empty summary means
    // the current week itself has no sessions — and the Training-balance detail
    // shows its current-week EMPTY / gather-more state (no region tiles) for
    // exactly that case. Running the rolling fallback here would instead surface
    // a `recent` focus plan built from OLD history (e.g. a user who trained last
    // week but not since Monday), so Home would show an old-history verdict
    // while the detail's default current-week window is empty — the two would
    // contradict again. For the current week we therefore return null (no plan),
    // which renders the same empty/gather state on Home (the plain Training-
    // balance nav row) as the detail shows. The rolling fallback only applies to
    // CLOSED periods, its original #378 purpose.
    //
    // For a closed period this is a deliberately EARLY/ROLLING read. The
    // fallback only fires when the closed period is empty — which is exactly
    // when the Training-balance detail screen also shows its "gather more data"
    // state. So the card must mirror that state, NOT a confident region verdict:
    // even with 2+ current-week sessions the rolling summary would otherwise
    // derive a concrete addSets/rebalance cue ("Add N sets") and contradict the
    // detail. We therefore force an early-signal / gather-more plan
    // ([earlySignal]) — it still RENDERS (no regression to a disappearing card)
    // but carries a soft "early read — keep logging" framing,
    // [CoachConfidence.building], and a rolling "recent" window label, never a
    // confident closed-period verdict.
    if (_period.isCurrentWeek) {
      return null;
    }
    final rollingSummary = _bodyScoreService.summarize(
      completed,
      range: rollingRangeToToday(days: _rollingFallbackDays, anchor: now),
    );
    if (rollingSummary == null) {
      return null;
    }
    return _planFromSummary(
      summary: rollingSummary,
      completed: completed,
      now: now,
      windowLabel: _rollingWindowLabel,
      confidenceOverride: CoachConfidence.building,
      earlySignal: true,
      readinessNote: readinessNote,
    );
  }

  /// Maps the day's [readiness] snapshot to a single conservative context line —
  /// the "should I push today?" answer — or `null` to render nothing.
  ///
  /// Mirrors the exact conservatism of `RecoveryFlowCopy`: never on thin data
  /// (no snapshot, no recovery signal, still calibrating, no band, or low
  /// confidence), and only on the two ends of the band scale — a gentle
  /// invitation to go lighter on the lowest band, a quiet green light to push on
  /// the highest. The middle bands ("Steady"/"Ready") stay silent so ordinary
  /// days carry no noise. Copy is sentence-case and non-medical.
  static String? readinessNoteFor(DailyRecoverySnapshot? readiness) {
    if (readiness == null || !readiness.hasRecoveryData) return null;
    if (readiness.isCalibrating) return null;
    if (readiness.confidence == RecoveryConfidence.low) return null;
    final band = readiness.flowBand;
    if (band == null) return null;
    switch (band) {
      case RecoveryFlowBand.recharge:
        return 'Recovery is low today — a lighter session still counts.';
      case RecoveryFlowBand.charged:
        return 'You\'re recharged — a good day to push.';
      case RecoveryFlowBand.steady:
      case RecoveryFlowBand.ready:
        return null;
    }
  }

  /// Rolling-to-today span used only by the early-signal fallback (matches the
  /// pre-#378 rolling window).
  static const int _rollingFallbackDays = 28;

  /// Window label for the rolling fallback read. Deliberately phrased as a
  /// rolling span ("recent") so the early card never claims the aligned
  /// closed-period window.
  static const String _rollingWindowLabel = 'recent';

  /// Builds the plan from a resolved [summary]. When [confidenceOverride] is
  /// non-null it is used verbatim (the rolling fallback forces an early
  /// "building" read); otherwise confidence is DERIVED from the data backing
  /// the verdict over the closed period.
  ///
  /// When [earlySignal] is true (the rolling fallback for an empty closed
  /// period) the derived verdict is downgraded to an early-signal / gather-more
  /// cue: the card still renders and still surfaces a focus region, but it never
  /// emits a concrete addSets/rebalance verdict ("Add N sets"). That keeps Home
  /// consistent with the Training-balance detail, which is in its gather-more
  /// state whenever the selected closed period is empty.
  ///
  /// When [rawCurrentWeek] is non-null (the in-progress current-week window) the
  /// verdict + per-region percents come from the RAW summed-sets-vs-target basis
  /// the Training-balance detail uses (its [BodyScoreCoach.currentWeekCue] /
  /// [BodyScoreCoach.currentWeekByDisplayRegion] path), NOT the paced
  /// [BodyScoreCoach.overallCue]. That keeps Home's current-week verdict
  /// identical to the detail's instead of the paced (sets/days)*7 figure that
  /// can call a region balanced/over target mid-week.
  NextWorkoutFocusPlan _planFromSummary({
    required BodyScoreSummary summary,
    required List<WorkoutSession> completed,
    required DateTime now,
    required String windowLabel,
    required CoachConfidence? confidenceOverride,
    bool earlySignal = false,
    _RawCurrentWeek? rawCurrentWeek,
    String? readinessNote,
  }) {
    // VERDICT: for the current-week window, the RAW sets-vs-target cue the detail
    // uses; otherwise the FLAT per-region paced basis the detail surfaces over a
    // CLOSED period (region tiles + balance score), so the card never claims
    // "balanced" while the detail shows a region under target. In the rolling
    // fallback we keep the region pick but soften the verdict to a gather-more
    // read so Home matches the detail's gather-more state.
    final derivedCue = rawCurrentWeek != null
        ? rawCurrentWeek.cue
        : BodyScoreCoach.overallCue(summary, recencyAware: false);
    final cue = earlySignal ? _asEarlySignalCue(derivedCue) : derivedCue;
    final displaySummaries =
        rawCurrentWeek?.displaySummaries ??
        BodyScoreCoach.aggregateByDisplayRegion(
          summary,
          recencyAware: false,
        );
    final primaryRegion = _resolvePrimaryRegion(
      cue: cue,
      summary: summary,
      displaySummaries: displaySummaries,
      anchor: now,
    );
    final secondaryRegion = cue.secondaryRegion;
    final lastStimulus =
        _lastStimulusForRegion(summary, primaryRegion) ??
        _lastCompletedSessionForRegion(completed, primaryRegion);
    final primaryPercent = (displaySummaries[primaryRegion]?.percent ?? 0)
        .round();
    final secondaryPercent = secondaryRegion == null
        ? null
        : (displaySummaries[secondaryRegion]?.percent ?? 0).round();

    return NextWorkoutFocusPlan(
      headline: cue.headline,
      detail: _buildDetail(
        cue: cue,
        primaryRegion: primaryRegion,
        secondaryRegion: secondaryRegion,
        primaryPercent: primaryPercent,
        daysSincePrimaryStimulus: _daysSince(now, lastStimulus),
        windowLabel: windowLabel,
      ),
      statusLabel: _statusLabel(cue.mode),
      primaryRegion: primaryRegion,
      secondaryRegion: secondaryRegion,
      suggestedSets: cue.setCount,
      daysSincePrimaryStimulus: _daysSince(now, lastStimulus),
      primaryPercent: primaryPercent.clamp(0, 999).toInt(),
      secondaryPercent: secondaryPercent?.clamp(0, 999).toInt(),
      exerciseSuggestions: _exerciseSuggestionsForRegion(
        sessions: completed,
        summary: summary,
        region: primaryRegion,
        anchor: now,
      ),
      tone: _toneForMode(cue.mode),
      windowLabel: windowLabel,
      confidence:
          confidenceOverride ?? _confidenceForSummary(summary, cue.mode),
      readinessNote: readinessNote,
    );
  }

  /// Downgrades a derived verdict [cue] to an early-signal / gather-more cue
  /// for the rolling fallback. It KEEPS the cue's focus region (so the card
  /// still points the user somewhere) but drops the concrete addSets/rebalance
  /// framing: the headline becomes a soft "early read — keep logging" message,
  /// the set count is cleared, and the mode flips to
  /// [BodyScoreCoachingMode.gatherMoreData] so [_statusLabel]/[_toneForMode]/
  /// [_buildDetail] all render the same early-signal state the Training-balance
  /// detail shows when the selected closed period is empty.
  static BodyScoreCoachingCue _asEarlySignalCue(BodyScoreCoachingCue cue) {
    return BodyScoreCoachingCue(
      mode: BodyScoreCoachingMode.gatherMoreData,
      headline: 'Early read — keep logging.',
      primaryRegion: cue.primaryRegion,
      // No secondary region / set count: an early read makes no concrete
      // rebalance ("shift N sets") claim.
    );
  }

  /// Builds the RAW current-week verdict + per-region figures the
  /// Training-balance detail uses for the in-progress week: summed sets vs the
  /// weekly goal, NOT the paced (sets/days)*7 weekly equivalent. The detail
  /// drives its tiles, headline and met-state from exactly this basis
  /// ([BodyScoreCoach.currentWeekByDisplayRegion] /
  /// [BodyScoreCoach.currentWeekCue]), so computing it here keeps Home's
  /// current-week verdict identical to the detail's.
  ///
  /// The per-region [CurrentWeekRegionSummary] map is adapted to the
  /// [DisplayRegionStimulusSummary] shape [_planFromSummary] /
  /// [_resolvePrimaryRegion] already consume, so the region pick and percents
  /// flow through unchanged on the RAW values.
  _RawCurrentWeek _buildRawCurrentWeek(
    List<WorkoutSession> completed,
    DateTimeRange range,
    BodyScoreSummary summary,
  ) {
    final Map<MuscleGroup, double> rawSetsByGroup = {
      for (final entry
          in _bodyScoreService.aggregateForRange(completed, range).entries)
        entry.key: entry.value.sets,
    };
    final cue = BodyScoreCoach.currentWeekCue(
      rawSetsByGroup,
      weeklyTargets: summary.weeklyTargets,
    );
    final byRegion = BodyScoreCoach.currentWeekByDisplayRegion(
      rawSetsByGroup,
      weeklyTargets: summary.weeklyTargets,
    );
    final displaySummaries = {
      for (final entry in byRegion.entries)
        entry.key: DisplayRegionStimulusSummary(
          region: entry.value.region,
          actualWeeklyEquivalent: entry.value.rawSets,
          weeklyTarget: entry.value.weeklyTarget,
          deficit: (entry.value.weeklyTarget - entry.value.rawSets).clamp(
            0.0,
            double.maxFinite,
          ),
          excess: (entry.value.rawSets - entry.value.weeklyTarget).clamp(
            0.0,
            double.maxFinite,
          ),
        ),
    };
    return _RawCurrentWeek(cue: cue, displaySummaries: displaySummaries);
  }

  /// A human window label matching the detail's period (e.g. "last 4 weeks").
  static String _windowLabel(BodyScorePeriod period) {
    switch (period) {
      case BodyScorePeriod.currentWeek:
        return 'this week';
      case BodyScorePeriod.lastFullWeek:
        return 'last full week';
      case BodyScorePeriod.lastFullMonth:
        return 'last full month';
      case BodyScorePeriod.last4FullWeeks:
        return 'last 4 weeks';
    }
  }

  /// Confidence DERIVED from how much data backs the verdict over the window —
  /// never asserted "high" unconditionally. A still-thin window (the same
  /// "gather more data" signal the detail shows) is [CoachConfidence.building];
  /// a couple of sessions is [CoachConfidence.medium]; a well-covered window is
  /// [CoachConfidence.high].
  static CoachConfidence _confidenceForSummary(
    BodyScoreSummary summary,
    BodyScoreCoachingMode mode,
  ) {
    if (mode == BodyScoreCoachingMode.gatherMoreData ||
        summary.sessionCount <= 1) {
      return CoachConfidence.building;
    }
    if (summary.sessionCount <= 3) {
      return CoachConfidence.medium;
    }
    return CoachConfidence.high;
  }

  DisplayRegion _resolvePrimaryRegion({
    required BodyScoreCoachingCue cue,
    required BodyScoreSummary summary,
    required Map<DisplayRegion, DisplayRegionStimulusSummary> displaySummaries,
    required DateTime anchor,
  }) {
    if (cue.primaryRegion != null) {
      return cue.primaryRegion!;
    }

    final candidates = displaySummaries.values
        .where((region) => region.region != DisplayRegion.other)
        .where((region) => region.weeklyTarget > 0)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return DisplayRegion.chest;
    }

    final sorted = [...candidates];
    sorted.sort((a, b) {
      if (cue.mode == BodyScoreCoachingMode.maintain) {
        return _regionSortKey(
          anchor,
          summary,
          b.region,
        ).compareTo(_regionSortKey(anchor, summary, a.region));
      }
      final percentCompare = a.percent.compareTo(b.percent);
      if (percentCompare != 0) {
        return percentCompare;
      }
      return _regionSortKey(
        anchor,
        summary,
        b.region,
      ).compareTo(_regionSortKey(anchor, summary, a.region));
    });
    return sorted.first.region;
  }

  int _regionSortKey(
    DateTime anchor,
    BodyScoreSummary summary,
    DisplayRegion region,
  ) {
    final lastStimulus = _lastStimulusForRegion(summary, region);
    final days = _daysSince(anchor, lastStimulus);
    return days ?? 999;
  }

  DateTime? _lastStimulusForRegion(
    BodyScoreSummary summary,
    DisplayRegion region,
  ) {
    DateTime? latest;
    for (final entry in summary.lastStimulus.entries) {
      if (entry.key.displayRegion != region) {
        continue;
      }
      final date = entry.value;
      if (date == null) {
        continue;
      }
      if (latest == null || date.isAfter(latest)) {
        latest = date;
      }
    }
    return latest;
  }

  DateTime? _lastCompletedSessionForRegion(
    List<WorkoutSession> sessions,
    DisplayRegion region,
  ) {
    final mapper = MuscleGroupMapper();
    DateTime? latest;
    for (final session in sessions) {
      final hitsRegion = session.exercises.any(
        (exercise) =>
            exercise.sets.any((set) => set.isCompleted) &&
            exercise.exercise.muscles.any(
              (muscle) => mapper.groupFor(muscle).displayRegion == region,
            ),
      );
      if (!hitsRegion) {
        continue;
      }
      final candidate = session.endTime ?? session.startTime;
      if (latest == null || candidate.isAfter(latest)) {
        latest = candidate;
      }
    }
    return latest;
  }

  int? _daysSince(DateTime anchor, DateTime? value) {
    if (value == null) {
      return null;
    }
    final today = DateTime(anchor.year, anchor.month, anchor.day);
    final day = DateTime(value.year, value.month, value.day);
    return math.max(0, today.difference(day).inDays);
  }

  List<String> _exerciseSuggestionsForRegion({
    required List<WorkoutSession> sessions,
    required BodyScoreSummary summary,
    required DisplayRegion region,
    required DateTime anchor,
  }) {
    final combined = <String, double>{};
    void collect(Map<MuscleGroup, Map<String, double>> source) {
      for (final entry in source.entries) {
        if (entry.key.displayRegion != region) {
          continue;
        }
        for (final exercise in entry.value.entries) {
          combined.update(
            exercise.key,
            (value) => exercise.value > value ? exercise.value : value,
            ifAbsent: () => exercise.value,
          );
        }
      }
    }

    collect(summary.topExercises);
    final range = _rangeFromSessions(sessions, anchor);
    if (range != null) {
      collect(
        _bodyScoreService.aggregateExerciseVolumeForRange(
          sessions,
          range,
          topExercisesPerRegion: 8,
        ),
      );
    }

    final sorted = combined.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(2).map((entry) => entry.key).toList(growable: false);
  }

  DateTimeRange? _rangeFromSessions(
    List<WorkoutSession> sessions,
    DateTime now,
  ) {
    if (sessions.isEmpty) {
      return null;
    }
    DateTime start = sessions.first.startTime;
    DateTime end = sessions.first.endTime ?? sessions.first.startTime;
    for (final session in sessions.skip(1)) {
      if (session.startTime.isBefore(start)) {
        start = session.startTime;
      }
      final candidateEnd = session.endTime ?? session.startTime;
      if (candidateEnd.isAfter(end)) {
        end = candidateEnd;
      }
    }
    if (end.isBefore(start)) {
      end = start;
    }
    if (now.isAfter(end)) {
      end = now;
    }
    return DateTimeRange(start: start, end: end);
  }

  /// The window phrase for add-set detail copy. The closed-period labels read
  /// naturally after "over the " (e.g. "over the last 4 weeks"), but the
  /// current-week label is "this week", which would render the ungrammatical
  /// "over the this week" (codex [P3], PR #384). Special-case the current week so
  /// the copy reads "... this week" with no "over the " prefix.
  static String _windowDetailPhrase(String windowLabel) {
    if (windowLabel == _windowLabel(BodyScorePeriod.currentWeek)) {
      return windowLabel;
    }
    return 'over the $windowLabel';
  }

  String _buildDetail({
    required BodyScoreCoachingCue cue,
    required DisplayRegion primaryRegion,
    required DisplayRegion? secondaryRegion,
    required int primaryPercent,
    required int? daysSincePrimaryStimulus,
    required String windowLabel,
  }) {
    final recencyText = daysSincePrimaryStimulus == null
        ? null
        : daysSincePrimaryStimulus == 0
        ? 'You already hit ${primaryRegion.label.toLowerCase()} today.'
        : daysSincePrimaryStimulus == 1
        ? 'Last solid ${primaryRegion.label.toLowerCase()} work was yesterday.'
        : 'Last solid ${primaryRegion.label.toLowerCase()} work was $daysSincePrimaryStimulus days ago.';

    switch (cue.mode) {
      case BodyScoreCoachingMode.addSets:
        // Deficit-first copy. We deliberately do NOT surface the same-day
        // "you already hit X today" recency clause here: it runs on the
        // device-local clock while the deficit is a period rate, so the two
        // can contradict the "add N sets" headline. Lead with the gap instead.
        // The window phrase tracks the selected period so it never claims a
        // different window than the detail.
        final setsLabel = cue.setCount == 1 ? 'set' : 'sets';
        // The window phrase reads "over the last 4 weeks" for closed periods,
        // but the current-week label is "this week" - "over the this week" is
        // ungrammatical (codex [P3], PR #384). For the current week drop the
        // "over the " prefix AND the redundant trailing "this week" (the window
        // phrase already says it), so the copy reads "... of its weekly goal
        // this week — aim for about N more sets." Closed periods keep
        // "over the $windowLabel ... this week."
        final bool isCurrentWeekWindow =
            windowLabel == _windowLabel(BodyScorePeriod.currentWeek);
        final String windowPhrase = _windowDetailPhrase(windowLabel);
        final String setsTail = isCurrentWeekWindow
            ? 'aim for about ${cue.setCount} more $setsLabel.'
            : 'aim for about ${cue.setCount} more $setsLabel this week.';
        return '${primaryRegion.label} is at $primaryPercent% of its weekly goal '
            '$windowPhrase — $setsTail';
      case BodyScoreCoachingMode.redistributeSets:
        if (secondaryRegion == null) {
          return recencyText ??
              '${primaryRegion.label} is lagging your current training split.';
        }
        return '${secondaryRegion.label} is ahead right now, so the easiest win is moving a little volume into ${primaryRegion.label.toLowerCase()}.';
      case BodyScoreCoachingMode.gatherMoreData:
        return recencyText ??
            'This is an early read, not a hard correction yet.';
      case BodyScoreCoachingMode.maintain:
        return recencyText ??
            'You look balanced overall, so treat this as your next rotation target.';
    }
  }

  String _statusLabel(BodyScoreCoachingMode mode) {
    switch (mode) {
      case BodyScoreCoachingMode.maintain:
        return 'Balanced';
      case BodyScoreCoachingMode.addSets:
        return 'Build';
      case BodyScoreCoachingMode.redistributeSets:
        return 'Rebalance';
      case BodyScoreCoachingMode.gatherMoreData:
        return 'Trending';
    }
  }

  NextWorkoutFocusTone _toneForMode(BodyScoreCoachingMode mode) {
    switch (mode) {
      case BodyScoreCoachingMode.maintain:
        return NextWorkoutFocusTone.balanced;
      case BodyScoreCoachingMode.addSets:
        return NextWorkoutFocusTone.build;
      case BodyScoreCoachingMode.redistributeSets:
        return NextWorkoutFocusTone.rebalance;
      case BodyScoreCoachingMode.gatherMoreData:
        return NextWorkoutFocusTone.earlySignal;
    }
  }
}

/// The RAW current-week basis (Phase 1) the Home focus card shares with the
/// Training-balance detail: the verdict [cue] and the per-region figures
/// [displaySummaries] both computed from summed sets vs the weekly goal (not the
/// paced weekly equivalent), so the two surfaces never contradict each other on
/// an in-progress week.
class _RawCurrentWeek {
  const _RawCurrentWeek({
    required this.cue,
    required this.displaySummaries,
  });

  final BodyScoreCoachingCue cue;
  final Map<DisplayRegion, DisplayRegionStimulusSummary> displaySummaries;
}
