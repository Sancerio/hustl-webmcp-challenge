import 'package:equatable/equatable.dart';

import 'health_metric_sample.dart';

enum HrvKind { sdnn, rmssd }

/// Legacy three-band readiness split. Kept for back-compat with existing
/// dashboard surfaces (`bandLabel`, the baselines grid). New flow surfaces
/// should prefer [RecoveryFlowBand].
enum RecoveryReadinessBand { low, moderate, high }

/// The four warm readiness bands surfaced across the training flow (spec
/// "Banding"). Ordered from the gentlest (lowest score) to the strongest.
///
/// Never alarmist or medical: the lowest band is a kind invitation to recharge,
/// tinted warm amber rather than a harsh red.
enum RecoveryFlowBand { recharge, steady, ready, charged }

extension RecoveryFlowBandDisplay on RecoveryFlowBand {
  /// Human label for the band.
  String get displayLabel {
    switch (this) {
      case RecoveryFlowBand.charged:
        return 'Charged';
      case RecoveryFlowBand.ready:
        return 'Ready';
      case RecoveryFlowBand.steady:
        return 'Steady';
      case RecoveryFlowBand.recharge:
        return 'Recharge';
    }
  }

  /// Semantic tint hint. The UI maps this onto `colorScheme`/`AppColors`
  /// tokens — never a hard-coded color here. The lowest band is warm amber,
  /// never a harsh red.
  RecoveryBandTint get tintHint {
    switch (this) {
      case RecoveryFlowBand.charged:
        return RecoveryBandTint.vital;
      case RecoveryFlowBand.ready:
        return RecoveryBandTint.calm;
      case RecoveryFlowBand.steady:
        return RecoveryBandTint.soft;
      case RecoveryFlowBand.recharge:
        return RecoveryBandTint.warmAmber;
    }
  }

  /// Maps the four-band model back onto the legacy three-band enum so existing
  /// surfaces keep working. Charged/Ready collapse into [high]/[moderate].
  RecoveryReadinessBand get legacyBand {
    switch (this) {
      case RecoveryFlowBand.charged:
        return RecoveryReadinessBand.high;
      case RecoveryFlowBand.ready:
        return RecoveryReadinessBand.moderate;
      case RecoveryFlowBand.steady:
        return RecoveryReadinessBand.moderate;
      case RecoveryFlowBand.recharge:
        return RecoveryReadinessBand.low;
    }
  }
}

/// Semantic tint hint for a readiness band. The presentation layer maps each
/// value to `colorScheme`/`AppColors` tokens; this enum carries intent only so
/// the domain never reaches for a hard-coded color.
///
/// - [vital]: strongest, well-recovered (token: a positive/secondary accent).
/// - [calm]: good, train-as-planned (token: a calm teal/secondary accent).
/// - [soft]: a bit below usual (token: a quiet neutral/tertiary accent).
/// - [warmAmber]: gentle recharge invitation (token: warm amber — never red).
enum RecoveryBandTint { warmAmber, soft, calm, vital }

/// How much trust to place in today's readiness number (spec "Confidence
/// level"). Low confidence should widen bands and soften copy.
enum RecoveryConfidence { high, medium, low }

class DailyRecoverySnapshot extends Equatable {
  const DailyRecoverySnapshot({
    required this.date,
    this.sleepDurationMinutes,
    this.timeInBedMinutes,
    this.remSleepMinutes,
    this.deepSleepMinutes,
    this.lightSleepMinutes,
    this.awakeMinutes,
    this.sleepCompleteness = HealthDataCompleteness.unknown,
    this.sleepNeedMinutes,
    this.sleepPerformanceScore,
    this.sleepConsistencyScore,
    this.sleepEfficiency,
    this.sleepStart,
    this.sleepEnd,
    this.hrvValue,
    this.hrvKind,
    this.restingHeartRateBpm,
    this.respiratoryRate,
    this.bloodOxygenPercent,
    this.temperatureCelsius,
    this.temperatureDeltaCelsius,
    this.steps,
    this.activeEnergyKilocalories,
    this.exerciseMinutes,
    this.trainingLoad,
    this.acuteLoad7,
    this.chronicLoad42,
    this.loadRatio,
    this.recoveryScore,
    this.readinessScore,
    this.strainScore,
    this.typicalStrainScore,
    this.baselineCoverageDays = 0,
    this.band,
    this.flowBand,
    this.confidence,
    this.isCalibrating = false,
    this.anomalyFlags = const [],
  });

