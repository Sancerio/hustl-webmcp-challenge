import '../../domain/models/food_log_entry.dart';

/// A stable key grouping logged entries by the food they represent.
String goToFoodKey(FoodLogEntry e) =>
    (e.food?.id ?? e.foodName ?? e.food?.name ?? '').toLowerCase().trim();

/// A dedupe key that matches how the BACKEND groups recents, for overlaying
/// still-queued offline creates onto server recents.
///
/// Unlike [goToFoodKey] (which always prefers `food.id`), this mirrors
/// [FoodLogEntry.toPayload] exactly: a generic on-device food carries an
/// asset id like `fdc-171705` that `toPayload` sends as `foodId: null`, so the
/// backend groups it by normalized `food_name`. Keying such a pending row by its
/// `fdc-*` id would NOT collapse against the name-keyed server row — showing the
/// same food twice in Recent until the create syncs.
///
/// So: use `food.id` ONLY when it is a canonical backend UUID
/// ([isBackendFoodId]); otherwise fall back to the normalized
/// (`foodName ?? food?.name`) — the exact name the payload sends and the
/// backend's `recentFoodKey` keys on.
String backendCompatibleKey(FoodLogEntry e) {
  final id = e.food?.id;
  if (isBackendFoodId(id)) return id!.toLowerCase().trim();
  return (e.foodName ?? e.food?.name ?? '').toLowerCase().trim();
}

class _Agg {
  _Agg(this.rep);
  final FoodLogEntry rep;
  double score = 0;
  int count = 0;
}

/// Ranks time-of-day "Go-tos" from [entries] (which must already be sorted
/// most-recent-first): the foods you usually log around [nowHour].
///
/// Score per entry = 1 + an hour-proximity boost (logged within ±2h of now
/// counts 3×, within ±4h counts 1.5×). Only foods logged at least [minCount]
/// times qualify — a one-off never becomes a go-to — and the most-recent entry
/// is kept as the re-log representative. Returns up to [limit] distinct foods,
/// or empty when the history is too thin to rank.
List<FoodLogEntry> goToEntries(
  List<FoodLogEntry> entries,
  int nowHour, {
  int limit = 4,
  int minCount = 2,
}) {
  final byFood = <String, _Agg>{};
  for (final e in entries) {
    final key = goToFoodKey(e);
    if (key.isEmpty) continue;
    final hour = e.loggedAt.toLocal().hour;
    final raw = (hour - nowHour).abs();
    final circ = raw > 12 ? 24 - raw : raw; // wrap around midnight
    final boost = circ <= 2
        ? 2.0
        : circ <= 4
        ? 0.5
        : 0.0;
    final agg = byFood.putIfAbsent(key, () => _Agg(e));
    agg.score += 1 + boost;
    agg.count += 1;
  }
  final ranked = byFood.values.where((a) => a.count >= minCount).toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  return ranked.take(limit).map((a) => a.rep).toList(growable: false);
}
