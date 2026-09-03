import '../models/food_log_entry.dart';

/// Strict, non-mutating food-log reads for agent and preview surfaces.
///
/// Unlike the diary read below, this contract never flushes queued writes and
/// propagates remote failures so callers cannot mistake an outage for zero.
abstract interface class ReadOnlyFoodLogRepository {
  Future<List<FoodLogEntry>> getLogsForDateReadOnly(DateTime date);
}

/// The add-food empty-state payload from `GET /api/nutrition/foods/suggestions`:
/// the time-of-day "Suggested for now" foods plus the distinct-by-recency
/// "Recent" foods (already de-duped against suggestions server-side).
class FoodSuggestions {
  const FoodSuggestions({this.suggestions = const [], this.recents = const []});

  /// "Suggested for now" — foods the user usually logs around this time of day.
  /// Empty when the backend's min-history guards suppress the section.
  final List<FoodLogEntry> suggestions;

  /// Distinct recently-logged foods, ordered by recency.
  final List<FoodLogEntry> recents;
}

abstract class FoodLogRepository {
  Future<List<FoodLogEntry>> getLogsForDate(DateTime date);

  /// All entries with [start] <= date <= [end] (inclusive), ordered by date
  /// then logged-at. The backend caps one window at 366 days, so long-history
  /// callers (the CSV export) walk back one window at a time. Online-only —
  /// unlike [getLogsForDate] this throws on failure instead of degrading to
  /// the offline queue, so an export can never silently truncate history.
  Future<List<FoodLogEntry>> getLogsForRange(DateTime start, DateTime end);

  /// Loads the add-food empty-state suggestions in a single round-trip. The
  /// optional [tzOffsetMinutes] (the client's `DateTime.timeZoneOffset
  /// .inMinutes`) drives the tz-aware time-of-day ranking. Best-effort: returns
  /// empty lists on any failure so the sheet still opens.
  Future<FoodSuggestions> getSuggestions({
    required int tzOffsetMinutes,
    int recentLimit,
    int suggestionLimit,
  });
  Future<List<FoodLogEntry>> addEntries(List<FoodLogEntry> entries);
  Future<FoodLogEntry> updateEntry(String id, Map<String, dynamic> patch);
  Future<void> deleteEntry(String id);

  /// Copies every entry from [fromDate] onto [toDate] (server-side, preserving
  /// each entry's local time-of-day), returning the inserted entries so the
  /// caller can offer Undo. When [replaceExisting] is true the target day is
  /// cleared first. Online-only — throws if the copy can't reach the server.
  Future<List<FoodLogEntry>> copyDay(
    DateTime fromDate,
    DateTime toDate, {
    bool replaceExisting = false,
  });
}
