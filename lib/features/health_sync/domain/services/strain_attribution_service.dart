import 'dart:math' as math;

import '../../../workout_logging/domain/models/workout_session.dart';
import '../models/daily_recovery_snapshot.dart';
import '../models/external_activity.dart';
import '../models/strain_ledger.dart';

/// Splits the day's *already-measured* training load across the sessions that
/// drove it, producing a [StrainLedger] for the "what drove today's strain"
/// receipt.
///
/// The cardinal rule: attribution NEVER adds load. The daily aggregates already
/// measured the day's [DailyRecoverySnapshot.trainingLoad] (and the strain
/// score derived from it); this service only *explains* that number by dividing
/// it, and the parts always sum back to the whole.
///
/// ## Component-budgeted attribution
///
/// The day's training load (arbitrary units, AU) is measured as
/// `activeEnergy*0.08 + exerciseMinutes*1.4 + steps/1000*1.2`. Rather than
/// crediting a session on energy alone, each session is credited on the SAME
/// components the day measured: overlap-adjusted exercise minutes and active
/// energy. Each component is treated as a fixed budget — the day's measured
/// value — that is divided among sessions and never exceeded, so a session can
/// never be credited more load than the day actually measured. Steps stay
/// entirely in Ambient for now (no per-session step reads yet).
///
/// - **Exercise minutes**: each session's overlap-adjusted ("effective")
///   minutes are computed via [_effectiveMinutes] so concurrent different-kind
///   sessions never double-count shared wall-clock minutes. The day's
///   `exerciseMinutes` is then divided among sessions proportionally, capped at
///   `min(1, day.exerciseMinutes / Σ effectiveMinutes)` — a paused or
///   low-intensity session that reported fewer elevated-HR minutes than its
///   wall-clock duration is credited only for what was measured.
/// - **Active energy**: sessions with recorded kcal claim the fraction of that
///   value matching their in-day duration (then scale down proportionally if
///   the recorded total exceeds the day's budget). Whatever active-energy
///   budget remains unclaimed is split among energy-absent sessions, weighted
///   by `effectiveMinutes * kindFactor`
///   (the [_kindFactor] table is a coarse kcal/min-ish estimate, used only
///   *relatively* between sessions, never as an absolute calorie claim).
///
/// A session's share of the day = `sessionLoad / day.trainingLoad`. Shares are
/// capped so their sum never exceeds 1 (a floating-point safety net — by
/// construction the budgeted components can't exceed `dayLoad`). The
/// **ambient remainder** = `max(0, 1 - Σ shares)` — the part of the day's
/// strain no session explains (background daily movement, plus the
/// not-yet-attributed steps term).
///
/// Each entry's `loadPoints = share * strainScore`, rounded to one decimal via
/// the largest-remainder method so that every entry plus the ambient remainder
/// sum *exactly* to the integer strain score.
class StrainAttributionService {
  const StrainAttributionService();

  /// Energy coefficient shared with the daily training-load formula, so a
  /// session's kcal map into the same AU space the day was measured in.
  static const double _energyToLoad = 0.08;

  /// Exercise-minute coefficient shared with the daily training-load formula.
  static const double _exerciseMinuteToLoad = 1.4;

  /// Coarse per-minute load factors (kcal/min-ish) used only to weight how the
  /// residual (unclaimed) active-energy budget is split among energy-absent
  /// sessions. Deliberately rough and only meaningful relative to one another.
  static double _kindFactor(ExternalActivityKind kind) {
    switch (kind) {
      case ExternalActivityKind.strengthTraining:
        return 5.0;
      case ExternalActivityKind.run:
        return 10.0;
      case ExternalActivityKind.ride:
        return 8.0;
      case ExternalActivityKind.swim:
        return 9.0;
      case ExternalActivityKind.walk:
        return 3.5;
      case ExternalActivityKind.hike:
        return 6.0;
      case ExternalActivityKind.hiit:
        return 11.0;
      case ExternalActivityKind.yoga:
        return 2.5;
      case ExternalActivityKind.other:
        return 5.0;
    }
  }

