import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:hustl_app/core/coaching/coach_insight.dart';

import '../../domain/models/nutrition_target_plan.dart';

/// Maps the nutrition plan + weekly check-in payload into a [CoachInsight] for
/// the shared CoachCard, so the adaptive-target guidance reads clearly on the
/// Strategy screen instead of being trapped in a modal. Adherence-neutral by
/// design: over/under eating is never framed as bad and the tone never goes red.
///
/// Returns null when there is nothing meaningful to say yet (auto mode with the
/// check-in still loading) so the caller can simply omit the card.
CoachInsight? nutritionCoachInsight({
  required NutritionTargetPlan plan,
  required Map<String, dynamic>? checkIn,
  VoidCallback? onReviewCheckIn,
}) {
  // Manual mode: coaching is off — say so plainly rather than leaving the user
  // to wonder why nothing adapts.
  if (plan.mode == 'manual') {
    return const CoachInsight(
      headline: 'Coaching is off',
      why:
          'You’re in manual mode, so your targets won’t adjust. Turn coaching '
          'on below to get a weekly check-in that adapts them to your data.',
      confidence: CoachConfidence.none,
      tone: CoachTone.neutral,
    );
  }
  if (checkIn == null) return null;

  final available = checkIn['available'] == true;
  final why = (checkIn['why'] as Map?)?.cast<String, dynamic>() ?? const {};
  final coverage =
      (checkIn['coverage'] as Map?)?.cast<String, dynamic>() ?? const {};
  final deltas =
      (checkIn['deltas'] as Map?)?.cast<String, dynamic>() ?? const {};

  final tdee = (why['tdeeKcal'] as num?)?.toDouble();
  final windowDays = (why['windowDays'] as num?)?.toInt();
  final confidence = (why['confidence'] as num?)?.toDouble();
  final daysLogged = (coverage['daysWithCaloriesLogged'] as num?)?.toInt();
  final calorieDelta = (deltas['calories'] as num?)?.toDouble();

  final action = onReviewCheckIn == null
      ? null
      : CoachAction(label: 'Review check-in', onTap: onReviewCheckIn);

  // CALIBRATING — the estimator doesn't have enough signal yet (no TDEE / no
  // window / zero confidence). The plan is running on the profile estimate.
  final calibrating =
      tdee == null || windowDays == null || (confidence ?? 0) <= 0;
  if (calibrating) {
    return CoachInsight(
      headline: 'Getting to know you',
      why:
          'Your targets start from your profile for now. The more you log meals '
          'and weigh-ins, the better they fit you.',
      confidence: CoachConfidence.building,
      windowLabel: daysLogged == null
          ? null
          : '$daysLogged/7 days logged this week',
      tone: CoachTone.neutral,
      action: action,
    );
  }

  // tdee + windowDays are guaranteed non-null here (the calibrating guard above
  // returns when either is missing).
  final windowLabel = '$windowDays-day trend';

  // TARGETS CHANGED — a meaningful adjustment is ready to apply.
  if (available && calorieDelta != null && calorieDelta.abs() >= 10) {
    // Past the calibrating guard, tdee + windowDays are always present.
    return CoachInsight(
      headline: 'Calories ${_signed(calorieDelta, unit: '')} this week',
      why:
          'Your estimated burn is about ${tdee.toStringAsFixed(0)} kcal from '
          'your $windowDays-day trend, so your calorie target moves '
          '${_signed(calorieDelta)}.',
      confidence: _confidenceBand(confidence),
      windowLabel: windowLabel,
      tone: CoachTone.attention,
      action: action,
    );
  }

  // ON TRACK — no change needed; surface it as a positive, not a non-event.
  return CoachInsight(
    headline: 'You’re on track',
    why: 'Your trend is tracking your target — no change needed this week.',
    confidence: _confidenceBand(confidence),
    windowLabel: windowLabel,
    tone: CoachTone.positive,
    action: action,
  );
}

CoachConfidence _confidenceBand(double? confidence) {
  final c = confidence ?? 0;
  if (c >= 0.66) return CoachConfidence.high;
  if (c >= 0.33) return CoachConfidence.medium;
  return CoachConfidence.building;
}

String _signed(num v, {String unit = ' kcal'}) {
  final d = v.toDouble();
  final sign = d >= 0 ? '+' : '−';
  final abs = d.abs();
  final t = abs % 1 == 0 ? abs.toStringAsFixed(0) : abs.toStringAsFixed(1);
  return '$sign$t$unit';
}
