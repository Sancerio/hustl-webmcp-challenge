import 'dart:math' as math;

import '../models/daily_recovery_snapshot.dart';
import '../models/health_metric_sample.dart';
import 'build_sleep_sessions.dart';
import 'hrv_platform_resolver.dart';

/// A robust trailing baseline: a median centre with a MAD (median absolute
/// deviation) dispersion, both computed over up to a 28-day window.
///
/// Using median + MAD instead of mean + standard deviation de-sensitizes the
/// baseline to a single bad night (one outlier cannot poison the centre).
class _RobustBaseline {
  const _RobustBaseline({required this.center, required this.spread});

  final double center;

  /// Dispersion as a MAD scaled to a standard-deviation-equivalent
  /// (`1.4826 * MAD`). Always strictly positive so deviations stay finite.
  final double spread;
}

class BuildDailyRecoverySnapshotsUseCase {
  /// Trailing window (days) for per-signal baselines.
  static const int baselineWindowDays = 28;

  /// Minimum prior days required before a baseline is trusted; below this the
  /// per-signal score is neutral (50).
  static const int minBaselineDays = 3;

  List<DailyRecoverySnapshot> call({
    required List<HealthMetricSample> metrics,
    DateTime? now,
  }) {
    if (metrics.isEmpty) return const [];

    final sleepSessions = const BuildSleepSessionsUseCase()(metrics, now: now);
    final sleepByDate = {
      for (final session in sleepSessions) session.localDate: session,
    };
    final grouped = <DateTime, List<HealthMetricSample>>{};
    for (final sample in metrics) {
      final localEnd = sample.localEndTime;
      final date = DateTime(localEnd.year, localEnd.month, localEnd.day);
      grouped.putIfAbsent(date, () => []).add(sample);
    }

    final dates = grouped.keys.toList()..sort((a, b) => a.compareTo(b));
    final firstDate = dates.first;
    final lastDate = dates.last;
    final rawDays = <_RawDayRecovery>[];

    for (
      DateTime date = firstDate;
      !date.isAfter(lastDate);
      date = date.add(const Duration(days: 1))
    ) {
      final samples = List<HealthMetricSample>.from(grouped[date] ?? const [])
        ..sort((a, b) => a.endTime.compareTo(b.endTime));

      final sleepSession = sleepByDate[date];
      final completeSleep = sleepSession?.isComplete == true;
      final exerciseMinutes = _sumMinutes(
        samples,
        HealthMetricType.exerciseTime,
      );
      final activeEnergy = _sumDeduplicatedByInterval(
        samples,
        HealthMetricType.activeEnergyBurned,
      );
      final steps = _sumDeduplicatedByInterval(
        samples,
        HealthMetricType.steps,
      )?.round();

      final (hrvValue, hrvKind) = _selectHrv(samples);

      final restingHr = _average(samples, HealthMetricType.restingHeartRate);
      final respiratory = _average(samples, HealthMetricType.respiratoryRate);
      final bloodOxygen = _average(samples, HealthMetricType.bloodOxygen);
      final temperature = _average(samples, HealthMetricType.bodyTemperature);

      rawDays.add(
        _RawDayRecovery(
          date: date,
          sleepMinutes: completeSleep ? sleepSession!.durationMinutes : null,
          timeInBedMinutes: completeSleep
              ? sleepSession!.timeInBedMinutes
              : null,
          remMinutes: completeSleep ? sleepSession!.remMinutes : null,
          deepMinutes: completeSleep ? sleepSession!.deepMinutes : null,
          lightMinutes: completeSleep ? sleepSession!.lightMinutes : null,
          awakeMinutes: completeSleep ? sleepSession!.awakeMinutes : null,
          sleepStart: sleepSession?.startTime,
          sleepEnd: sleepSession?.endTime,
          sleepCompleteness:
              sleepSession?.completeness ?? HealthDataCompleteness.unknown,
          hrvValue: hrvValue,
          hrvKind: hrvKind,
          restingHeartRateBpm: restingHr,
          respiratoryRate: respiratory,
          bloodOxygenPercent: bloodOxygen,
          temperatureCelsius: temperature,
          steps: steps,
          activeEnergyKilocalories: activeEnergy,
          exerciseMinutes: exerciseMinutes > 0 ? exerciseMinutes : null,
        ),
      );
    }

    return _score(rawDays);
  }

