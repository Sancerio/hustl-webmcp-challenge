import '../../../domain/models/daily_recovery_snapshot.dart';

/// Pure copy + phrasing helpers for the "Conditions Report" overview hero, the
/// instruments row, and the "Last night" detail screen. Kept separate from
/// [health_dashboard_copy.dart] because this is new, narrative "data as a
/// sentence" copy (the Ledger-direction lede) rather than the vetted
/// band/coaching copy pipeline, which stays untouched and is reused as-is.

/// Minimum number of prior-day values required before a trailing baseline is
/// considered trustworthy — mirrors the app's existing baseline convention
/// (see `health_dashboard_copy.dart`'s former hrv/rhr status helpers: a plain
/// average over the days feeding a signal, once enough exist).
const int kConditionsBaselineMinDays = 5;

bool _isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Trailing average of prior-day values for one signal, using at most the
/// last [windowDays] values (a rolling week) and only once at least
/// [minCount] values exist. Returns null while the baseline is still building.
double? trailingSignalBaseline(
  Iterable<double> priorValues, {
  int windowDays = 7,
  int minCount = kConditionsBaselineMinDays,
}) {
  final values = priorValues.toList();
  if (values.length < minCount) return null;
  final windowed = values.length > windowDays
      ? values.sublist(values.length - windowDays)
      : values;
  return windowed.reduce((a, b) => a + b) / windowed.length;
}

/// Sleep / HRV / resting-heart-rate baselines derived from the trailing
/// recovery snapshots, excluding the day being described. Shared by the
/// conditions hero, the instruments row, and the night detail screen so all
/// three read the same baseline the same way.
class ConditionsBaselines {
  const ConditionsBaselines({
    this.sleepMinutes,
    this.hrvValue,
    this.restingHeartRateBpm,
  });

  final double? sleepMinutes;
  final double? hrvValue;
  final double? restingHeartRateBpm;

  factory ConditionsBaselines.fromSnapshots(
    List<DailyRecoverySnapshot> snapshots,
    DailyRecoverySnapshot today,
  ) {
    final prior = snapshots
        .where((s) => !_isSameDate(s.date, today.date))
        .toList();
    return ConditionsBaselines(
      sleepMinutes: trailingSignalBaseline(
        prior.map((s) => s.sleepDurationMinutes).whereType<double>(),
      ),
      hrvValue: trailingSignalBaseline(
        prior.map((s) => s.hrvValue).whereType<double>(),
      ),
      restingHeartRateBpm: trailingSignalBaseline(
        prior.map((s) => s.restingHeartRateBpm).whereType<double>(),
      ),
    );
  }
}

/// The most recent snapshot that actually carries recovery data, falling back
/// to the very latest day (which may be a blank, still-syncing "today") when
/// nothing yet has data. Shared by the overview hero and the night detail
/// screen so both surfaces treat "today" / "last night" identically.
({DailyRecoverySnapshot? snapshot, bool isStale}) latestRecoverySnapshot(
  List<DailyRecoverySnapshot> snapshots,
) {
  if (snapshots.isEmpty) return (snapshot: null, isStale: false);
  final today = snapshots.last;
  final latest = today.hasRecoveryData
      ? today
      : snapshots.lastWhere((s) => s.hasRecoveryData, orElse: () => today);
  return (snapshot: latest, isStale: latest != today);
}

// ---- Formatting ----

