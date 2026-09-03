import '../models/daily_recovery_snapshot.dart';

/// Pure, kind, non-medical copy + gating for the R3 in-flow recovery surfaces:
/// the readiness-aware rest suggestion and the post-workout strain-vs-recovery
/// note. Keeping the decisions here (not in widgets) means the gating is
/// directly testable and the two surfaces never drift from the band copy.
///
/// Every helper is STRICTLY ADDITIVE: when the snapshot is absent, low-signal,
/// or not in a low-readiness state, the suggestion/note collapses to `null` and
/// the surrounding flow renders exactly as today.
class RecoveryFlowCopy {
  const RecoveryFlowCopy._();

  /// How many seconds the readiness-aware rest suggestion adds when accepted.
  static const int restBumpSeconds = 30;

  /// Whether to offer the "a bit more rest" suggestion for [snapshot].
  ///
  /// Only a genuinely LOW-readiness day qualifies, and never on thin data:
  /// - `Recharge` (lowest band) → yes.
  /// - `Steady` (a bit below usual) → only when confidence is NOT low, so a
  ///   noisy single-signal day never nudges more rest on its own.
  /// - `Ready` / `Charged` / calibrating / no band / no data → no.
  ///
  /// This mirrors the spec's "a single noisy signal must never push into the
  /// lowest band on its own" rule for the rest nudge.
  static bool shouldSuggestMoreRest(DailyRecoverySnapshot? snapshot) {
    if (snapshot == null || !snapshot.hasRecoveryData) return false;
    if (snapshot.isCalibrating) return false;
    final band = snapshot.flowBand;
    if (band == null) return false;
    switch (band) {
      case RecoveryFlowBand.recharge:
        return true;
      case RecoveryFlowBand.steady:
        return snapshot.confidence != RecoveryConfidence.low;
      case RecoveryFlowBand.ready:
      case RecoveryFlowBand.charged:
        return false;
    }
  }

  /// The single quiet line shown in the rest picker on a low-readiness day.
  /// Kind, suggestive, never a command — and never shown unless
  /// [shouldSuggestMoreRest] is true.
  static const String restSuggestionLine =
      'Low readiness today — consider a bit more rest.';

  /// The one-tap accept label that bumps the suggested rest by
  /// [restBumpSeconds]. Suffix only; callers prefix it with a "+".
  static String restSuggestionAction() => 'Use +${restBumpSeconds}s';

  /// The post-workout strain-vs-recovery note (spec "Post-workout note"), or
  /// `null` to render nothing. Gated on a present, reasonably-confident snapshot
  /// that actually carries recovery signal — otherwise the summary is identical
  /// to today.
  ///
  /// Combines the just-finished session's effort ([strainScore], 0–21) with the
  /// day's band into ONE kind, non-medical line. Low band + high strain reads as
  /// a gentle "lighter day tomorrow"; a good band reads as quiet affirmation.
  static String? postWorkoutNote(DailyRecoverySnapshot? snapshot) {
    if (snapshot == null || !snapshot.hasRecoveryData) return null;
    if (snapshot.isCalibrating) return null;
    if (snapshot.confidence == RecoveryConfidence.low) return null;
    final band = snapshot.flowBand;
    if (band == null) return null;

    final strain = snapshot.strainScore;
    final bigSession = strain != null && strain >= 14;

    switch (band) {
      case RecoveryFlowBand.recharge:
        return bigSession
            ? 'Big session today. Your body may want a lighter day '
                  'tomorrow — prioritise sleep.'
            : 'Nice work. Your recovery is asking for a gentle day '
                  'tomorrow — go easy and rest well.';
      case RecoveryFlowBand.steady:
        return bigSession
            ? 'Strong effort today. You\'re a touch below your usual, so '
                  'keep tomorrow lighter if you can.'
            : 'Solid work. You\'re recovering steadily — listen to how you '
                  'feel tomorrow.';
      case RecoveryFlowBand.ready:
      case RecoveryFlowBand.charged:
        return bigSession
            ? 'Big session, and you\'re recovering well. Refuel and rest to '
                  'keep the momentum.'
            : 'Solid work. You\'re recovering well.';
    }
  }

  /// Whether the post-workout note should render at all. Convenience mirror of
  /// [postWorkoutNote] returning non-null, for callers that gate layout first.
  static bool hasPostWorkoutNote(DailyRecoverySnapshot? snapshot) =>
      postWorkoutNote(snapshot) != null;
}