  List<DailyRecoverySnapshot> _score(List<_RawDayRecovery> rawDays) {
    final snapshots = <DailyRecoverySnapshot>[];
    final loadHistory = <double>[];

    for (var i = 0; i < rawDays.length; i++) {
      final day = rawDays[i];
      final previous = rawDays.take(i).toList();

      final trainingLoad = _computeTrainingLoad(day);
      loadHistory.add(trainingLoad);
      final acuteLoad7 = _averageNumbers(
        loadHistory.skip(loadHistory.length > 7 ? loadHistory.length - 7 : 0),
      );
      final chronicLoad42 = _averageNumbers(
        loadHistory.skip(loadHistory.length > 42 ? loadHistory.length - 42 : 0),
      );
      final loadRatio =
          acuteLoad7 != null && chronicLoad42 != null && chronicLoad42 > 0
          ? acuteLoad7 / chronicLoad42
          : null;

      final baselineCoverage = previous
          .where(
            (entry) =>
                entry.hrvValue != null ||
                entry.restingHeartRateBpm != null ||
                entry.sleepMinutes != null,
          )
          .length;

      // Personalize sleep need to the user's habitual duration (median over the
      // trailing window), then add a modest acute-load bump. Debt is NOT folded
      // into need — it is a deficit measured against this stable anchor and is
      // surfaced separately by the insight layer.
      final habitualSleepBase = _habitualSleepBase(previous);
      final sleepNeedMinutes = _sleepNeedMinutes(
        trainingLoad: trainingLoad,
        habitualBase: habitualSleepBase,
      );

      final sleepPerformance = _sleepPerformance(
        day,
        sleepNeedMinutes: sleepNeedMinutes,
        previous: previous,
      );

      // Same-kind HRV baseline: never mix SDNN and RMSSD into one trend.
      final hrvBaseline = _baseline(
        previous
            .where((entry) => entry.hrvKind == day.hrvKind)
            .map((entry) => entry.hrvValue)
            .whereType<double>(),
      );
      final hrvScore = _scoreAgainstBaseline(
        value: day.hrvValue,
        baseline: hrvBaseline,
        positiveBetter: true,
      );
      final restingHrScore = _scoreAgainstBaseline(
        value: day.restingHeartRateBpm,
        baseline: _baseline(
          previous
              .map((entry) => entry.restingHeartRateBpm)
              .whereType<double>(),
        ),
        positiveBetter: false,
      );

      final temperatureBaseline = _baselineCenter(
        previous.map((entry) => entry.temperatureCelsius).whereType<double>(),
      );
      final temperatureDelta =
          day.temperatureCelsius != null && temperatureBaseline != null
          ? day.temperatureCelsius! - temperatureBaseline
          : null;

      // HRV-led recovery, renormalized over whatever core signals are present
      // so a sleep-only user still gets a sleep-based estimate.
      final recoveryBase = _weightedAverage([
        (hrvScore, 0.35),
        (restingHrScore, 0.25),
        (sleepPerformance, 0.30),
      ]);

      // Respiratory rate + temperature become an illness GATE: they can only
      // lower the score when clearly off baseline, never average in.
      final illnessCap = _illnessCap(
        day,
        previous: previous,
        temperatureDelta: temperatureDelta,
      );
      final recoveryScore = _applyCap(recoveryBase, illnessCap);

      final loadBalanceScore = loadRatio == null
          ? null
          : (100 - ((loadRatio - 1).abs() * 125)).clamp(0, 100).toDouble();
      // Load is a soft penalty (~0.10) on top of recovery, never a base weight.
      final readinessScore = _applyLoadPenalty(recoveryScore, loadBalanceScore);
      final strainScore = strainScoreForLoad(trainingLoad);
      final typicalStrainScore = _typicalStrainScore(previous);
      final anomalies = _anomalyFlags(
        day,
        previous: previous,
        temperatureDelta: temperatureDelta,
      );

      final confidence = _confidenceFor(
        day,
        baselineCoverageDays: baselineCoverage,
      );
      final isCalibrating =
          baselineCoverage < DailyRecoverySnapshot.calibrationTargetDays;
      final flowBand = _flowBandFor(readinessScore, confidence: confidence);

      snapshots.add(
        DailyRecoverySnapshot(
          date: day.date,
          sleepDurationMinutes: day.sleepMinutes,
          timeInBedMinutes: day.timeInBedMinutes,
          remSleepMinutes: day.remMinutes,
          deepSleepMinutes: day.deepMinutes,
          lightSleepMinutes: day.lightMinutes,
          awakeMinutes: day.awakeMinutes,
          sleepCompleteness: day.sleepCompleteness,
          sleepStart: day.sleepStart,
          sleepEnd: day.sleepEnd,
          sleepNeedMinutes: sleepNeedMinutes,
          sleepPerformanceScore: sleepPerformance,
          sleepConsistencyScore: _sleepConsistencyScore(previous, day),
          sleepEfficiency:
              day.timeInBedMinutes != null &&
                  day.timeInBedMinutes! > 0 &&
                  day.sleepMinutes != null
              ? (day.sleepMinutes! / day.timeInBedMinutes!).clamp(0, 1)
              : null,
          hrvValue: day.hrvValue,
          hrvKind: day.hrvKind,
          restingHeartRateBpm: day.restingHeartRateBpm,
          respiratoryRate: day.respiratoryRate,
          bloodOxygenPercent: day.bloodOxygenPercent,
          temperatureCelsius: day.temperatureCelsius,
          temperatureDeltaCelsius: temperatureDelta,
          steps: day.steps,
          activeEnergyKilocalories: day.activeEnergyKilocalories,
          exerciseMinutes: day.exerciseMinutes,
          trainingLoad: trainingLoad,
          acuteLoad7: acuteLoad7,
          chronicLoad42: chronicLoad42,
          loadRatio: loadRatio,
          recoveryScore: recoveryScore,
          readinessScore: readinessScore,
          strainScore: strainScore,
          typicalStrainScore: typicalStrainScore,
          baselineCoverageDays: baselineCoverage,
          band: flowBand?.legacyBand ?? _bandFor(readinessScore),
          flowBand: flowBand,
          confidence: confidence,
          isCalibrating: isCalibrating,
          anomalyFlags: anomalies,
        ),
      );
    }

    return snapshots;
  }

