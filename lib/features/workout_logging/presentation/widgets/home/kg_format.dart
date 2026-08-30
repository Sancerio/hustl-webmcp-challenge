import 'package:hustl_app/core/utils/number_format_util.dart';

/// Compact kilogram label for dashboard numbers: '860', '4k', '12.4k'.
/// Whole thousands drop the trailing '.0' so the number stays quiet.
String formatCompactKg(double v) {
  if (v < 1000) return NumberFormatUtil.formatDouble(v, decimalDigits: 0);
  final thousands = v / 1000;
  final isWhole = (thousands - thousands.round()).abs() < 0.05;
  return '${NumberFormatUtil.formatDouble(thousands, decimalDigits: isWhole ? 0 : 1)}k';
}
