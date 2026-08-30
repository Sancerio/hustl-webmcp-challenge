import '../models/daily_recovery_snapshot.dart';

/// Kind, non-medical, sentence-case copy for the four warm readiness bands and
/// the confidence / calibration states. Pure domain helpers so the dashboard
/// coaching panel and the insights deck never drift apart.
///
/// All copy is an invitation, never a command, never a diagnosis. The lowest
/// band ("Recharge") reads as a gentle nudge that ends with reassurance.
class RecoveryBandCopy {
  const RecoveryBandCopy._();

  /// The headline beside the recovery ring (e.g. "You're in a good spot.").
  /// Falls back to the calibration line while the baseline is still building.
  static String headline(DailyRecoverySnapshot? snapshot) {
    if (snapshot == null) return 'Building your baseline';
    if (snapshot.isCalibrating || snapshot.flowBand == null) {
      return _calibratingHeadline(snapshot);
    }
    return headlineForBand(snapshot.flowBand!);
  }

  /// The longer suggestive guidance paragraph for the coaching panel.
  static String guidance(DailyRecoverySnapshot? snapshot) {
    if (snapshot == null || snapshot.flowBand == null) {
      return _calibratingGuidance(snapshot);
    }
    if (snapshot.isCalibrating) {
      return '${_calibratingGuidance(snapshot)} ${_softBandGuidance(snapshot.flowBand!)}';
    }
    final base = _bandGuidance(snapshot.flowBand!);
    if (snapshot.confidence == RecoveryConfidence.low) {
      return 'This is a rough, sleep-based estimate while your signals fill in. $base';
    }
    return base;
  }

  /// Short label describing how much to trust today's number.
  static String confidenceLabel(RecoveryConfidence? confidence) {
    switch (confidence) {
      case RecoveryConfidence.high:
        return 'High confidence';
      case RecoveryConfidence.medium:
        return 'Medium confidence';
      case RecoveryConfidence.low:
        return 'Rough estimate';
      case null:
        return 'Building confidence';
    }
  }

  /// The label for the discrete "learn more" affordance on the recovery card,
  /// which opens the recovery & readiness explainer. Frames the explainer as
  /// Hustl describing its own reasoning.
  static const String learnMoreLabel = 'How we read this';

  /// The "building your baseline (n/14)" calibration line, or null when the
  /// snapshot is already calibrated.
  static String? calibrationLabel(DailyRecoverySnapshot? snapshot) {
    if (snapshot == null) return null;
    if (!snapshot.isCalibrating) return null;
    final coverage = snapshot.baselineCoverageDays.clamp(
      0,
      DailyRecoverySnapshot.calibrationTargetDays,
    );
    return 'Building your baseline ($coverage/${DailyRecoverySnapshot.calibrationTargetDays})';
  }

  /// Kind, non-illness phrasing for anomaly flags. Never says "you are sick".
  static String? anomalyNote(DailyRecoverySnapshot? snapshot) {
    if (snapshot == null || snapshot.anomalyFlags.isEmpty) return null;
    return 'Your markers look a bit off baseline today — be gentle with yourself.';
  }

  /// The standing non-medical disclaimer for the recovery surface.
  static const String disclaimer =
      "Hustl's recovery score is a wellness estimate from your activity and "
      'sleep, not medical advice.';

  /// Band-only headline (e.g. "You're in a good spot."), independent of a
  /// snapshot. Used where a band is derived directly (e.g. legacy snapshots).
  static String headlineForBand(RecoveryFlowBand band) {
    switch (band) {
      case RecoveryFlowBand.charged:
        return "You're well recovered.";
      case RecoveryFlowBand.ready:
        return "You're in a good spot.";
      case RecoveryFlowBand.steady:
        return 'A bit below your usual.';
      case RecoveryFlowBand.recharge:
        return "Your body's asking for a lighter day.";
    }
  }

  /// Band-only suggestive guidance, independent of a snapshot.
  static String guidanceForBand(RecoveryFlowBand band) => _bandGuidance(band);

  static String _bandGuidance(RecoveryFlowBand band) {
    switch (band) {
      case RecoveryFlowBand.charged:
        return "Great day to push if you're feeling it.";
      case RecoveryFlowBand.ready:
        return 'Solid day to train as planned.';
      case RecoveryFlowBand.steady:
        return 'Train, but dial volume or intensity back about 10-20% and listen to how you feel.';
      case RecoveryFlowBand.recharge:
        return "Consider easy movement, mobility, or rest. You'll bounce back.";
    }
  }

  static String _softBandGuidance(RecoveryFlowBand band) {
    switch (band) {
      case RecoveryFlowBand.charged:
      case RecoveryFlowBand.ready:
        return 'Early signs look good — train as you feel.';
      case RecoveryFlowBand.steady:
      case RecoveryFlowBand.recharge:
        return 'Treat any low reading gently until the baseline settles.';
    }
  }

  static String _calibratingHeadline(DailyRecoverySnapshot? snapshot) {
    final label = calibrationLabel(snapshot);
    return label ?? 'Building your baseline';
  }

  static String _calibratingGuidance(DailyRecoverySnapshot? snapshot) {
    if (snapshot == null) {
      return 'Keep syncing overnight recovery to unlock daily training guidance and baselines.';
    }
    final remaining = snapshot.calibrationDaysRemaining;
    if (remaining <= 0) {
      return 'A few more nights of data will sharpen your readiness number.';
    }
    final dayWord = remaining == 1 ? 'day' : 'days';
    return "We're learning your normal — about $remaining more $dayWord to go.";
  }
}