String formatHoursMinutes(double minutes) {
  final total = minutes.round();
  final h = total ~/ 60;
  final m = total % 60;
  if (h <= 0) return '${m}m';
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

/// A signed delta rendered as e.g. "18m under" / "no data yet". Shared shape
/// for the instruments row + the night screen's "what tonight built" rows.
class SignalDelta {
  const SignalDelta({required this.label, required this.up});

  /// Compact label, e.g. "18m under", "4 ms easier", "4 over".
  final String label;

  /// True when the value moved above its baseline (drives the tiny up/down
  /// chevron); false when it moved below or is flat.
  final bool up;
}

/// Sleep duration delta vs. baseline, e.g. "18m under" / "12m over".
SignalDelta? sleepDelta(double? sleepMinutes, double? baselineMinutes) {
  if (sleepMinutes == null || baselineMinutes == null) return null;
  final diff = sleepMinutes - baselineMinutes;
  if (diff.abs() < 1) return const SignalDelta(label: 'on baseline', up: true);
  final word = diff < 0 ? 'under' : 'over';
  return SignalDelta(label: '${diff.abs().round()}m $word', up: diff >= 0);
}

/// HRV delta vs. baseline. Warm, never alarmist: a drop reads as "easier" /
/// "easing", never "worse".
SignalDelta? hrvDelta(double? hrvValue, double? baselineValue) {
  if (hrvValue == null || baselineValue == null) return null;
  final diff = hrvValue - baselineValue;
  if (diff.abs() < 0.5) return const SignalDelta(label: 'steady', up: true);
  final word = diff < 0 ? 'easier' : 'higher';
  return SignalDelta(label: '${diff.abs().round()} ms $word', up: diff >= 0);
}

/// Resting heart rate delta vs. baseline, e.g. "4 over" / "3 under".
SignalDelta? rhrDelta(double? rhrValue, double? baselineValue) {
  if (rhrValue == null || baselineValue == null) return null;
  final diff = rhrValue - baselineValue;
  if (diff.abs() < 0.5) return const SignalDelta(label: 'steady', up: true);
  final word = diff < 0 ? 'under' : 'over';
  return SignalDelta(label: '${diff.abs().round()} $word', up: diff >= 0);
}

/// The one-sentence, data-woven lede shown under the conditions band word —
/// the "Ledger" direction's steal: a warm sentence composed only from signals
/// that actually have data today. Returns null when fewer than one signal has
/// data; the hero then falls back to the existing `coachHeadline` copy.
///
/// Resting heart rate is preferred for the "how your heart ran" clause (it is
/// the more literal read of "heart"); HRV steps in alone when RHR isn't
/// available or isn't notably off baseline.
String? conditionsLede(
  DailyRecoverySnapshot today, {
  required double? sleepBaselineMinutes,
  required double? hrvBaseline,
  required double? rhrBaseline,
}) {
  final sleepMinutes = today.sleepDurationMinutes;
  final hrv = today.hrvValue;
  final rhr = today.restingHeartRateBpm;

  final signalCount = [sleepMinutes, hrv, rhr].whereType<double>().length;
  if (signalCount < 1) return null;

  final parts = <String>[];

  if (sleepMinutes != null) {
    final buffer = StringBuffer(
      'You slept ${formatHoursMinutes(sleepMinutes)}',
    );
    final deltaMinutes = sleepBaselineMinutes == null
        ? null
        : sleepMinutes - sleepBaselineMinutes;
    if (deltaMinutes != null && deltaMinutes.abs() >= 5) {
      final word = deltaMinutes < 0 ? 'under' : 'over';
      buffer.write(
        ' — ${deltaMinutes.abs().round()} minutes $word your baseline',
      );
    }
    parts.add(buffer.toString());
  }

  String? heartClause;
  if (rhr != null && rhrBaseline != null) {
    final delta = rhr - rhrBaseline;
    if (delta.abs() >= 1.5) {
      heartClause = delta > 0
          ? 'your heart ran slightly warm overnight'
          : 'your heart ran calm overnight';
    }
  }
  if (heartClause == null && hrv != null && hrvBaseline != null) {
    final delta = hrv - hrvBaseline;
    if (delta.abs() >= 2) {
      heartClause = delta < 0
          ? 'your HRV eased a little overnight'
          : 'your HRV ran a little higher overnight';
    }
  }

  if (heartClause != null) {
    if (parts.isEmpty) {
      parts.add(heartClause[0].toUpperCase() + heartClause.substring(1));
    } else {
      parts.add('and $heartClause');
    }
  } else if (parts.isEmpty) {
    // A heart-only signal with no deviation worth naming still deserves a
    // quiet, true sentence rather than an empty lede.
    if (rhr != null) {
      parts.add('Your resting heart rate held steady overnight');
    } else if (hrv != null) {
      parts.add('Your HRV held steady overnight');
    }
  }

  if (parts.isEmpty) return null;
  return '${parts.join(' — ')}.';
}
