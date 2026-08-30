import 'dart:math' as math;

/// A clean, unit-agnostic y-axis for MacroFactor-style trend charts (kcal,
/// macros, anything that isn't weight). Mirrors `WeightAxis` but without the
/// weight-specific 0.5-floor / forced-decimal rules, so kcal lands on round
/// hundreds (2800 / 3000 / 3200) instead of noisy fractions.
class ChartAxis {
  const ChartAxis({
    required this.min,
    required this.max,
    required this.interval,
    required this.fractionDigits,
  });

  final double min;
  final double max;
  final double interval;
  final int fractionDigits;

  /// Whether [value] lands on a real gridline (within float tolerance).
  bool isTick(double value) {
    if (value < min - _eps || value > max + _eps) return false;
    final steps = (value - min) / interval;
    return (steps - steps.roundToDouble()).abs() < 1e-6;
  }

  String format(double value) => value.toStringAsFixed(fractionDigits);

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

/// Builds a [ChartAxis] from the raw data range. Targets ~[targetTicks]
/// gridlines on a 1/2/5 ladder, pads ~30% of an interval (unless [tight]), snaps
/// both bounds onto the grid, and picks the fewest decimals that keep ticks
/// distinct. [clampMinToZero] keeps non-negative series (kcal) off negative
/// floors without forcing a zero baseline that would flatten the curve.
ChartAxis computeNiceAxis(
  double minY,
  double maxY, {
  int targetTicks = 4,
  bool tight = false,
  bool clampMinToZero = true,
}) {
  if (!minY.isFinite || !maxY.isFinite) {
    return const ChartAxis(min: 0, max: 4, interval: 1, fractionDigits: 0);
  }

  var lo = math.min(minY, maxY);
  var hi = math.max(minY, maxY);
  var range = hi - lo;

  if (range < _eps) {
    final mid = (lo + hi) / 2;
    final pad = mid.abs() < 1 ? 1.0 : mid.abs() * 0.05;
    lo = mid - pad;
    hi = mid + pad;
    range = hi - lo;
  }

  final interval = _niceInterval(range / targetTicks);
  final pad = tight ? 0.0 : interval * 0.3;
  var axisMin = _floorTo(lo - pad, interval);
  var axisMax = _ceilTo(hi + pad, interval);

  if (clampMinToZero && axisMin < 0) axisMin = 0;
  if (axisMax <= axisMin) axisMax = axisMin + interval;

  final fractionDigits = interval < 1 ? (interval < 0.1 ? 2 : 1) : 0;

  return ChartAxis(
    min: axisMin,
    max: axisMax,
    interval: interval,
    fractionDigits: fractionDigits,
  );
}

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
  return niceFraction * magnitude;
}

double _floorTo(double value, double step) => (value / step).floor() * step;
double _ceilTo(double value, double step) => (value / step).ceil() * step;
const double _eps = 1e-9;
