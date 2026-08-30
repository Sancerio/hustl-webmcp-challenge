import 'package:hustl_app/core/coaching/coach_insight.dart';

import '../../../domain/models/daily_recovery_snapshot.dart';
import '../../../domain/usecases/recovery_band_copy.dart';
import 'health_dashboard_copy.dart';

/// Maps the recovery/readiness snapshot into the shared [CoachInsight] so the
/// recovery surface reads as the SAME coach as training + nutrition. On top of
/// the band guidance it adds a plain-language "why it matters" clause — the one
/// gap in the otherwise-strong recovery copy.
///
/// Confidence and the "How we read this" action are intentionally LEFT OFF the
/// card here: the recovery hero ring already shows the confidence chip and the
/// learn-more link right beside the score, so the card carries the eyebrow,
/// the (now-prominent) headline and the why — no duplication.
CoachInsight recoveryCoachInsight(DailyRecoverySnapshot? snapshot) {
  final band = snapshot?.flowBand;
  final calibrating =
      snapshot == null || snapshot.isCalibrating || band == null;
  final hasAnomaly = RecoveryBandCopy.anomalyNote(snapshot) != null;

  // coachCopy already folds in the kind anomaly note when markers look off.
  final why = StringBuffer(coachCopy(snapshot));
  // !calibrating proves band is non-null (calibrating includes band == null).
  if (!calibrating) {
    why
      ..write(' ')
      ..write(recoveryWhyItMatters(band));
  }

  return CoachInsight(
    headline: coachHeadline(snapshot),
    why: why.toString(),
    confidence: CoachConfidence.none,
    tone: _tone(band, calibrating, hasAnomaly),
  );
}

/// The plain-language "why this matters" clause for a readiness [band]. Public so
/// the shared "explain any number" recovery mapper restates the SAME vetted copy
/// rather than duplicating it — keeping one source of truth for the why.
String recoveryWhyItMatters(RecoveryFlowBand band) {
  switch (band) {
    case RecoveryFlowBand.charged:
    case RecoveryFlowBand.ready:
      return 'Higher readiness means your body can handle a harder session.';
    case RecoveryFlowBand.steady:
      return 'Middling readiness is a cue to autoregulate — train to feel.';
    case RecoveryFlowBand.recharge:
      return 'Low readiness means recovery work pays off more than pushing today.';
  }
}

CoachTone _tone(RecoveryFlowBand? band, bool calibrating, bool hasAnomaly) {
  if (hasAnomaly) return CoachTone.attention;
  if (calibrating || band == null) return CoachTone.neutral;
  switch (band) {
    case RecoveryFlowBand.charged:
    case RecoveryFlowBand.ready:
      return CoachTone.positive;
    case RecoveryFlowBand.steady:
      return CoachTone.neutral;
    case RecoveryFlowBand.recharge:
      return CoachTone.attention;
  }
}