  /// Pick the platform-correct HRV value for a day and tag its kind. iOS reports
  /// SDNN, Android reports RMSSD; the two are not interchangeable. We prefer the
  /// kind that matches the running platform, then fall back to whatever exists,
  /// so a single trend line never mixes the two.
  static (double?, HrvKind?) _selectHrv(List<HealthMetricSample> samples) {
    final sdnn = _average(samples, HealthMetricType.heartRateVariabilitySdnn);
    final rmssd = _average(samples, HealthMetricType.heartRateVariabilityRmssd);
    final preferred = HrvPlatform.preferredKind;
    if (preferred == HrvKind.sdnn) {
      if (sdnn != null) return (sdnn, HrvKind.sdnn);
      if (rmssd != null) return (rmssd, HrvKind.rmssd);
    } else if (preferred == HrvKind.rmssd) {
      if (rmssd != null) return (rmssd, HrvKind.rmssd);
      if (sdnn != null) return (sdnn, HrvKind.sdnn);
    } else {
      // Unknown platform (tests/web): keep prior behaviour, SDNN first.
      if (sdnn != null) return (sdnn, HrvKind.sdnn);
      if (rmssd != null) return (rmssd, HrvKind.rmssd);
    }
    return (null, null);
  }

  /// Total an additive metric (steps, active energy) without cross-source double
  /// counting AND without dropping non-overlapping periods. When several
  /// providers (e.g. the phone and a watch) each report the same day, summing
  /// every sample double counts an overlapping window; conversely, keeping only
  /// the single largest source's total drops periods a device covered alone,
  /// undercounting multi-device users. Health Connect's own aggregate query
  /// de-duplicates server-side, but the per-type reads feeding this builder do
  /// not. As a robust client-side approximation we sweep the samples as time
  /// intervals (sorted by start) and count each covered window exactly once: a
  /// fully new period adds its whole value, a fully overlapped one is skipped,
  /// and a partial overlap contributes only its uncovered tail (pro-rated by
  /// duration). This counts overlapping sources once while still summing
  /// disjoint windows across sources.
  static double? _sumDeduplicatedByInterval(
    List<HealthMetricSample> samples,
    HealthMetricType type,
  ) {
    final intervals =
        samples
            .where(
              (sample) =>
                  sample.type == type && sample.valueInPreferredUnit.isFinite,
            )
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
    if (intervals.isEmpty) return null;

    var total = 0.0;
    DateTime? coveredUntil;
    for (final sample in intervals) {
      final start = sample.startTime;
      final end = sample.endTime;
      final value = sample.valueInPreferredUnit;

      if (coveredUntil == null || !start.isBefore(coveredUntil)) {
        // Fully new period: nothing before this window is covered yet.
        total += value;
        coveredUntil = end.isAfter(start) ? end : start;
      } else if (!end.isAfter(coveredUntil)) {
        // Fully overlapped by an already-counted window: skip.
        continue;
      } else {
        // Partial overlap: count only the uncovered tail, pro-rated by duration.
        final durMs = end.difference(start).inMilliseconds;
        if (durMs <= 0) {
          coveredUntil = end.isAfter(coveredUntil) ? end : coveredUntil;
          continue;
        }
        final uncoveredMs = end.difference(coveredUntil).inMilliseconds;
        total += value * (uncoveredMs / durMs);
        coveredUntil = end;
      }
    }
    return total;
  }

