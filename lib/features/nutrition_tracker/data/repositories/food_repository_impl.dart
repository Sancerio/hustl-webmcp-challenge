import 'dart:math' as math;

import '../../domain/models/food.dart';
import '../../domain/repositories/food_repository.dart';
import '../datasources/hustl_backend_nutrition_api.dart';
import '../sources/local_food_index.dart';

class FoodRepositoryImpl implements FoodRepository {
  FoodRepositoryImpl({required this.api, this.localFoodIndex});

  final HustlBackendNutritionApi api;

  /// Optional offline-first index over the bundled generic foods asset. When
  /// present, [searchFoodsResult] queries it in parallel with the backend and
  /// merges the two result sets. When null the repository is backend-only and
  /// behaves exactly as before.
  final LocalFoodIndex? localFoodIndex;

  @override
  Future<List<Food>> searchFoods(String query, {int limit = 20}) async {
    final items = await api.searchFoods(query, limit: limit);
    return items.map(Food.fromMap).toList(growable: false);
  }

  @override
  Future<FoodSearchResult> searchFoodsResult(
    String query, {
    int limit = 20,
  }) async {
    final index = localFoodIndex;
    if (index == null) {
      return _backendOnlyResult(query, limit: limit);
    }

    // Resolve the local leg first so the on-device index can always serve
    // results — even when the backend is offline or erroring. The local index
    // degrades to an empty list on any failure, so this never throws.
    final localFoods = await index.search(query, limit: limit);

    final FoodSearchApiResult backendRaw;
    try {
      backendRaw = await api.searchFoodsResult(query, limit: limit);
    } catch (_) {
      // Offline-first: a backend failure must not defeat the on-device index.
      // If local has matches, serve them (fresh local data — not a stale
      // backend cache). Otherwise rethrow so the UI still surfaces an error
      // when there is genuinely nothing to show.
      if (localFoods.isNotEmpty) {
        return FoodSearchResult(foods: localFoods);
      }
      rethrow;
    }

    final backendFoods = backendRaw.items
        .map(Food.fromMap)
        .toList(growable: false);

    if (localFoods.isEmpty) {
      return FoodSearchResult(
        foods: backendFoods,
        isStale: backendRaw.isStale,
        staleAgeMs: backendRaw.staleAgeMs,
      );
    }

    return FoodSearchResult(
      foods: _merge(local: localFoods, backend: backendFoods, limit: limit),
      isStale: backendRaw.isStale,
      staleAgeMs: backendRaw.staleAgeMs,
    );
  }

  Future<FoodSearchResult> _backendOnlyResult(
    String query, {
    required int limit,
  }) async {
    final result = await api.searchFoodsResult(query, limit: limit);
    return FoodSearchResult(
      foods: result.items.map(Food.fromMap).toList(growable: false),
      isStale: result.isStale,
      staleAgeMs: result.staleAgeMs,
    );
  }

  /// Merges local generic results with backend (branded) results, deduped by
  /// `(name, brand, barcode)`. Local generics lead the list but are capped so
  /// they never monopolize the window: at most `ceil(limit/2)` local rows are
  /// kept, leaving the remaining slots for the backend's branded/long-tail
  /// rows. Backend rows fill the rest (and win on collision, preserving their
  /// provenance/stale data). The final list is truncated to [limit].
  List<Food> _merge({
    required List<Food> local,
    required List<Food> backend,
    required int limit,
  }) {
    if (limit <= 0) return const <Food>[];

    // Reserve slots for backend rows: local takes at most half the window so a
    // broad prefix of local generics cannot starve the backend long-tail.
    final localCap = math.max(1, (limit / 2).ceil());

    final ordered = <String, Food>{};
    var localKept = 0;
    for (final food in local) {
      if (localKept >= localCap) break;
      ordered[_dedupeKey(food)] = food;
      localKept++;
    }
    for (final food in backend) {
      // Backend wins on collision (preserve provenance/stale data).
      ordered[_dedupeKey(food)] = food;
    }
    final merged = ordered.values.toList(growable: false);
    if (merged.length <= limit) return merged;
    return merged.sublist(0, limit);
  }

  String _dedupeKey(Food food) {
    final name = food.name.trim().toLowerCase();
    final brand = (food.brand ?? '').trim().toLowerCase();
    final barcode = (food.barcode ?? '').trim().toLowerCase();
    return '$name\x00$brand\x00$barcode';
  }

  @override
  Future<Food?> lookupBarcode(String barcode) async {
    final map = await api.lookupBarcode(barcode);
    if (map == null) return null;
    return Food.fromMap(map);
  }

  @override
  Future<List<Food>> listCustomFoods() async {
    final items = await api.listCustomFoods();
    return items.map(Food.fromMap).toList(growable: false);
  }

  @override
  Future<Food> createCustomFood(Food food) async {
    final created = await api.createCustomFood(food.toMap());
    return Food.fromMap(created);
  }

  @override
  Future<List<Food>> listFavorites({int limit = 10}) async {
    final items = await api.listFoodFavorites(limit: limit);
    return items
        .map((item) => item['food'])
        .whereType<Map>()
        .map((food) => Food.fromMap(Map<String, dynamic>.from(food)))
        .toList(growable: false);
  }

  @override
  Future<Set<String>> listFavoriteIds({int limit = 5000}) async {
    final ids = await api.listFoodFavoriteIds(limit: limit);
    return ids.toSet();
  }

  @override
  Future<void> addFavorite(String foodId) async {
    await api.addFoodFavorite(foodId);
  }

  @override
  Future<void> removeFavorite(String foodId) async {
    await api.removeFoodFavorite(foodId);
  }
}
