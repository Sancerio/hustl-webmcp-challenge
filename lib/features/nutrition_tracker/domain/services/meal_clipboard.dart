import '../models/food_log_entry.dart';

/// A copy/paste clipboard for week-planning (MacroFactor-style). The user copies
/// a day's entries once, then pastes that snapshot onto one or many future days.
///
/// This complements [CopyFromDaySheet], which copies straight from a past day to
/// the current day in one shot. The clipboard instead holds a snapshot so a
/// single copy can be pasted across the rest of the week.
///
/// Process-local and ephemeral: the snapshot lives only for the session and is
/// not persisted. Exposed as a [MealClipboard.instance] singleton because the
/// feature's DI file owns the repositories, not this service.
class MealClipboard {
  MealClipboard();

  /// Shared process-wide clipboard. Tests may construct their own instance.
  static final MealClipboard instance = MealClipboard();

  List<FoodLogEntry> _entries = const [];
  DateTime? _sourceDate;

  /// True once a day has been copied and not cleared.
  bool get hasContent => _entries.isNotEmpty;

  /// The copied snapshot (defensive copy; never the caller's live list).
  List<FoodLogEntry> get entries => List<FoodLogEntry>.unmodifiable(_entries);

  /// The day the snapshot was copied from (`null` when empty).
  DateTime? get sourceDate => _sourceDate;

  /// How many foods are on the clipboard.
  int get count => _entries.length;

  /// Snapshots [entries] copied from [sourceDate]. An empty list clears the
  /// clipboard so [hasContent] stays honest.
  void copy(List<FoodLogEntry> entries, {DateTime? sourceDate}) {
    _entries = List<FoodLogEntry>.unmodifiable(entries);
    _sourceDate = entries.isEmpty
        ? null
        : (sourceDate == null
              ? null
              : DateTime(sourceDate.year, sourceDate.month, sourceDate.day));
  }

  /// Empties the clipboard.
  void clear() {
    _entries = const [];
    _sourceDate = null;
  }
}
