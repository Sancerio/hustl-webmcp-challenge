import '../models/food_log_entry.dart';
import '../repositories/food_log_repository.dart';

/// Fetches the user's full food-log history for export by walking backwards
/// from today in windows the backend accepts (`GET /api/nutrition/logs`
/// caps `start..end` at 366 days).
///
/// The walk stops at the first EMPTY window found after data has been seen
/// (we've walked past the account's first entry), or at a 10-year hard floor
/// (matching the weight screen's 3650-day "All" range). Leading empty windows
/// do NOT stop the walk, so a long recent logging gap can't truncate older
/// history. Any fetch failure propagates to the caller — an export must fail
/// loudly rather than produce a silently incomplete file.
class FoodLogHistoryLoader {
  const FoodLogHistoryLoader({required this.repository});

  final FoodLogRepository repository;

  /// Backend cap for one `start..end` request (inclusive days).
  static const int windowDays = 366;

  /// Hard floor: never walk more than ~10 years back.
  static const int maxHistoryDays = 3650;

  /// Loads every entry from today back to the account's first data (or the
  /// 10-year floor), oldest first. [onWindowFetched] reports 1-based window
  /// counts for a simple progress indicator.
  Future<List<FoodLogEntry>> loadAll({
    DateTime? now,
    void Function(int windowsFetched)? onWindowFetched,
  }) async {
    final today = now ?? DateTime.now();
    final endDay = DateTime(today.year, today.month, today.day);
    final floor = DateTime(endDay.year, endDay.month, endDay.day - maxHistoryDays);

    final all = <FoodLogEntry>[];
    var windowEnd = endDay;
    var windowsFetched = 0;

    while (!windowEnd.isBefore(floor)) {
      var windowStart = DateTime(
        windowEnd.year,
        windowEnd.month,
        windowEnd.day - (windowDays - 1),
      );
      if (windowStart.isBefore(floor)) windowStart = floor;

      final entries = await repository.getLogsForRange(windowStart, windowEnd);
      windowsFetched += 1;
      onWindowFetched?.call(windowsFetched);

      if (entries.isEmpty && all.isNotEmpty) break;
      all.addAll(entries);

      windowEnd = DateTime(
        windowStart.year,
        windowStart.month,
        windowStart.day - 1,
      );
    }

    all.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      return a.loggedAt.compareTo(b.loggedAt);
    });
    return all;
  }
}
