/// A PURE, synchronous weight-unit formatter over an already-resolved
/// 'kg' | 'lb' string.
///
/// `PreferencesService.getWeightUnit()` is async, so it can't be awaited per
/// paint. Resolve the unit ONCE in screen state (store the string), then build a
/// [WeightUnit] and pass it down — the hero, axis labels, stat strip, and every
/// weigh-in row format through this so the unit can never disagree. It never
/// touches preferences itself, so it's safe to call every frame.
class WeightUnit {
  const WeightUnit(this.unit);

  /// 'kg' or 'lb'. Anything other than 'lb' is treated as 'kg'.
  final String unit;

  static const double _kgPerLb = 0.45359237;

  bool get isLb => unit == 'lb';

  /// The unit suffix, e.g. 'kg' or 'lb'.
  String get suffix => isLb ? 'lb' : 'kg';

  /// Converts a stored-kg value into the display unit (e.g. for chart spots and
  /// axis bounds that must render in the user's unit).
  double toDisplay(double kg) => isLb ? kg / _kgPerLb : kg;

  double _toDisplay(double kg) => toDisplay(kg);

  /// A stored-kg value in the display unit, no suffix (e.g. '72.4').
  String value(double? kg, {int decimals = 1}) =>
      kg == null ? '—' : _toDisplay(kg).toStringAsFixed(decimals);

  /// A stored-kg value with the unit suffix (e.g. '72.4 kg').
  String formatWeight(double? kg, {int decimals = 1}) =>
      kg == null ? '—' : '${value(kg, decimals: decimals)} $suffix';

  /// A signed delta (stored kg) with a proper minus glyph + suffix
  /// (e.g. '−1.2 kg' / '+0.5 lb').
  String formatDelta(double? kgDelta, {int decimals = 1}) {
    if (kgDelta == null) return '—';
    final d = _toDisplay(kgDelta);
    final sign = d >= 0 ? '+' : '−';
    return '$sign${d.abs().toStringAsFixed(decimals)} $suffix';
  }
}
