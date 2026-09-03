import '../models/food.dart';

/// Search results plus the backend's cache-demotion flags. When the live food
/// provider times out or errors, the backend falls back to a past-TTL cache and
/// reports [isStale]/[staleAgeMs] so the UI can offer a refresh.
class FoodSearchResult {
  const FoodSearchResult({
    required this.foods,
    this.isStale = false,
    this.staleAgeMs,
  });

  final List<Food> foods;
  final bool isStale;
  final int? staleAgeMs;
}

abstract class FoodRepository {
  Future<List<Food>> searchFoods(String query, {int limit = 20});

  /// Like [searchFoods] but preserves the backend's stale-cache flags so the
  /// search surface can show "showing saved results — tap to refresh".
  Future<FoodSearchResult> searchFoodsResult(String query, {int limit = 20});

  Future<Food?> lookupBarcode(String barcode);
  Future<List<Food>> listCustomFoods();
  Future<Food> createCustomFood(Food food);
  Future<List<Food>> listFavorites({int limit = 10});
  Future<Set<String>> listFavoriteIds({int limit = 5000});
  Future<void> addFavorite(String foodId);
  Future<void> removeFavorite(String foodId);
}
