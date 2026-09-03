class TimeFormatUtil {
  /// Format seconds as mm:ss (00:00)
  static String formatMmSs(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  /// Parse text like "mm:ss" or plain seconds into seconds
  static int parseMmSs(String text) {
    final t = text.trim();
    if (t.isEmpty) return 0;
    final colon = t.indexOf(':');
    if (colon > -1) {
      final m = int.tryParse(t.substring(0, colon)) ?? 0;
      final s = int.tryParse(t.substring(colon + 1)) ?? 0;
      if (m < 0 || s < 0) return 0;
      return m * 60 + (s % 60);
    }
    return int.tryParse(t) ?? 0;
  }
}
