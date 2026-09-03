import 'dart:typed_data';

import '../../features/nutrition_tracker/domain/models/meal_scan_result.dart';
import '../../features/nutrition_tracker/domain/repositories/meal_scan_repository.dart';

/// Deterministic [MealScanRepository] for demo mode.
///
/// Returns a fixed, plausible meal-scan result without any network call so the
/// camera/scan flow can be demoed offline.
class DemoMealScanRepository implements MealScanRepository {
  const DemoMealScanRepository();

  @override
  Future<MealScanResult> scanMealPhoto({
    required Uint8List imageBytes,
    required String mimeType,
    String? notes,
    String? restaurant,
    String? locale,
  }) async => _sampleResult;

  @override
  Future<MealScanResult> describeMeal({
    required String text,
    String? notes,
    String? restaurant,
    String? locale,
  }) async => _sampleResult;

  static const MealScanResult _sampleResult = MealScanResult(
    mealName: 'Chicken & rice bowl',
    totals: MealScanTotals(
      caloriesKcal: 520,
      proteinGrams: 42,
      carbsGrams: 50,
      fatGrams: 16,
    ),
    items: [
      MealScanItem(
        name: 'Grilled chicken breast',
        quantity: 180,
        unit: 'g',
        grams: 180,
        caloriesKcal: 297,
        proteinGrams: 56,
        carbsGrams: 0,
        fatGrams: 6.5,
      ),
      MealScanItem(
        name: 'White rice',
        quantity: 150,
        unit: 'g',
        grams: 150,
        caloriesKcal: 195,
        proteinGrams: 4,
        carbsGrams: 42,
        fatGrams: 0.5,
      ),
      MealScanItem(
        name: 'Mixed greens',
        quantity: 80,
        unit: 'g',
        grams: 80,
        caloriesKcal: 28,
        proteinGrams: 2,
        carbsGrams: 4,
        fatGrams: 0.5,
      ),
    ],
    confidence: 0.86,
    assumptions: ['Assumed standard restaurant portion sizes.'],
    warnings: [],
    debug: MealScanDebug(model: 'demo', latencyMs: 0),
  );
}