  static double _sumMinutes(
    List<HealthMetricSample> samples,
    HealthMetricType type,
  ) {
    return samples
        .where((sample) => sample.type == type)
        .map((sample) => sample.valueInPreferredUnit)
        .where((value) => value.isFinite)
        .fold(0.0, (sum, value) => sum + value);
  }

  static double? _average(
    List<HealthMetricSample> samples,
    HealthMetricType type,
  ) {
    final values = samples
        .where((sample) => sample.type == type)
        .map((sample) => sample.valueInPreferredUnit)
        .where((value) => value.isFinite)
        .toList();
    return _averageNumbers(values);
  }

  static double? _averageNumbers(Iterable<double> values) {
    final list = values.where((value) => value.isFinite).toList();
    if (list.isEmpty) return null;
    return list.reduce((a, b) => a + b) / list.length;
  }

  static double _computeTrainingLoad(_RawDayRecovery day) {
    final energy = day.activeEnergyKilocalories ?? 0;
    final exercise = day.exerciseMinutes ?? 0;
    final steps = (day.steps ?? 0) / 1000.0;
    return (energy * 0.08) + (exercise * 1.4) + (steps * 1.2);
  }

  /// Cold-start sleep-need base (7.75 h) used before there are enough
  /// qualifying nights to personalize.
  static const double _coldStartSleepBase = 465;

  /// Per-night floor (minutes); nights below this are nap/partial-sync noise and
  /// excluded from the habitual-base median.
  static const double _habitualNightFloorMinutes = 180;

  /// The personalized habitual sleep base: the median nightly sleep over the
  /// trailing [baselineWindowDays] (ignoring nights shorter than
  /// [_habitualNightFloorMinutes]), clamped to the adult consensus range
  /// 420-540 (7.0-9.0 h). Falls back to [_coldStartSleepBase] until at least
  /// [minBaselineDays] qualifying nights exist.
  ///
  /// Adult sleep need is a trait that varies ~1 h around the mean; habitual
  /// duration is the best available proxy and a robust median resists one bad
  /// night.
  static double _habitualSleepBase(List<_RawDayRecovery> previous) {
    final recentNights = previous
        .skip(
          previous.length > baselineWindowDays
              ? previous.length - baselineWindowDays
              : 0,
        )
        .map((entry) => entry.sleepMinutes)
        .whereType<double>()
        .where((minutes) => minutes >= _habitualNightFloorMinutes)
        .toList();
    if (recentNights.length < minBaselineDays) return _coldStartSleepBase;
    final median = _median(recentNights);
    if (median == null) return _coldStartSleepBase;
    return median.clamp(420, 540).toDouble();
  }

