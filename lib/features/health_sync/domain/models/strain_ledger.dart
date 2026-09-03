import 'package:equatable/equatable.dart';

import 'external_activity.dart';

/// Whether a ledger entry came from a Hustl-recorded session or an external
/// (platform-imported) workout.
enum StrainSource { hustl, external }

/// One attributed slice of the day's strain: a single session and the share of
/// the day's strain score it accounts for.
class StrainLedgerEntry extends Equatable {
  const StrainLedgerEntry({
    required this.id,
    required this.source,
    required this.kind,
    required this.label,
    required this.start,
    required this.end,
    required this.share,
    required this.loadPoints,
    this.activityName,
  });

  /// Stable identifier: the Hustl session id or the external platform UUID.
  final String id;
  final StrainSource source;

  /// Coarse activity kind. Hustl sessions are attributed as strength training.
  final ExternalActivityKind kind;

  /// Display label (session name / external source name).
  final String label;

  final DateTime start;
  final DateTime end;

  /// Fraction of the day's strain-implied total this entry accounts for (0–1).
  final double share;

  /// Points on the 0–21 strain scale attributed to this entry, rounded to one
  /// decimal place. Entry [loadPoints] plus the ledger's ambient remainder sum
  /// exactly to the day's strain score.
  final double loadPoints;

  /// Real platform activity name for an external workout of ANY kind (e.g.
  /// `Soccer`, `Tennis`, `Pilates`); null for Hustl sessions and for platform
  /// catch-all types (`OTHER`/`UNKNOWN`). When present the receipt shows it in
  /// place of the coarse [kind] label.
  final String? activityName;

  @override
  List<Object?> get props => [
    id,
    source,
    kind,
    label,
    start,
    end,
    share,
    loadPoints,
    activityName,
  ];
}

/// The day's strain, split across the sessions that drove it plus an ambient
/// remainder (everyday movement the aggregates measured but no session
/// explains). Never adds load: entry load points + [ambientLoadPoints] equal
/// the day's [strainScore] exactly.
class StrainLedger extends Equatable {
  const StrainLedger({
    required this.strainScore,
    required this.entries,
    required this.ambientLoadPoints,
  });

  /// An empty ledger — no measured strain (strain score <= 0). A day with
  /// measured strain but no sessions is NOT empty: it is an ambient-only
  /// ledger whose [ambientLoadPoints] equal the whole [strainScore].
  const StrainLedger.empty()
    : strainScore = 0,
      entries = const [],
      ambientLoadPoints = 0;

  /// The day's strain score (0–21) being explained.
  final int strainScore;

  /// Attributed entries, ordered chronologically by start time.
  final List<StrainLedgerEntry> entries;

  /// Points not attributable to any session (ambient daily movement), rounded
  /// to one decimal place.
  final double ambientLoadPoints;

  /// True when there is nothing measured to explain — i.e. exactly the
  /// [StrainLedger.empty] case (no measured strain, `strainScore <= 0`).
  /// An ambient-only day (measured strain, no session entries) is NOT empty:
  /// hiding it would suppress a real measured day.
  bool get isEmpty => strainScore <= 0;

  /// True when at least one session entry was attributed. The receipt's
  /// absence rule (plan 012) keys on THIS getter, not [isEmpty]: the UI hides
  /// the receipt when there are no session entries to itemize, even though an
  /// ambient-only ledger itself is not empty.
  bool get hasSessionEntries => entries.isNotEmpty;

  @override
  List<Object?> get props => [strainScore, entries, ambientLoadPoints];
}
