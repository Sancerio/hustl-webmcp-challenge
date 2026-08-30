import 'package:hustl_app/core/coaching/coach_insight.dart';

import '../utils/weight_unit.dart';

/// Builds the scale-vs-trend [CoachInsight] for the Weight screen so it reads as
/// the same Coach as nutrition + training. Adherence-neutral: a goal-aligned
/// trend is positive, drift the wrong way is a calm amber nudge — never red.
///
/// [weeklyRateKg] is the smoothed weekly rate (kg/week, signed), [goalType] is
/// 'lose' | 'gain' | 'maintain', [unit] formats the rate in the user's unit, and
/// [weighInCount] sets the confidence cue while the data fills in.
CoachInsight buildWeightCoachInsight({
  required double? weeklyRateKg,
  required String? goalType,
  required WeightUnit unit,
  required int weighInCount,
}) {
  const why =
      'Trend smooths out the day-to-day scale noise — follow the line, not the '
      'number on any single morning.';

  final confidence = weighInCount >= 14
      ? CoachConfidence.high
      : weighInCount >= 5
      ? CoachConfidence.medium
      : CoachConfidence.building;
  final windowLabel = weighInCount > 0 ? '$weighInCount weigh-ins' : null;

  if (weeklyRateKg == null) {
    return CoachInsight(
      headline: 'Building your trend',
      why:
          'Keep logging weigh-ins and the smoothed trend will settle so you '
          'can read your real direction.',
      confidence: CoachConfidence.building,
      windowLabel: windowLabel,
      tone: CoachTone.neutral,
    );
  }

  // ~0 movement reads as steady regardless of goal.
  if (weeklyRateKg.abs() < 0.05) {
    return CoachInsight(
      headline: 'Holding steady',
      why: why,
      confidence: confidence,
      windowLabel: windowLabel,
      tone: goalType == 'maintain' ? CoachTone.positive : CoachTone.neutral,
    );
  }

  final goingUp = weeklyRateKg > 0;
  final rateText =
      '${unit.value(weeklyRateKg.abs(), decimals: 2)} ${unit.suffix}/wk';
  final headline = goingUp
      ? 'Trending up ~$rateText'
      : 'Trending down ~$rateText';

  // On-track toward the goal -> positive; against it -> attention (amber).
  final bool onTrack;
  switch (goalType) {
    case 'gain':
      onTrack = goingUp;
    case 'maintain':
      onTrack = false; // any real movement is drift for maintain
    case 'lose':
    default:
      onTrack = !goingUp;
  }

  return CoachInsight(
    headline: headline,
    why: why,
    confidence: confidence,
    windowLabel: windowLabel,
    tone: onTrack ? CoachTone.positive : CoachTone.attention,
  );
}