  /// Sanitizes a double read from health-kit-sourced data: non-finite,
  /// negative, null, or zero values collapse to `0.0`; anything else is
  /// capped at [max] so a single corrupt/huge reading can't overflow
  /// downstream sums (e.g. `claimedSum`) to `Infinity`/`NaN`.
  static double _sanitize(num? v, {double max = 1e9}) {
    if (v == null) return 0.0;
    final d = v.toDouble();
    if (!d.isFinite || d <= 0) return 0.0;
    return d < max ? d : max;
  }

  /// Fraction of a contributor's positive wall-clock duration that falls
  /// inside the current day's clipped interval. Invalid/non-positive full or
  /// clipped durations claim no recorded energy. The upper clamp also keeps
  /// malformed clipping inputs from amplifying a contributor's total kcal.
  static double _inDayDurationRatio({
    required DateTime start,
    required DateTime end,
    required DateTime clippedStart,
    required DateTime clippedEnd,
  }) {
    final fullMicros = end.difference(start).inMicroseconds;
    final clippedMicros = clippedEnd.difference(clippedStart).inMicroseconds;
    if (fullMicros <= 0 || clippedMicros <= 0) return 0.0;
    return math.min(1.0, clippedMicros / fullMicros);
  }

  StrainLedger attribute({
    required DailyRecoverySnapshot day,
    required List<WorkoutSession> hustlSessions,
    required List<ExternalActivity> externals,
  }) {
    final strainScore = day.strainScore ?? 0;
    if (strainScore <= 0) return const StrainLedger.empty();

    final contributors = <_Contributor>[];
    for (final session in hustlSessions) {
      final end = session.endTime;
      if (end == null) continue;
      contributors.add(
        _Contributor(
          id: session.id,
          source: StrainSource.hustl,
          // Hustl sessions are strength training for factor purposes.
          kind: ExternalActivityKind.strengthTraining,
          label: session.name,
          start: session.startTime,
          end: end,
          kcal: session.activeEnergyKilocalories,
        ),
      );
    }
    for (final activity in externals) {
      contributors.add(
        _Contributor(
          id: activity.platformUuid,
          source: StrainSource.external,
          kind: activity.kind,
          label: activity.sourceName,
          start: activity.start,
          end: activity.end,
          kcal: activity.activeEnergyKcal,
          activityName: activity.activityName,
        ),
      );
    }

    // Measured strain with nothing to attribute it to: the ledger still owes
    // the reader the whole number. All of it is ambient — never dropped.
    if (contributors.isEmpty) {
      return StrainLedger(
        strainScore: strainScore,
        entries: const [],
        ambientLoadPoints: strainScore.toDouble(),
      );
    }

    final dayLoad = _sanitize(day.trainingLoad);
    final energyBudget = _sanitize(day.activeEnergyKilocalories);
    final minuteBudget = _sanitize(day.exerciseMinutes);

    // Step 1 — overlap-adjusted effective minutes, so concurrent
    // different-kind sessions never double-count shared wall-clock minutes.
    // Minutes are computed from intervals CLIPPED to the day window
    // `[dayStart, dayEnd)` so a session spanning midnight only contributes
    // the portion that actually falls within this day; the entries' DISPLAY
    // start/end (and their sort order) stay the original, unclipped times.
    //
    // The window is built with the CALENDAR constructor (not
    // `date.add(Duration(days: 1))`): it normalizes a non-midnight `date` down
    // to its day start and lands on the true next calendar midnight even across
    // a DST transition (where a civil day is not 24h). UTC/local mode is
    // preserved from `day.date`.
    final d = day.date;
    final dayStart = d.isUtc
        ? DateTime.utc(d.year, d.month, d.day)
        : DateTime(d.year, d.month, d.day);
    final dayEnd = d.isUtc
        ? DateTime.utc(d.year, d.month, d.day + 1)
        : DateTime(d.year, d.month, d.day + 1);
    DateTime clampLo(DateTime t) => t.isBefore(dayStart) ? dayStart : t;
    DateTime clampHi(DateTime t) => t.isAfter(dayEnd) ? dayEnd : t;
    final clippedStarts = [for (final c in contributors) clampLo(c.start)];
    final clippedEnds = [for (final c in contributors) clampHi(c.end)];
    final effMin = _effectiveMinutes(clippedStarts, clippedEnds);

    // Step 2 — exercise-minute allocation, bounded by the day's measured
    // exerciseMinutes AND by each session's own effective minutes: a session
    // is never credited more elevated-HR minutes than either it or the day
    // measured.
    final sumEff = effMin.fold<double>(0, (a, b) => a + b);
    final exerciseScale = sumEff > 0
        ? math.min(1.0, minuteBudget / sumEff)
        : 0.0;
    final exerciseAu = [
      for (final m in effMin) m * exerciseScale * _exerciseMinuteToLoad,
    ];

    // Step 3 — energy allocation, bounded by the day's measured active
    // energy. Recorded kcal cover the contributor's full interval, so first
    // prorate them to the fraction inside this day. This mirrors the day
    // clipping already applied to exercise minutes above.
    final claimed = [
      for (var i = 0; i < contributors.length; i++)
        _sanitize(contributors[i].kcal, max: 1e6) *
            _inDayDurationRatio(
              start: contributors[i].start,
              end: contributors[i].end,
              clippedStart: clippedStarts[i],
              clippedEnd: clippedEnds[i],
            ),
    ];
    final claimedSum = claimed.fold<double>(0, (a, b) => a + b);
    final List<double> energyKcal;
    if (energyBudget <= 0) {
      // The day measured no active energy — invent none.
      energyKcal = List<double>.filled(contributors.length, 0.0);
    } else {
      final postCapClaimed = claimedSum > energyBudget
          ? [for (final k in claimed) k * (energyBudget / claimedSum)]
          : claimed;
      final postCapSum = postCapClaimed.fold<double>(0, (a, b) => a + b);
      final residual = math.max(0.0, energyBudget - postCapSum);

      final absentWeights = [
        for (var i = 0; i < contributors.length; i++)
          claimed[i] == 0 ? effMin[i] * _kindFactor(contributors[i].kind) : 0.0,
      ];
      final absentWeightSum = absentWeights.fold<double>(0, (a, b) => a + b);

      energyKcal = [
        for (var i = 0; i < contributors.length; i++)
          if (claimed[i] > 0)
            postCapClaimed[i]
          else if (absentWeightSum > 0 && residual > 0)
            residual * absentWeights[i] / absentWeightSum
          else
            0.0,
      ];
    }
    final energyAu = [for (final k in energyKcal) k * _energyToLoad];

    // Step 4 — session load, shares, and largest-remainder rounding.
    final sessionLoad = [
      for (var i = 0; i < contributors.length; i++) energyAu[i] + exerciseAu[i],
    ];
    // Floor the denominator at the component-derived budget so a degenerate
    // `day.trainingLoad` smaller than its own components can never push
    // `Σ share` above 1 by construction (the `shareSum > 1` cap below is then
    // only a float safety net, not the primary guarantee). In production
    // `dayLoad = E*0.08 + M*1.4 + steps*1.2 >= componentFloor`, so this is a
    // no-op there.
    final componentFloor =
        energyBudget * _energyToLoad + minuteBudget * _exerciseMinuteToLoad;
    final effectiveDayLoad = math.max(dayLoad, componentFloor);
    var shares = [
      for (final l in sessionLoad)
        effectiveDayLoad > 0 ? l / effectiveDayLoad : 0.0,
    ];
    final shareSum = shares.fold<double>(0, (a, b) => a + b);
    if (shareSum > 1) {
      shares = [for (final s in shares) s / shareSum];
    }
    final attributed = shares.fold<double>(0, (a, b) => a + b);
    final ambientShare = (1 - attributed).clamp(0.0, 1.0).toDouble();

    // Largest-remainder rounding to 0.1, over entries + ambient, targeting an
    // exact sum of strainScore.
    final rawTenths = <double>[
      for (final s in shares) s * strainScore * 10,
      ambientShare * strainScore * 10,
    ];
    final roundedTenths = _largestRemainder(rawTenths, strainScore * 10);

    final entries = <StrainLedgerEntry>[];
    for (var i = 0; i < contributors.length; i++) {
      final c = contributors[i];
      entries.add(
        StrainLedgerEntry(
          id: c.id,
          source: c.source,
          kind: c.kind,
          label: c.label,
          start: c.start,
          end: c.end,
          share: shares[i],
          loadPoints: roundedTenths[i] / 10.0,
          activityName: c.activityName,
        ),
      );
    }
    entries.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      if (byStart != 0) return byStart;
      final byEnd = a.end.compareTo(b.end);
      if (byEnd != 0) return byEnd;
      return a.id.compareTo(b.id);
    });

    final ambientLoadPoints = roundedTenths.last / 10.0;

    return StrainLedger(
      strainScore: strainScore,
      entries: entries,
      ambientLoadPoints: ambientLoadPoints,
    );
  }

  /// Round [rawTenths] (values already scaled to tenths) to integers whose sum
  /// equals [targetTenths], giving each the floor and distributing the leftover
  /// units to the largest fractional remainders (largest-remainder method).
  static List<int> _largestRemainder(List<double> rawTenths, int targetTenths) {
    final floors = rawTenths.map((v) => v.floor()).toList();
    final floorSum = floors.fold<int>(0, (a, b) => a + b);
    var deficit = targetTenths - floorSum;

    // Guard against tiny negative floors from floating error; clamp to >= 0.
    for (var i = 0; i < floors.length; i++) {
      if (floors[i] < 0) {
        deficit += floors[i];
        floors[i] = 0;
      }
    }

    if (deficit <= 0) return floors;

    final order = List<int>.generate(rawTenths.length, (i) => i)
      ..sort((a, b) {
        final ra = rawTenths[a] - rawTenths[a].floor();
        final rb = rawTenths[b] - rawTenths[b].floor();
        final byRem = rb.compareTo(ra);
        if (byRem != 0) return byRem;
        return a.compareTo(b);
      });
    for (var i = 0; i < deficit && i < order.length; i++) {
      floors[order[i]] += 1;
    }
    return floors;
  }
}

