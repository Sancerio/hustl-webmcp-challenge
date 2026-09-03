import '../../domain/models/food.dart';
import '../../domain/models/food_log_entry.dart';

/// Builds the user's logged-food HISTORY matches for an active search query,
/// derived from the same recents/suggestions infra that powers the empty-state
/// strip. Users re-eat the same foods, so a query that matches a food they've
/// logged before should surface that food FIRST — above the generic catalog —
/// and re-logging it should pre-fill the serving + macros they always use.
///
/// This is a pure, local transform over data already in memory ([suggested] +
/// [latest]), so the history leg resolves INSTANTLY as the user types, with no
/// network round-trip. The catalog/backend results merge in around it as they
/// arrive (see [mergeCatalogAfterHistory]).

/// A name-based dedupe key matching how a catalog [Food] is grouped against the
/// user's history. Mirrors the backend's name-keyed recents and the catalog
/// merge key (lower-cased, trimmed name) so a history food and the same catalog
/// food collapse to one row. Brand is folded in when present so two distinct
/// branded products with the same base name don't wrongly merge.
String historyFoodKey(Food food) {
  final name = food.name.trim().toLowerCase();
  final brand = (food.brand ?? '').trim().toLowerCase();
  return brand.isEmpty ? name : '$name\x00$brand';
}

String _entryHistoryKey(FoodLogEntry entry) {
  final name = (entry.foodName ?? entry.food?.name ?? '').trim().toLowerCase();
  final brand = (entry.food?.brand ?? '').trim().toLowerCase();
  return brand.isEmpty ? name : '$name\x00$brand';
}

/// Converts a logged-history [entry] into a search-result [Food].
///
/// The entry stores the user's LAST-USED serving + the ABSOLUTE macros at that
/// serving; search rows render and re-log on a per-100g basis (the portion
/// stepper scales `caloriesPer100g × grams/100`). So we back out per-100g macros
/// from the serving and set [Food.servingSizeGrams] to the user's last-used
/// portion. That makes re-logging a staple pre-fill their usual amount and the
/// correct macros — the exact serving-carry contract the portion stepper already
/// honours for `recent` rows (it reads `servingSizeGrams` with no special
/// casing). Tagged `trustTier: 'recent'` so the row shows the quiet "Recent"
/// provenance hint, consistent with backend-resurfaced recents.
Food historyEntryToFood(FoodLogEntry entry) {
  final grams = entry.servingGrams;
  // Per-100g back-out; guard a zero/absent serving so we never divide by zero
  // (fall back to treating the snapshot as a per-100g row).
  final per100 = grams > 0 ? 100 / grams : 1.0;
  double scale(double value) => value * per100;

  final name = entry.foodName ?? entry.food?.name ?? 'Food';
  final sourceFood = entry.food;
  return Food(
    // Reuse the canonical backend food id when the entry carries one (so the
    // favorite star + any id-keyed behavior still works); otherwise a stable
    // history id keyed on the food name keeps the row identity stable across
    // rebuilds (used for the expand/collapse toggle).
    id: sourceFood != null && isBackendFoodId(sourceFood.id)
        ? sourceFood.id
        : 'history:${name.trim().toLowerCase()}',
    name: name,
    brand: sourceFood?.brand,
    barcode: sourceFood?.barcode,
    source: sourceFood?.source ?? entry.source,
    // The user's last-used serving — pre-fills the stepper + quick-add grams.
    servingSizeGrams: grams > 0 ? grams : sourceFood?.servingSizeGrams,
    caloriesPer100g: scale(entry.calories),
    proteinPer100g: scale(entry.proteinGrams),
    carbsPer100g: scale(entry.carbsGrams),
    fatPer100g: scale(entry.fatGrams),
    fiberPer100g: entry.fiberGrams == null ? null : scale(entry.fiberGrams!),
    sugarPer100g: entry.sugarGrams == null ? null : scale(entry.sugarGrams!),
    sodiumMgPer100g: entry.sodiumMg == null ? null : scale(entry.sodiumMg!),
    trustTier: 'recent',
  );
}

/// Filters + ranks the user's logged history to the foods whose name matches
/// [query], most-relevant first. [suggested] (time-of-day go-tos) lead, then the
/// recency/frequency-ranked [latest] recents, deduped by the history key so a
/// food that's both appears once (kept as the higher-ranked suggestion). The
/// result is a list of history-derived [Food]s carrying the user's last-used
/// serving (see [historyEntryToFood]).
///
/// Matching is a case-insensitive substring over the food name — a typed query
/// like "chick" surfaces "Grilled chicken". Empty/whitespace queries match
/// nothing (the empty-state strip handles the no-query landing).
List<Food> historyMatches(
  String query, {
  required List<FoodLogEntry> suggested,
  required List<FoodLogEntry> latest,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const <Food>[];

  bool matches(FoodLogEntry e) {
    final name = (e.foodName ?? e.food?.name ?? '').toLowerCase();
    return name.contains(q);
  }

  final out = <Food>[];
  final seen = <String>{};
  void take(FoodLogEntry e) {
    if (!matches(e)) return;
    final key = _entryHistoryKey(e);
    // An empty-keyed entry can't be deduped reliably; skip it (a nameless log
    // can't match a typed query anyway).
    if (key.isEmpty || !seen.add(key)) return;
    out.add(historyEntryToFood(e));
  }

  for (final e in suggested) {
    take(e);
  }
  for (final e in latest) {
    take(e);
  }
  return out;
}

/// Appends the [catalog]/backend results AFTER the [history] matches, dropping
/// any catalog row that's already represented by a history match (deduped by
/// [historyFoodKey]). The history match wins the slot — ranked first AND keeping
/// the user's last-used serving/macros — so re-logging a staple pre-fills their
/// usual amount instead of the catalog 100g default. Foods NOT in the user's
/// history pass through from the catalog unchanged.
List<Food> mergeCatalogAfterHistory({
  required List<Food> history,
  required List<Food> catalog,
}) {
  if (history.isEmpty) return catalog;
  final seen = history.map(historyFoodKey).toSet();
  final merged = <Food>[...history];
  for (final food in catalog) {
    if (seen.add(historyFoodKey(food))) merged.add(food);
  }
  return merged;
}
