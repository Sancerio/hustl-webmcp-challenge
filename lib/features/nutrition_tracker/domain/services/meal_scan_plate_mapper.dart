import '../models/food_log_entry.dart';
import '../models/meal_scan_result.dart';

String _formatPortionNumber(double value) {
  if (value % 1 == 0) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

bool _unitIsGrams(String? unit) {
  final normalized = unit?.trim().toLowerCase();
  return normalized == 'g' || normalized == 'gram' || normalized == 'grams';
}

String? buildMealScanItemPortionLabel(MealScanItem item) {
  final quantity = item.quantity;
  final unit = item.unit?.trim();

  // Count-style portions (e.g. "2 eggs") keep their unit + count. For weight
  // portions, the backend's resolved `grams` is authoritative (the macros are
  // scaled to it), so the label must match it — not a possibly-stale Gemini
  // `quantity` that can disagree (which made the UI show 200 g while the diary
  // logged 100 g).
  if (quantity != null && unit != null && unit.isNotEmpty && !_unitIsGrams(unit)) {
    return '${_formatPortionNumber(quantity)} $unit';
  }

  final grams = item.grams;
  if (grams != null && grams > 0) return '${grams.toStringAsFixed(0)}g';
  if (quantity != null && _unitIsGrams(unit)) return '${_formatPortionNumber(quantity)}g';
  if (quantity != null) return _formatPortionNumber(quantity);
  return null;
}

double _servingGramsFromMealScanItem(MealScanItem item) {
  // `grams` is the backend's authoritative resolved portion — the weight the
  // item's absolute macros were scaled to — so it is the source of truth for the
  // logged serving. Preferring `quantity` here logged 200 g as 100 g (and made
  // the serving disagree with the macros) whenever the two diverged.
  final grams = item.grams;
  if (grams != null && grams > 0) return grams;

  final quantity = item.quantity;
  if (quantity != null && _unitIsGrams(item.unit?.trim())) return quantity;

  return 1;
}

double _nonNegativeOrZero(double? value) =>
    value != null && value > 0 ? value : 0;

List<FoodLogEntry> mealScanResultToPlateEntries({
  required MealScanResult scan,
  required DateTime date,
  required DateTime loggedAt,
  String source = 'meal_scan_item',
  String Function(int index)? idFactory,
}) {
  final items = scan.items
      .map((item) => item.copyWith(name: item.name.trim()))
      .where((item) => item.name.isNotEmpty)
      .toList(growable: false);
  if (items.isEmpty) return const [];

  final idBase = 'temp-${DateTime.now().microsecondsSinceEpoch}';
  return List<FoodLogEntry>.generate(items.length, (index) {
    final item = items[index];
    // Do NOT attach a Food here: a DB-matched item only carries absolute
    // macros (already correct from the backend), not per-100g values. Linking a
    // Food with null per-100g macros makes the edit sheet rescale them to zero.
    // The absolute macros on the entry are authoritative and stay untouched.
    return FoodLogEntry(
      id: idFactory == null ? '$idBase-$index' : idFactory(index),
      date: date,
      loggedAt: loggedAt,
      servingGrams: _servingGramsFromMealScanItem(item),
      calories: _nonNegativeOrZero(item.caloriesKcal),
      proteinGrams: _nonNegativeOrZero(item.proteinGrams),
      carbsGrams: _nonNegativeOrZero(item.carbsGrams),
      fatGrams: _nonNegativeOrZero(item.fatGrams),
      foodName: item.name,
      portionLabel: buildMealScanItemPortionLabel(item),
      source: source,
    );
  });
}
