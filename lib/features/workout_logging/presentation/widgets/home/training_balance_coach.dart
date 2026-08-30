import 'package:flutter/widgets.dart';
import 'package:hustl_app/core/coaching/coach_insight.dart';

import '../../../domain/services/next_workout_focus_service.dart';

/// Maps the training-balance [NextWorkoutFocusPlan] onto the shared
/// [CoachInsight] so it renders in the one coach card pattern used app-wide.
///
/// Tone: a "build"/"rebalance" suggestion is an amber nudge (attention); a
/// "balanced" read is emerald (positive); an early-signal read is a neutral
/// blue. Confidence and window label are taken straight from the plan — the
/// plan computes both over the SAME period the Training-balance detail uses, so
/// the card never asserts "high confidence · last 4 weeks" while the detail
/// shows a contradicting verdict over a different window.
CoachInsight trainingBalanceInsight(
  NextWorkoutFocusPlan focus, {
  required VoidCallback onSeeDetails,
}) {
  final tone = switch (focus.tone) {
    NextWorkoutFocusTone.balanced => CoachTone.positive,
    NextWorkoutFocusTone.build => CoachTone.attention,
    NextWorkoutFocusTone.rebalance => CoachTone.attention,
    NextWorkoutFocusTone.earlySignal => CoachTone.neutral,
  };
  // A still-building read hides its window qualifier (it's an early signal, not
  // a settled window claim); otherwise surface the actual period window.
  final showWindow = focus.confidence != CoachConfidence.building;
  return CoachInsight(
    headline: focus.headline,
    why: focus.detail,
    tone: tone,
    confidence: focus.confidence,
    windowLabel: showWindow ? focus.windowLabel : null,
    // Optional readiness context line ("should I push today?") — quiet footnote
    // under the balance verdict; null on ordinary/thin-data days.
    note: focus.readinessNote,
    // The action always opens the Training-balance breakdown (which itself lists
    // any suggested work), so label it for that destination rather than
    // promising an exercises view that doesn't exist.
    action: CoachAction(label: 'See training balance', onTap: onSeeDetails),
  );
}
