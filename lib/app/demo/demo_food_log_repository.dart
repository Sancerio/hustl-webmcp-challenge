import '../../features/nutrition_tracker/domain/models/food_log_entry.dart';
import '../../features/nutrition_tracker/domain/repositories/food_log_repository.dart';

/// Deterministic in-memory [FoodLogRepository] for demo mode.
///
/// Today's diary is seeded with exactly 4 meals summing to 1,430 kcal
/// (P 118 / C 142 / F 48 g), spread across breakfast / lunch / snack / dinner
/// so the diary timeline renders four populated hour groups. Other days are
/// empty (so navigating back shows the kind empty state).
class DemoFoodLogRepository
    implements FoodLogRepository, ReadOnlyFoodLogRepository {
  DemoFoodLogRepository({required DateTime anchor})
    : _today = DateTime(anchor.year, anchor.month, anchor.day),
      _entries = <FoodLogEntry>[] {
    _entries.addAll(_seedToday());
  }

  final DateTime _today;
  final List<FoodLogEntry> _entries;

  List<FoodLogEntry> _seedToday() {
    return [
      _entry(
        id: '11111111-1111-4111-8111-111111111111',
        hour: 8,
        name: 'Greek yogurt, berries & granola',
        grams: 320,
        calories: 380,
        protein: 30,
        carbs: 42,
        fat: 10,
        fiber: 6,
        sugar: 18,
        sodium: 120,
      ),
      _entry(
        id: '22222222-2222-4222-8222-222222222222',
        hour: 13,
        name: 'Chicken & rice bowl',
        grams: 450,
        calories: 520,
        protein: 42,
        carbs: 50,
        fat: 16,
        fiber: 8,
        sugar: 6,
        sodium: 640,
      ),
      _entry(
        id: '33333333-3333-4333-8333-333333333333',
        hour: 16,
        name: 'Protein shake & banana',
        grams: 380,
        calories: 230,
        protein: 20,
        carbs: 22,
        fat: 7,
        fiber: 3,
        sugar: 16,
        sodium: 180,
      ),
      _entry(
        id: '44444444-4444-4444-8444-444444444444',
        hour: 19,
        minute: 30,
        name: 'Salmon, potatoes & greens',
        grams: 420,
        calories: 300,
        protein: 26,
        carbs: 28,
        fat: 15,
        fiber: 7,
        sugar: 5,
        sodium: 520,
      ),
    ];
  }

  FoodLogEntry _entry({
    required String id,
    required int hour,
    int minute = 0,
    required String name,
    required double grams,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    required double fiber,
    required double sugar,
    required double sodium,
  }) {
    final loggedAt = _today.add(Duration(hours: hour, minutes: minute));
    return FoodLogEntry(
      id: id,
      date: _today,
      loggedAt: loggedAt,
      servingGrams: grams,
      calories: calories,
      proteinGrams: protein,
      carbsGrams: carbs,
      fatGrams: fat,
      fiberGrams: fiber,
      sugarGrams: sugar,
      sodiumMg: sodium,
      foodName: name,
    );
  }

  bool _isToday(DateTime date) {
    final local = date.toLocal();
    return local.year == _today.year &&
        local.month == _today.month &&
        local.day == _today.day;
  }

  @override
  Future<List<FoodLogEntry>> getLogsForDate(DateTime date) async {
    if (!_isToday(date)) return const [];
    final list = List<FoodLogEntry>.from(
      _entries.where((e) => _isToday(e.date)),
    )..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
    return list;
  }

  @override
  Future<List<FoodLogEntry>> getLogsForDateReadOnly(DateTime date) =>
      getLogsForDate(date);

  @override
  Future<List<FoodLogEntry>> getLogsForRange(
    DateTime start,
    DateTime end,
  ) async {
    // Demo data only exists on the anchor day; return it when in range so the
    // CSV export produces a plausible one-day file in demo mode.
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    if (_today.isBefore(startDay) || _today.isAfter(endDay)) return const [];
    return getLogsForDate(_today);
  }

  @override
  Future<FoodSuggestions> getSuggestions({
    required int tzOffsetMinutes,
    int recentLimit = 12,
    int suggestionLimit = 4,
  }) async {
    // Demo recents: the seeded meals, most-recent first, collapsed to distinct
    // foods by name. Demo history is intentionally thin, so "Suggested for now"
    // stays empty (mirrors the backend's min-history guard) and the empty state
    // shows the Recent strip only.
    final sorted = List<FoodLogEntry>.from(_entries)
      ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
    final seen = <String>{};
    final recents = <FoodLogEntry>[];
    for (final e in sorted) {
      final key = (e.foodName ?? e.food?.name ?? '').toLowerCase().trim();
      if (key.isEmpty || !seen.add(key)) continue;
      recents.add(e);
      if (recents.length >= recentLimit) break;
    }
    return FoodSuggestions(suggestions: const [], recents: recents);
  }

  @override
  Future<List<FoodLogEntry>> addEntries(List<FoodLogEntry> entries) async {
    _entries.addAll(entries);
    return entries;
  }

  /// Returns the exact in-memory row used by proposal preview/apply logic.
  /// Demo-only collaborators use this instead of performing an unbounded scan.
  FoodLogEntry? findEntry(String id) {
    for (final entry in _entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// Restores a prior immutable row at its original logical identity.
  void restoreEntry(FoodLogEntry entry) {
    final index = _entries.indexWhere((candidate) => candidate.id == entry.id);
    if (index < 0) {
      _entries.add(entry);
    } else {
      _entries[index] = entry;
    }
  }

  void removeEntries(Iterable<String> ids) {
    final idSet = ids.toSet();
    _entries.removeWhere((entry) => idSet.contains(entry.id));
  }

  @override
  Future<FoodLogEntry> updateEntry(
    String id,
    Map<String, dynamic> patch,
  ) async {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index < 0) {
      throw StateError('Demo food entry $id not found');
    }
    final current = _entries[index];
    final updated = FoodLogEntry(
      id: current.id,
      date: current.date,
      loggedAt: current.loggedAt,
      servingGrams:
          (patch['servingGrams'] as num?)?.toDouble() ?? current.servingGrams,
      calories: (patch['calories'] as num?)?.toDouble() ?? current.calories,
      proteinGrams:
          (patch['proteinGrams'] as num?)?.toDouble() ?? current.proteinGrams,
      carbsGrams:
          (patch['carbsGrams'] as num?)?.toDouble() ?? current.carbsGrams,
      fatGrams: (patch['fatGrams'] as num?)?.toDouble() ?? current.fatGrams,
      fiberGrams:
          (patch['fiberGrams'] as num?)?.toDouble() ?? current.fiberGrams,
      sugarGrams:
          (patch['sugarGrams'] as num?)?.toDouble() ?? current.sugarGrams,
      sodiumMg: (patch['sodiumMg'] as num?)?.toDouble() ?? current.sodiumMg,
      food: current.food,
      foodName: patch['foodName']?.toString() ?? current.foodName,
      portionLabel: current.portionLabel,
      source: current.source,
    );
    _entries[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteEntry(String id) async {
    _entries.removeWhere((e) => e.id == id);
  }

  @override
  Future<List<FoodLogEntry>> copyDay(
    DateTime fromDate,
    DateTime toDate, {
    bool replaceExisting = false,
  }) async {
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    if (replaceExisting) {
      _entries.removeWhere((e) => sameDay(e.date, toDate));
    }
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final source = _entries.where((e) => sameDay(e.date, fromDate)).toList();
    final copies = [
      for (var i = 0; i < source.length; i++)
        FoodLogEntry(
          id: 'demo-copy-$stamp-$i',
          date: toDate,
          loggedAt: DateTime(
            toDate.year,
            toDate.month,
            toDate.day,
            source[i].loggedAt.hour,
            source[i].loggedAt.minute,
            source[i].loggedAt.second,
          ),
          servingGrams: source[i].servingGrams,
          calories: source[i].calories,
          proteinGrams: source[i].proteinGrams,
          carbsGrams: source[i].carbsGrams,
          fatGrams: source[i].fatGrams,
          fiberGrams: source[i].fiberGrams,
          sugarGrams: source[i].sugarGrams,
          sodiumMg: source[i].sodiumMg,
          foodName: source[i].foodName,
          portionLabel: source[i].portionLabel,
          source: source[i].source,
        ),
    ];
    _entries.addAll(copies);
    return copies;
  }
}