  /// Number of days of baseline coverage required before a confident score is
  /// shown. Below this, surfaces present a gentle "building your baseline"
  /// calibration state instead of a hard number.
  static const int calibrationTargetDays = 14;

  final DateTime date;
  final double? sleepDurationMinutes;
  final double? timeInBedMinutes;
  final double? remSleepMinutes;
  final double? deepSleepMinutes;
  final double? lightSleepMinutes;
  final double? awakeMinutes;
  final HealthDataCompleteness sleepCompleteness;
  final double? sleepNeedMinutes;
  final double? sleepPerformanceScore;
  final double? sleepConsistencyScore;
  final double? sleepEfficiency;

  /// Earliest start / latest end of last night's timestamped sleep-segment
  /// samples (asleep/REM/deep/light/awake), attributed to this snapshot's
  /// [date] the same way the aggregator attributes minutes — by the sample's
  /// end-time day (the wake day). Null when no timestamped sleep points exist
  /// for the night (e.g. a provider that only reports a daily total).
  final DateTime? sleepStart;
  final DateTime? sleepEnd;

  final double? hrvValue;
  final HrvKind? hrvKind;
  final double? restingHeartRateBpm;
  final double? respiratoryRate;
  final double? bloodOxygenPercent;
  final double? temperatureCelsius;
  final double? temperatureDeltaCelsius;
  final int? steps;
  final double? activeEnergyKilocalories;
  final double? exerciseMinutes;
  final double? trainingLoad;
  final double? acuteLoad7;
  final double? chronicLoad42;
  final double? loadRatio;
  final double? recoveryScore;
  final double? readinessScore;
  final int? strainScore;

  /// The user's typical daily strain — [strainScoreForLoad] of the median
  /// training load over the trailing 28 days that carried a real reading. Null
  /// while calibrating (fewer than 7 qualifying days). Surfaced under the strain
  /// total as a "typical {n}" comparison line.
  final int? typicalStrainScore;

  final int baselineCoverageDays;

  /// Legacy three-band readiness band. Derived from [flowBand] when present so
  /// existing surfaces keep rendering.
  final RecoveryReadinessBand? band;

  /// The four warm readiness bands (Charged / Ready / Steady / Recharge).
  final RecoveryFlowBand? flowBand;

  /// Trust level for today's score, driven by signal count + baseline coverage.
  final RecoveryConfidence? confidence;

  /// True while the baseline is still maturing (coverage below
  /// [calibrationTargetDays]) and the surface should present a gentle
  /// "building your baseline (n/14)" state rather than a hard score.
  final bool isCalibrating;

  final List<String> anomalyFlags;

  bool get hasRecoveryData =>
      sleepPerformanceScore != null ||
      hrvValue != null ||
      restingHeartRateBpm != null ||
      respiratoryRate != null;

  /// Number of baseline days still needed before the score leaves the
  /// "building your baseline" calibration state. Clamped to >= 0.
  int get calibrationDaysRemaining {
    final remaining = calibrationTargetDays - baselineCoverageDays;
    return remaining < 0 ? 0 : remaining;
  }

  @override
  List<Object?> get props => [
    date,
    sleepDurationMinutes,
    timeInBedMinutes,
    remSleepMinutes,
    deepSleepMinutes,
    lightSleepMinutes,
    awakeMinutes,
    sleepCompleteness,
    sleepNeedMinutes,
    sleepPerformanceScore,
    sleepConsistencyScore,
    sleepEfficiency,
    sleepStart,
    sleepEnd,
    hrvValue,
    hrvKind,
    restingHeartRateBpm,
    respiratoryRate,
    bloodOxygenPercent,
    temperatureCelsius,
    temperatureDeltaCelsius,
    steps,
    activeEnergyKilocalories,
    exerciseMinutes,
    trainingLoad,
    acuteLoad7,
    chronicLoad42,
    loadRatio,
    recoveryScore,
    readinessScore,
    strainScore,
    typicalStrainScore,
    baselineCoverageDays,
    band,
    flowBand,
    confidence,
    isCalibrating,
    anomalyFlags,
  ];
}
