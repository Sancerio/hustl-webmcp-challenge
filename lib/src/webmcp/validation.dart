class InputValidation {
  static bool exactKeys(
    Map<String, Object?> input, {
    required Set<String> allowed,
    Set<String> required = const {},
  }) => input.keys.every(allowed.contains) && required.every(input.containsKey);

  static int? integer(Object? raw, int minimum, int maximum) {
    if (raw is! num || !raw.isFinite || raw.toInt() != raw) return null;
    final value = raw.toInt();
    return value >= minimum && value <= maximum ? value : null;
  }

  static double? number(Object? raw, double minimum, double maximum) {
    if (raw is! num || !raw.isFinite) return null;
    final value = raw.toDouble();
    if (value < minimum || value > maximum) return null;
    return value == 0 ? 0.0 : value;
  }

  static String? text(Object? raw, int minimum, int maximum) {
    if (raw is! String) return null;
    final rawLength = raw.runes.length;
    if (rawLength < minimum || rawLength > maximum) return null;
    final value = raw.trim();
    final normalizedLength = value.runes.length;
    return normalizedLength >= minimum && normalizedLength <= maximum
        ? value
        : null;
  }

  static bool realDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return false;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (year < 100) return false;
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }
}
