import 'package:intl/intl.dart';

class NumberFormatUtil {
  static String formatInt(int value) {
    final formatter = NumberFormat.decimalPattern();
    return formatter.format(value);
  }

  static String formatDouble(double value, {int decimalDigits = 0}) {
    final formatter = NumberFormat.decimalPattern()
      ..minimumFractionDigits = decimalDigits
      ..maximumFractionDigits = decimalDigits;
    return formatter.format(value);
  }

  /// Human-facing label for a logged weight (kg). Preserves the precision the
  /// user actually entered — up to two decimals, matching the backend's
  /// `numeric(6,2)` column — while trimming noise: whole numbers show no
  /// decimals and trailing zeros are dropped.
  ///
  /// `60` -> `60`, `62.5` -> `62.5`, `3.75` -> `3.75`, `3.70` -> `3.7`.
  ///
  /// Use this everywhere a weight is shown so micro-plate loads (1.25 kg
  /// increments) are never silently rounded — e.g. `3.75` must not become
  /// `3.8` in summaries, PR rows, or the next workout's prefilled value.
  static String formatWeight(double value) {
    final formatter = NumberFormat.decimalPattern()
      ..minimumFractionDigits = 0
      ..maximumFractionDigits = 2;
    return formatter.format(value);
  }

  static String formatApproximateSets(
    double value, {
    bool includeApproximationSymbol = true,
  }) {
    if (value <= 0) {
      return '0';
    }
    final scaled = (value * 2).round();
    final rounded = scaled / 2;
    final bool isInteger = scaled.isEven;
    final formatted = formatDouble(rounded, decimalDigits: isInteger ? 0 : 1);
    if (!includeApproximationSymbol) {
      return formatted;
    }
    return '~$formatted';
  }
}
