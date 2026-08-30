import '../models/daily_health_summary.dart';
import '../models/daily_recovery_snapshot.dart';
import 'recovery_band_copy.dart';

enum HealthInsightSeverity { info, success, warning }

class HealthInsight {
  const HealthInsight({
    required this.title,
    required this.message,
    this.severity = HealthInsightSeverity.info,
  });

  final String title;
  final String message;
  final HealthInsightSeverity severity;
}

class DeriveHealthInsightsUseCase {
  List<HealthInsight> call(
    List<DailyHealthSummary> summaries, {
    List<DailyRecoverySnapshot> recoverySnapshots = const [],
  }) {
    if (summaries.isEmpty) {
      return const [
        HealthInsight(
          title: 'Connect a provider to begin',
          message:
              'Authorize Hustl to read sleep, recovery, activity, and body metrics from Apple Health or Health Connect to unlock insights.',
        ),
      ];
    }

    final List<HealthInsight> insights = [];
    final recentSummaries = summaries.takeLast(7);
    final latestRecovery = recoverySnapshots.isEmpty
        ? null
        : recoverySnapshots.last;

    final readiness = latestRecovery?.readinessScore;
    if (readiness != null) {
      final rounded = readiness.round();
      // Prefer the algorithm's flow band; fall back to a score-derived band so
      // legacy snapshots (readiness set, no flow band) still surface a kind,
      // band-aware insight.
      final flowBand =
          latestRecovery?.flowBand ?? _flowBandFromScore(readiness);
      final isCalibrating = latestRecovery?.isCalibrating ?? false;
      // Band-aware, kind copy: a warm invitation, never a command. While
      // calibrating we soften to a "building baseline" note instead of leading
      // with a hard number.
      if (isCalibrating) {
        insights.add(
          HealthInsight(
            title: 'Building your readiness baseline',
            message:
                '${RecoveryBandCopy.guidance(latestRecovery)} Your number will sharpen as the baseline fills in.',
            severity: HealthInsightSeverity.info,
          ),
        );
      } else {
        final isPositive =
            flowBand == RecoveryFlowBand.charged ||
            flowBand == RecoveryFlowBand.ready;
        insights.add(
          HealthInsight(
            title: '${flowBand.displayLabel} today',
            message:
                '${RecoveryBandCopy.headlineForBand(flowBand)} ${RecoveryBandCopy.guidanceForBand(flowBand)} (readiness $rounded/100)',
            severity: isPositive
                ? HealthInsightSeverity.success
                : HealthInsightSeverity.info,
          ),
        );
      }
    } else if (latestRecovery?.hasRecoveryData ?? false) {
      // Signal-present calibration path: vitals (HRV/RHR/sleep) are flowing but
      // the score is intentionally WITHHELD because the baseline isn't ready
      // yet (e.g. HRV/RHR-only early days before a trustworthy baseline exists).
      // Surface a gentle "still learning / building your baseline" state so the
      // user never falls through to unrelated "All clear" copy. We never
      // fabricate a number here — the score stays null by design.
      insights.add(
        HealthInsight(
          title: 'Building your readiness baseline',
          message:
              '${RecoveryBandCopy.guidance(latestRecovery)} Your readiness number will appear once we have enough to read it confidently.',
          severity: HealthInsightSeverity.info,
        ),
      );
    }

    final sleepMinutes = latestRecovery?.sleepDurationMinutes;
    if (sleepMinutes != null) {
      final sleepHours = sleepMinutes / 60.0;
      // Personalized need (habitual base + acute load), defended by a legacy
      // fallback for snapshots with a null need.
      final sleepNeed = (latestRecovery?.sleepNeedMinutes ?? 480) / 60.0;
      // Fire on EITHER a meaningful per-night shortfall against the personalized
      // need (one sleep cycle, ~45 min) OR a genuinely short night in absolute
      // terms (<6.0 h is short for adults regardless of computed need).
      final hitAbsoluteFloor = sleepHours < 6.0;
      final hitRelativeSlack = sleepHours < sleepNeed - 0.75;
      if (hitAbsoluteFloor || hitRelativeSlack) {
        final gap = sleepNeed - sleepHours;
        final weekDebt = _weeklySleepDebtMinutes(recoverySnapshots);
        final buffer = StringBuffer(
          'You slept ${sleepHours.toStringAsFixed(1)}h, about '
          '${gap.toStringAsFixed(1)}h under your usual '
          '${sleepNeed.toStringAsFixed(1)}h.',
        );
        if (weekDebt >= 60) {
          buffer.write(
            ' Sleep debt is building this week — an earlier night would help.',
          );
        }
        // A well-recovered person who only slept a bit short doesn't need a
        // warning tone: downgrade to info when only the relative slack fired and
        // the band is ready/charged. The absolute 6 h floor always warns.
        final band = latestRecovery?.flowBand;
        final wellRecovered =
            band == RecoveryFlowBand.ready || band == RecoveryFlowBand.charged;
        final severity = (!hitAbsoluteFloor && hitRelativeSlack && wellRecovered)
            ? HealthInsightSeverity.info
            : HealthInsightSeverity.warning;
        insights.add(
          HealthInsight(
            title: 'Sleep came in short',
            message: buffer.toString(),
            severity: severity,
          ),
        );
      }
    }

    final loadRatio = latestRecovery?.loadRatio;
    if (loadRatio != null) {
      if (loadRatio >= 1.25) {
        insights.add(
          HealthInsight(
            title: 'Training load is elevated',
            message:
                'Your recent load is running about ${(loadRatio * 100).round()}% of your longer-term baseline. Watch for fatigue creep if recovery is also down.',
            severity: HealthInsightSeverity.warning,
          ),
        );
      } else if (loadRatio <= 0.75 && latestRecovery?.trainingLoad != null) {
        insights.add(
          const HealthInsight(
            title: 'Load is below baseline',
            message:
                'Recent training load is lighter than your usual range. This can be useful for a deload, but it may also signal lost momentum.',
            severity: HealthInsightSeverity.info,
          ),
        );
      }
    }

    if ((latestRecovery?.anomalyFlags.length ?? 0) >= 2) {
      insights.add(
        const HealthInsight(
          title: 'Markers look a bit off baseline',
          message:
              'A few overnight signals shifted from your usual at once. Nothing to worry about — be gentle with yourself today and keep things easy if you feel run down.',
          severity: HealthInsightSeverity.info,
        ),
      );
    }

    final weights = recentSummaries
        .map((s) => s.latestWeightKg)
        .whereType<double>()
        .toList();
    if (weights.length >= 2) {
      final diff = weights.last - weights.first;
      if (diff.abs() >= 0.75) {
        final direction = diff > 0 ? 'up' : 'down';
        insights.add(
          HealthInsight(
            title: 'Weight trending $direction',
            message:
                'Your weight moved ${diff.abs().toStringAsFixed(1)} kg over the past week. Consider adjusting your training or nutrition goals.',
            severity: HealthInsightSeverity.info,
          ),
        );
      }
    }

    final hasHydrationData = recentSummaries.any(
      (s) => s.macros.waterLiters != null,
    );
    if (hasHydrationData) {
      final hydrationDays = recentSummaries
          .where((s) => (s.macros.waterLiters ?? 0) >= 2.0)
          .length;
      if (hydrationDays >= 4) {
        insights.add(
          const HealthInsight(
            title: 'Hydration streak',
            message:
                'Great work staying hydrated on at least 4 of the last 7 days.',
            severity: HealthInsightSeverity.success,
          ),
        );
      } else {
        final needed = 4 - hydrationDays;
        if (needed > 0) {
          insights.add(
            HealthInsight(
              title: 'Hydration opportunity',
              message:
                  'Hit at least 2L of water for $needed more day(s) this week to stay on track.',
              severity: HealthInsightSeverity.warning,
            ),
          );
        }
      }
    }

    final avgProtein = recentSummaries
        .where((s) => s.macros.calories > 0)
        .map((s) => s.macros.proteinGrams)
        .toList();
    if (avgProtein.isNotEmpty) {
      final proteinAvg =
          avgProtein.reduce((a, b) => a + b) / avgProtein.length.toDouble();
      if (proteinAvg < 1.6 * 70) {
        insights.add(
          const HealthInsight(
            title: 'Protein intake could increase',
            message:
                'Aim for roughly 1.6-2.2g of protein per kg of bodyweight to support strength gains.',
            severity: HealthInsightSeverity.warning,
          ),
        );
      }
    }

    final bmiValues = recentSummaries
        .map((s) => s.bodyMassIndex)
        .whereType<double>()
        .toList();
    if (bmiValues.isNotEmpty) {
      final bmi = bmiValues.last;
      if (bmi < 18.5) {
        insights.add(
          const HealthInsight(
            title: 'BMI below healthy range',
            message:
                'Consider discussing with a coach or physician to ensure your nutrition supports recovery.',
            severity: HealthInsightSeverity.warning,
          ),
        );
      } else if (bmi > 25) {
        insights.add(
          const HealthInsight(
            title: 'BMI above healthy range',
            message:
                'Pair progressive overload with nutrition adjustments to move toward your target body composition.',
            severity: HealthInsightSeverity.info,
          ),
        );
      }
    }

    if (insights.isEmpty) {
      insights.add(
        const HealthInsight(
          title: 'All clear',
          message:
              'Metrics look steady this week. Keep logging workouts to discover deeper trends.',
          severity: HealthInsightSeverity.success,
        ),
      );
    }

    return insights;
  }
}