  static double _sleepNeedMinutes({
    required double trainingLoad,
    required double habitualBase,
  }) {
    // Acute hard exercise raises sleep need ~10-30 min, up to ~45 min after very
    // heavy/unaccustomed load — not hours. Cap at +45 min.
    final loadAdj = (trainingLoad / 40).clamp(0, 45).toDouble();
    return (habitualBase + loadAdj).clamp(390, 600).toDouble();
  }

  static double? _sleepPerformance(
    _RawDayRecovery day, {
    required double sleepNeedMinutes,
    required List<_RawDayRecovery> previous,
  }) {
    final sleepMinutes = day.sleepMinutes;
    if (sleepMinutes == null) return null;
    final durationAttainment =
        ((sleepMinutes / sleepNeedMinutes).clamp(0, 1) * 100).toDouble();
    final efficiency = day.timeInBedMinutes != null && day.timeInBedMinutes! > 0
        ? (sleepMinutes / day.timeInBedMinutes!).clamp(0, 1).toDouble()
        : null;
    final efficiencyScore = ((efficiency ?? (durationAttainment / 100)) * 100)
        .clamp(0, 100)
        .toDouble();
    final consistency = _sleepConsistencyScore(previous, day);
    final stageScore = _sleepStageScore(day);

    return (0.45 * durationAttainment) +
        (0.25 * efficiencyScore) +
        (0.20 * consistency) +
        (0.10 * stageScore);
  }

  static double _sleepConsistencyScore(
    List<_RawDayRecovery> previous,
    _RawDayRecovery current,
  ) {
    final currentSleep = current.sleepMinutes;
    if (currentSleep == null) return 50;
    final recent = previous
        .map((entry) => entry.sleepMinutes)
        .whereType<double>()
        .toList();
    if (recent.length < 3) return 70;
    final baseline = _averageNumbers(recent) ?? currentSleep;
    final delta = (currentSleep - baseline).abs();
    return (100 - (delta * 0.8)).clamp(0, 100).toDouble();
  }

  static double _sleepStageScore(_RawDayRecovery day) {
    final sleep = day.sleepMinutes;
    if (sleep == null || sleep <= 0) return 50;
    final restorative = (day.deepMinutes ?? 0) + (day.remMinutes ?? 0);
    if (restorative <= 0) return 50;
    final restorativePct = restorative / sleep;
    // Normative deep (13-23%) + REM (20-25%) gives a restorative fraction of
    // ~33-48%, so full credit is a band, not a knife-edge point. The upper slope
    // is gentler so healthy-high restorative sleep isn't penalized.
    if (restorativePct >= 0.33 && restorativePct <= 0.50) return 100;
    if (restorativePct < 0.33) {
      return (100 - (0.33 - restorativePct) * 200).clamp(0, 100).toDouble();
    }
    return (100 - (restorativePct - 0.50) * 100).clamp(0, 100).toDouble();
  }

  /// Robust median + MAD baseline over up to [baselineWindowDays] prior values.
  /// Returns null below [minBaselineDays] so the score stays neutral until the
  /// baseline is trustworthy.
  static _RobustBaseline? _baseline(Iterable<double> values) {
    final list = values.where((value) => value.isFinite).toList();
    if (list.length < minBaselineDays) return null;
    final recent = list
        .skip(
          list.length > baselineWindowDays
              ? list.length - baselineWindowDays
              : 0,
        )
        .toList();
    final center = _median(recent);
    if (center == null) return null;
    final deviations = recent.map((v) => (v - center).abs()).toList();
    final mad = _median(deviations) ?? 0;
    // Scale MAD to a std-equivalent; floor it so spread is always positive
    // (relative to the centre) to avoid divide-by-zero on flat data.
    final scaled = mad * 1.4826;
    final floor = math.max(center.abs() * 0.04, 1e-6);
    return _RobustBaseline(center: center, spread: math.max(scaled, floor));
  }

  /// Convenience: just the robust centre (used for temperature delta).
  static double? _baselineCenter(Iterable<double> values) =>
      _baseline(values)?.center;

