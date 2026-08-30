import 'package:intl/intl.dart';

/// Human-readable relative date labels for workout surfaces.
///
/// Replaces the ad-hoc `DateTime.toString().split(' ').first` ISO strings that
/// were scattered across the home, summary and template-save call sites.
class WorkoutDateLabel {
  WorkoutDateLabel._();

  /// "Today" / "Yesterday" / "Jun 11" (same year) / "Jun 11, 2025" otherwise.
  static String relative(DateTime time, {DateTime? now}) {
    final local = time.toLocal();
    final reference = (now ?? DateTime.now()).toLocal();
    final today = DateTime(reference.year, reference.month, reference.day);
    final day = DateTime(local.year, local.month, local.day);
    final diffDays = today.difference(day).inDays;

    if (diffDays == 0) return 'Today';
    if (diffDays == 1) return 'Yesterday';
    if (local.year == reference.year) {
      return DateFormat('MMM d').format(local);
    }
    return DateFormat('MMM d, y').format(local);
  }

  /// Compact absolute date, e.g. "Jun 11, 2025" — used in descriptions.
  static String absolute(DateTime time) =>
      DateFormat('MMM d, y').format(time.toLocal());
}
