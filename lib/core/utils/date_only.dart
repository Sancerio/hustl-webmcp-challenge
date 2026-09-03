DateTime? tryParseLocalDateOnly(String? ymd) {
  if (ymd == null) return null;
  final v = ymd.trim();
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v);
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;

  final dt = DateTime(year, month, day);
  if (dt.year != year || dt.month != month || dt.day != day) return null;
  return dt;
}

DateTime parseLocalDateOnly(String ymd) {
  final dt = tryParseLocalDateOnly(ymd);
  if (dt == null) throw FormatException('Invalid YYYY-MM-DD date', ymd);
  return dt;
}