  static double? _median(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /// Maps a value against a robust baseline to a 0-100 sub-score. The deviation
  /// is measured in MAD-equivalents and clamped to +/-3 to reject sensor spikes.
  static double? _scoreAgainstBaseline({
    required double? value,
    required _RobustBaseline? baseline,
    required bool positiveBetter,
    double perMadPoints = 16,
  }) {
    if (value == null) return null;
    // Exclude an unbaselined signal (return null so _weightedAverage
    // renormalizes) rather than injecting a synthetic "average" 50, which would
    // bias every calibrating user toward the middle.
    if (baseline == null) return null;
    final dev = ((value - baseline.center) / baseline.spread).clamp(-3.0, 3.0);
    final raw = positiveBetter
        ? 50 + (dev * perMadPoints)
        : 50 - (dev * perMadPoints);
    return raw.clamp(0, 100).toDouble();
  }

  static double? _weightedAverage(List<(double?, double)> entries) {
    var weightSum = 0.0;
    var total = 0.0;
    for (final (value, weight) in entries) {
      if (value == null) continue;
      total += value * weight;
      weightSum += weight;
    }
    if (weightSum == 0) return null;
    return total / weightSum;
  }

  /// Illness gate from respiratory rate + temperature delta. Returns a 0-100
  /// CAP that can only lower the score when a marker is clearly off baseline; a
  /// normal day returns 100 (no cap). Never averages into the base recovery.
  static double _illnessCap(
    _RawDayRecovery day, {
    required List<_RawDayRecovery> previous,
    required double? temperatureDelta,
  }) {
    var cap = 100.0;

    final respiratoryBaseline = _baseline(
      previous.map((entry) => entry.respiratoryRate).whereType<double>(),
    );
    if (respiratoryBaseline != null && day.respiratoryRate != null) {
      final dev =
          (day.respiratoryRate! - respiratoryBaseline.center) /
          respiratoryBaseline.spread;
      if (dev >= 2) {
        // 2 MAD over -> cap 70; scale down to 45 by ~4 MAD.
        cap = math.min(cap, (70 - (dev - 2) * 12.5).clamp(45, 70).toDouble());
      }
    }

    if (temperatureDelta != null && temperatureDelta >= 0.3) {
      // +0.3C -> cap 75; +1.0C -> cap ~40.
      cap = math.min(
        cap,
        (75 - (temperatureDelta - 0.3) * 50).clamp(40, 75).toDouble(),
      );
    }

    final oxygenBaseline = _baseline(
      previous.map((entry) => entry.bloodOxygenPercent).whereType<double>(),
    );
    if (oxygenBaseline != null && day.bloodOxygenPercent != null) {
      final drop = oxygenBaseline.center - day.bloodOxygenPercent!;
      if (drop >= 1.5) {
        cap = math.min(cap, (80 - (drop - 1.5) * 15).clamp(50, 80).toDouble());
      }
    }

    return cap;
  }

  static double? _applyCap(double? recovery, double cap) {
    if (recovery == null) return null;
    return math.min(recovery, cap);
  }

  /// Apply load as a soft penalty (~0.10 weight) rather than blending it in as a
  /// peer signal. A balanced load (score ~100) does nothing; a ramped/very-low
  /// load nudges readiness down a little.
  static double? _applyLoadPenalty(double? recovery, double? loadBalance) {
    if (recovery == null) return null;
    if (loadBalance == null) return recovery;
    final penalty = (100 - loadBalance) * 0.10;
    return (recovery - penalty).clamp(0, 100).toDouble();
  }

  /// Maps a single day's training load to the 0-21 strain meter.
  ///
  /// Public so the typical-strain baseline maps the median prior load with the
  /// EXACT same mapping the day score uses ([_typicalStrainScore]); a single
  /// definition means the day number and its "typical" can never drift apart.
  static int strainScoreForLoad(double trainingLoad) {
    // Decay constant matched to the real daily load distribution so the meter
    // discriminates across the normal range and only nears full scale at a
    // genuinely hard session (~400-600 AU): ~100 AU -> ~7, ~370 -> ~16, ~600 -> ~19.
    final value = 21 * (1 - math.exp(-trainingLoad / 250));
    return value.round().clamp(0, 21);
  }

  /// Minimum qualifying prior days before a typical strain is honest. Below
  /// this the typical is null (no comparison line while still calibrating).
  static const int _minTypicalDays = 7;

  /// The user's typical daily strain: [strainScoreForLoad] of the MEDIAN
  /// training load over the trailing [baselineWindowDays] of PRIOR days that
  /// actually carried an activity reading (today itself is excluded — [previous]
  /// never contains it).
  ///
  /// A robust median (not the [chronicLoad42] mean) so one very hard or very
  /// light day cannot drag the typical, matching the pipeline's stated
  /// robust-baseline philosophy. Zero-filled gap days (no steps / energy /
  /// exercise reading) are skipped, not counted as a real rest day, so a run of
  /// unsynced days does not deflate the typical. Returns null until at least
  /// [_minTypicalDays] qualifying days exist.
  static int? _typicalStrainScore(List<_RawDayRecovery> previous) {
    final recentLoads = previous
        .skip(
          previous.length > baselineWindowDays
              ? previous.length - baselineWindowDays
              : 0,
        )
        .where(_hasLoadReading)
        .map(_computeTrainingLoad)
        .toList();
    if (recentLoads.length < _minTypicalDays) return null;
    final median = _median(recentLoads);
    if (median == null) return null;
    return strainScoreForLoad(median);
  }

  /// Whether a day carried a real activity reading (as opposed to a zero-filled
  /// gap day the aggregator synthesized to keep load windows on the calendar).
  static bool _hasLoadReading(_RawDayRecovery day) =>
      day.activeEnergyKilocalories != null ||
      day.exerciseMinutes != null ||
      day.steps != null;

  /// Honest confidence from signal count + baseline coverage (spec).
  ///
  /// Confidence is anchored on the *baseline* — once a strong trailing baseline
  /// exists, an unfinished current day (today's HRV/RHR/sleep not synced yet)
  /// must not drag the number down to "Rough estimate". A genuinely thin
  /// baseline still reads low, preserving honest early calibration.
  static RecoveryConfidence _confidenceFor(
    _RawDayRecovery day, {
    required int baselineCoverageDays,
  }) {
    final hasHrv = day.hrvValue != null;
    final hasRhr = day.restingHeartRateBpm != null;
    final hasSleep = day.sleepMinutes != null;

    // A strong baseline earns high confidence even when today is incomplete:
    // today carries the full signal set => high; otherwise the deep baseline
    // alone still holds at medium so an unsynced current day doesn't penalize
    // the estimate down to "Rough estimate".
    if (baselineCoverageDays >= 14) {
      if (hasHrv && hasRhr && hasSleep) return RecoveryConfidence.high;
      return RecoveryConfidence.medium;
    }
    // A 7+ day baseline holds at medium confidence regardless of whether
    // today's signals have finished syncing.
    if (baselineCoverageDays >= 7) {
      return RecoveryConfidence.medium;
    }
    return RecoveryConfidence.low;
  }

  /// Four warm bands from the readiness score. On low confidence the bands are
  /// widened toward the gentle middle so a thin-data day never throws a scary
  /// low it cannot justify.
  static RecoveryFlowBand? _flowBandFor(
    double? readiness, {
    required RecoveryConfidence confidence,
  }) {
    if (readiness == null) return null;
    // Base thresholds: Charged >=80, Ready >=60, Steady >=40, else Recharge.
    var chargedAt = 80.0;
    var readyAt = 60.0;
    var rechargeBelow = 40.0;
    if (confidence == RecoveryConfidence.low) {
      // Widen: harder to reach the extremes, easier to land in Steady.
      chargedAt = 85.0;
      readyAt = 58.0;
      rechargeBelow = 32.0;
    } else if (confidence == RecoveryConfidence.medium) {
      chargedAt = 82.0;
      rechargeBelow = 37.0;
    }
    if (readiness >= chargedAt) return RecoveryFlowBand.charged;
    if (readiness >= readyAt) return RecoveryFlowBand.ready;
    if (readiness >= rechargeBelow) return RecoveryFlowBand.steady;
    return RecoveryFlowBand.recharge;
  }

  static RecoveryReadinessBand? _bandFor(double? readiness) {
    if (readiness == null) return null;
    if (readiness >= 80) return RecoveryReadinessBand.high;
    if (readiness >= 60) return RecoveryReadinessBand.moderate;
    return RecoveryReadinessBand.low;
  }

  static List<String> _anomalyFlags(
    _RawDayRecovery day, {
    required List<_RawDayRecovery> previous,
    required double? temperatureDelta,
  }) {
    final flags = <String>[];
    final hrvBaseline = _baseline(
      previous
          .where((entry) => entry.hrvKind == day.hrvKind)
          .map((entry) => entry.hrvValue)
          .whereType<double>(),
    );
    final rhrBaseline = _baseline(
      previous.map((entry) => entry.restingHeartRateBpm).whereType<double>(),
    );
    final respiratoryBaseline = _baseline(
      previous.map((entry) => entry.respiratoryRate).whereType<double>(),
    );
    final oxygenBaseline = _baseline(
      previous.map((entry) => entry.bloodOxygenPercent).whereType<double>(),
    );

    if (hrvBaseline != null &&
        day.hrvValue != null &&
        day.hrvValue! < hrvBaseline.center * 0.9) {
      flags.add('low_hrv');
    }
    if (rhrBaseline != null &&
        day.restingHeartRateBpm != null &&
        day.restingHeartRateBpm! > rhrBaseline.center * 1.08) {
      flags.add('elevated_resting_hr');
    }
    if (respiratoryBaseline != null &&
        day.respiratoryRate != null &&
        day.respiratoryRate! > respiratoryBaseline.center * 1.08) {
      flags.add('elevated_respiratory_rate');
    }
    if (temperatureDelta != null && temperatureDelta >= 0.3) {
      flags.add('elevated_temperature');
    }
    if (oxygenBaseline != null &&
        day.bloodOxygenPercent != null &&
        day.bloodOxygenPercent! < oxygenBaseline.center - 1.5) {
      flags.add('low_blood_oxygen');
    }
    return flags;
  }
}

/// Resolves which HRV kind to prefer on the running platform. iOS HealthKit
/// exposes SDNN; Android Health Connect exposes RMSSD. Overridable in tests.
class HrvPlatform {
  HrvPlatform._();

