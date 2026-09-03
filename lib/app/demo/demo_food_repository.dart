import '../../features/nutrition_tracker/domain/models/food.dart';
import '../../features/nutrition_tracker/domain/repositories/food_repository.dart';

/// Deterministic in-memory [FoodRepository] for demo mode.
///
/// Provides a small curated catalog so the Add Food search, favorites and
/// barcode flows return populated, reproducible results offline.
class DemoFoodRepository implements FoodRepository {
  DemoFoodRepository() : _favorites = {'demo-food-chicken', 'demo-food-rice'};

  final Set<String> _favorites;

  static const List<Food> _catalog = [
    Food(
      id: 'demo-food-chicken',
      name: 'Chicken breast, grilled',
      source: 'demo',
      servingSizeGrams: 100,
      caloriesPer100g: 165,
      proteinPer100g: 31,
      carbsPer100g: 0,
      fatPer100g: 3.6,
      completeness: 1,
    ),
    Food(
      id: 'demo-food-rice',
      name: 'White rice, cooked',
      source: 'demo',
      servingSizeGrams: 100,
      caloriesPer100g: 130,
      proteinPer100g: 2.7,
      carbsPer100g: 28,
      fatPer100g: 0.3,
      completeness: 1,
    ),
    Food(
      id: 'demo-food-yogurt',
      name: 'Greek yogurt, plain',
      brand: 'Demo Dairy',
      barcode: '0123456789012',
      source: 'demo',
      servingSizeGrams: 170,
      caloriesPer100g: 59,
      proteinPer100g: 10,
      carbsPer100g: 3.6,
      fatPer100g: 0.4,
      completeness: 1,
    ),
    Food(
      id: 'demo-food-banana',
      name: 'Banana',
      source: 'demo',
      servingSizeGrams: 118,
      caloriesPer100g: 89,
      proteinPer100g: 1.1,
      carbsPer100g: 23,
      fatPer100g: 0.3,
      completeness: 1,
    ),
    Food(
      id: 'demo-food-salmon',
      name: 'Salmon, baked',
      source: 'demo',
      servingSizeGrams: 100,
      caloriesPer100g: 208,
      proteinPer100g: 20,
      carbsPer100g: 0,
      fatPer100g: 13,
      completeness: 1,
    ),
    Food(
      id: 'demo-food-oats',
      name: 'Rolled oats, dry',
      source: 'demo',
      servingSizeGrams: 40,
      caloriesPer100g: 379,
      proteinPer100g: 13,
      carbsPer100g: 67,
      fatPer100g: 6.5,
      completeness: 1,
    ),
    Food(
      id: 'demo-food-eggs',
      name: 'Eggs, whole',
      source: 'demo',
      servingSizeGrams: 50,
      caloriesPer100g: 143,
      proteinPer100g: 13,
      carbsPer100g: 0.7,
      fatPer100g: 9.5,
      completeness: 1,
    ),
    Food(
      id: 'demo-food-almonds',
      name: 'Almonds',
      source: 'demo',
      servingSizeGrams: 28,
      caloriesPer100g: 579,
      proteinPer100g: 21,
      carbsPer100g: 22,
      fatPer100g: 50,
      completeness: 1,
    ),
  ];

  @override
  Future<List<Food>> searchFoods(String query, {int limit = 20}) async {
    final q = query.trim().toLowerCase();
    final matches = q.isEmpty
        ? _catalog
        : _catalog
              .where((f) => f.name.toLowerCase().contains(q))
              .toList(growable: false);
    return matches.take(limit).toList(growable: false);
  }

  @override
  Future<FoodSearchResult> searchFoodsResult(
    String query, {
    int limit = 20,
  }) async {
    // Demo mode is always "fresh" — there is no live provider to fall back from.
    return FoodSearchResult(foods: await searchFoods(query, limit: limit));
  }

  @override
  Future<Food?> lookupBarcode(String barcode) async {
    for (final food in _catalog) {
      if (food.barcode == barcode) return food;
    }
    return null;
  }

  @override
  Future<List<Food>> listCustomFoods() async => const [];

  @override
  Future<Food> createCustomFood(Food food) async => food;

  @override
  Future<List<Food>> listFavorites({int limit = 10}) async {
    return _catalog
        .where((f) => _favorites.contains(f.id))
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<Set<String>> listFavoriteIds({int limit = 5000}) async {
    return Set<String>.from(_favorites);
  }

  @override
  Future<void> addFavorite(String foodId) async {
    _favorites.add(foodId);
  }

  @override
  Future<void> removeFavorite(String foodId) async {
    _favorites.remove(foodId);
  }
}
