import 'dart:math' as math;

/// A clean y-axis for the weight trend chart.
///
/// The old chart rounded every gridline label to 0 decimals over a
/// sub-1-kg interval, which collapsed distinct ticks into duplicate strings
/// ("71, 71, 70, 70, 69"). [computeWeightAxis] instead snaps the bounds to a
/// "nice" interval and records how many decimals each label needs so that
/// every visible tick reads as a distinct, sensible weight.
class WeightAxis {
  const WeightAxis({
    required this.min,
    required this.max,
    required this.interval,
    required this.fractionDigits,
  });

  /// Bottom of the axis (a multiple of [interval]).
  final double min;

  /// Top of the axis (a multiple of [interval]).
  final double max;

  /// Gap between gridlines (a "nice" number: 0.5, 1, 2, 5, 10…).
  final double interval;

  /// Decimal places each label needs so adjacent ticks never collapse.
  final int fractionDigits;

  /// Whether [value] lands on a real gridline (within float tolerance).
  bool isTick(double value) {
    if (value < min - _eps || value > max + _eps) return false;
    final steps = (value - min) / interval;
    return (steps - steps.roundToDouble()).abs() < 1e-6;
  }

  /// The label for a tick at [value].
  String format(double value) => value.toStringAsFixed(fractionDigits);

  /// The distinct labels this axis would render, top to bottom — handy for
  /// tests asserting there are no duplicates.
  List<String> tickLabels() {
    final labels = <String>[];
    final count = ((max - min) / interval).round();
    for (var i = 0; i <= count; i++) {
      labels.add(format(min + interval * i));
    }
    return labels;
  }

  static const double _eps = 1e-6;
}

/// Builds a [WeightAxis] from the raw data range.
///
/// Targets ~4 gridlines, picks a "nice" interval from a 1/2/5 ladder, pads the
/// data range by one interval, snaps both bounds to multiples of the interval,
/// and chooses the minimum decimal precision that keeps every tick distinct
/// (1 decimal for sub-1-kg intervals, otherwise 0).
///
/// [tight] drops the breathing-room padding so the extreme weigh-ins sit near
/// the frame — the "fit to data" state behind the header's vertical-resize
/// button.
WeightAxis computeWeightAxis(
  double minY,
  double maxY, {
  int targetTicks = 4,
  bool tight = false,
}) {
  // Degenerate / empty range: show a small symmetric window around the value.
  if (!minY.isFinite || !maxY.isFinite) {
    return const WeightAxis(min: 0, max: 4, interval: 1, fractionDigits: 0);
  }

  var lo = math.min(minY, maxY);
  var hi = math.max(minY, maxY);
  var range = hi - lo;

  // Flat data (single weigh-in or identical values): open up a ±1 kg window so
  // the line sits mid-card with real gridlines around it.
  if (range < 0.5) {
    final mid = (lo + hi) / 2;
    lo = mid - 1;
    hi = mid + 1;
    range = hi - lo;
  }

  final interval = _niceInterval(range / targetTicks);

  // Pad by ~30% of an interval so the extreme points don't kiss the frame,
  // then snap both bounds onto the interval grid. [tight] removes the padding
  // so the curve fills the frame edge-to-edge.
  final pad = tight ? 0.0 : interval * 0.3;
  var axisMin = _floorTo(lo - pad, interval);
  var axisMax = _ceilTo(hi + pad, interval);

  // Weight can't be negative; keep the floor sensible.
  if (axisMin < 0) axisMin = 0;
  if (axisMax <= axisMin) axisMax = axisMin + interval;

  // Sub-1-kg intervals need a decimal so 70.5 and 71.0 don't both round to 71.
  final fractionDigits = interval < 1 ? 1 : 0;

  return WeightAxis(
    min: axisMin,
    max: axisMax,
    interval: interval,
    fractionDigits: fractionDigits,
  );
}

/// Rounds [raw] up to the nearest "nice" number on a 1/2/5 × 10ⁿ ladder.
double _niceInterval(double raw) {
  if (raw <= 0) return 1;
  final exponent = (math.log(raw) / math.ln10).floor();
  final magnitude = math.pow(10, exponent).toDouble();
  final fraction = raw / magnitude;
  final double niceFraction;
  if (fraction <= 1) {
    niceFraction = 1;
  } else if (fraction <= 2) {
    niceFraction = 2;
  } else if (fraction <= 5) {
    niceFraction = 5;
  } else {
    niceFraction = 10;
  }
  final result = niceFraction * magnitude;
  // Never go below 0.5 kg — finer than that produces noisy, near-duplicate
  // gridline labels for weight data.
  return result < 0.5 ? 0.5 : result;
}

double _floorTo(double value, double step) => (value / step).floor() * step;

double _ceilTo(double value, double step) => (value / step).ceil() * step;
