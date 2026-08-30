import 'package:flutter/widgets.dart';
import 'package:hustl_app/core/coaching/coach_insight.dart';
import 'package:hustl_app/core/widgets/coach_card.dart';

/// Plain-language energy-balance verdict shown as the lead CoachCard on Insights.
///
/// Honest about TDEE: when [avgTdee] is null we do NOT claim a TDEE comparison —
/// we compare to the target and say so, and the confidence reads "building".
CoachInsight energyVerdictInsight({
  required double avgIntake,
  required double avgTarget,
  required double? avgTdee,
  required int rangeDays,
}) {
  final hasTdee = avgTdee != null;
  final compare = hasTdee ? avgTdee : avgTarget;
  final diff = avgIntake - compare; // negative = deficit, positive = surplus.
  final magnitude = diff.abs();
  final basis = hasTdee ? 'TDEE' : 'target';

  final String headline;
  if (magnitude < 75) {
    headline = hasTdee
        ? 'Eating around maintenance'
        : 'Right around your target';
  } else if (diff < 0) {
    headline = magnitude > 500 ? 'In a large deficit' : 'In a slight deficit';
  } else {
    headline = magnitude > 500 ? 'In a large surplus' : 'In a slight surplus';
  }

  final why =
      'Avg intake ${avgIntake.round()} vs ${hasTdee ? '~' : ''}'
      '${compare.round()} kcal $basis over the last $rangeDays days.';

  return CoachInsight(
    headline: headline,
    why: why,
    // Adherence-neutral: a deficit/surplus is information, not a verdict to feel
    // bad about — keep the tone calm (neutral), never an alarm.
    tone: CoachTone.neutral,
    confidence: hasTdee ? CoachConfidence.high : CoachConfidence.building,
    windowLabel: hasTdee ? '$rangeDays-day average' : 'TDEE still calibrating',
  );
}

/// The energy verdict rendered with the shared [CoachCard] so it reads as the
/// same Coach used across the app — not a look-alike banner.
class EnergyVerdictBanner extends StatelessWidget {
  const EnergyVerdictBanner({super.key, required this.insight});

  final CoachInsight insight;

  @override
  Widget build(BuildContext context) => CoachCard(insight: insight);
}