/// Surfaced weekly sleep debt (minutes), computed transiently from the trailing
/// 7 recovery snapshots. Each night is measured against that snapshot's own
/// personalized need (`sleepNeedMinutes`), so the debt figure shares the same
/// anchor as the need quoted to the user. A surplus night (slept more than
/// need) repays debt down to -120 min/night; the weekly total is floored at 0.
double _weeklySleepDebtMinutes(List<DailyRecoverySnapshot> snapshots) {
  if (snapshots.isEmpty) return 0;
  final recent = snapshots.length > 7
      ? snapshots.sublist(snapshots.length - 7)
      : snapshots;
  var debt = 0.0;
  for (final snapshot in recent) {
    final sleep = snapshot.sleepDurationMinutes;
    final need = snapshot.sleepNeedMinutes;
    if (sleep == null || need == null) continue;
    debt += (need - sleep).clamp(-120, 180).toDouble();
  }
  return debt < 0 ? 0 : debt;
}

/// Score-derived four-band fallback for legacy snapshots that carry a
/// `readinessScore` but no `flowBand`. Uses the default (high/medium
/// confidence) thresholds from the recovery spec.
RecoveryFlowBand _flowBandFromScore(double readiness) {
  if (readiness >= 80) return RecoveryFlowBand.charged;
  if (readiness >= 60) return RecoveryFlowBand.ready;
  if (readiness >= 40) return RecoveryFlowBand.steady;
  return RecoveryFlowBand.recharge;
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final list = toList();
    if (list.length <= count) return list;
    return list.sublist(list.length - count);
  }
}