/// Overlap-adjusted ("effective") minutes for each contributor, computed from
/// [starts]/[ends] (which callers may have clipped to the day window — this
/// function is agnostic to that). A timeline of interval boundaries is built
/// from every positive-duration interval, and each sub-segment's minutes are
/// split evenly among the intervals that cover it. This guarantees
/// `Σ effectiveMinutes <= union wall-clock minutes`, so concurrent
/// different-kind sessions never double-count shared minutes. An interval
/// with `end <= start` (e.g. clipped entirely outside the day) contributes
/// zero-duration and is excluded.
List<double> _effectiveMinutes(List<DateTime> starts, List<DateTime> ends) {
  final effMin = List<double>.filled(starts.length, 0.0);

  final durMin = [
    for (var i = 0; i < starts.length; i++)
      math.max(0.0, ends[i].difference(starts[i]).inMilliseconds / 60000.0),
  ];
  final active = [
    for (var i = 0; i < starts.length; i++)
      if (durMin[i] > 0) i,
  ];
  if (active.isEmpty) return effMin;

  final boundaries = <DateTime>{
    for (final i in active) starts[i],
    for (final i in active) ends[i],
  }.toList()..sort();

  for (var k = 0; k < boundaries.length - 1; k++) {
    final segStart = boundaries[k];
    final segEnd = boundaries[k + 1];
    final segMin = segEnd.difference(segStart).inMilliseconds / 60000.0;
    if (segMin <= 0) continue;

    final covering = [
      for (final i in active)
        if (!starts[i].isAfter(segStart) && !ends[i].isBefore(segEnd)) i,
    ];
    if (covering.isEmpty) continue;

    final share = segMin / covering.length;
    for (final i in covering) {
      effMin[i] += share;
    }
  }

  return effMin;
}

class _Contributor {
  const _Contributor({
    required this.id,
    required this.source,
    required this.kind,
    required this.label,
    required this.start,
    required this.end,
    required this.kcal,
    this.activityName,
  });

  final String id;
  final StrainSource source;
  final ExternalActivityKind kind;
  final String label;
  final DateTime start;
  final DateTime end;
  final double? kcal;
  final String? activityName;
}