  /// Test/seed override. When set, takes precedence over the real platform.
  static HrvKind? debugOverrideKind;

  /// The HRV kind to prefer for the current platform, or null when unknown.
  static HrvKind? get preferredKind {
    if (debugOverrideKind != null) return debugOverrideKind;
    return _platformResolver();
  }

  /// Resolver indirection so tests can drive platform behaviour without dart:io.
  static HrvKind? Function() _platformResolver = _defaultResolver;

  // ignore: use_setters_to_change_properties
  static void debugSetResolver(HrvKind? Function() resolver) {
    _platformResolver = resolver;
  }

  static void debugReset() {
    debugOverrideKind = null;
    _platformResolver = _defaultResolver;
  }

  static HrvKind? _defaultResolver() {
    // Falls back to null on web or unknown platforms where neither kind is
    // canonical; tests inject a resolver to drive platform behaviour.
    return PlatformHrvResolver.kind();
  }
}

class _RawDayRecovery {
  const _RawDayRecovery({
    required this.date,
    this.sleepMinutes,
    this.timeInBedMinutes,
    this.remMinutes,
    this.deepMinutes,
    this.lightMinutes,
    this.awakeMinutes,
    this.sleepCompleteness = HealthDataCompleteness.unknown,
    this.sleepStart,
    this.sleepEnd,
    this.hrvValue,
    this.hrvKind,
    this.restingHeartRateBpm,
    this.respiratoryRate,
    this.bloodOxygenPercent,
    this.temperatureCelsius,
    this.steps,
    this.activeEnergyKilocalories,
    this.exerciseMinutes,
  });

  final DateTime date;
  final double? sleepMinutes;
  final double? timeInBedMinutes;
  final double? remMinutes;
  final double? deepMinutes;
  final double? lightMinutes;
  final double? awakeMinutes;
  final HealthDataCompleteness sleepCompleteness;
  final DateTime? sleepStart;
  final DateTime? sleepEnd;
  final double? hrvValue;
  final HrvKind? hrvKind;
  final double? restingHeartRateBpm;
  final double? respiratoryRate;
  final double? bloodOxygenPercent;
  final double? temperatureCelsius;
  final int? steps;
  final double? activeEnergyKilocalories;
  final double? exerciseMinutes;
}
