import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/meal_scan_result.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/services/meal_scan_plate_mapper.dart';

void main() {
  test('mealScanResultToPlateEntries maps items to plate entries', () {
    const scan = MealScanResult(
      mealName: 'Meal',
      totals: MealScanTotals(
        caloriesKcal: 500,
        proteinGrams: 30,
        carbsGrams: 50,
        fatGrams: 20,
      ),
      items: [
        MealScanItem(
          name: 'Chicken',
          quantity: 200,
          unit: 'g',
          grams: null,
          caloriesKcal: 330,
          proteinGrams: 60,
          carbsGrams: 0,
          fatGrams: 7,
        ),
        MealScanItem(
          name: 'Cucumber',
          quantity: 4,
          unit: 'slices',
          grams: 40,
          caloriesKcal: 8,
          proteinGrams: 0,
          carbsGrams: 2,
          fatGrams: 0,
        ),
        MealScanItem(
          name: 'Mystery',
          quantity: null,
          unit: null,
          grams: null,
          caloriesKcal: null,
          proteinGrams: null,
          carbsGrams: null,
          fatGrams: null,
        ),
      ],
      confidence: 0.5,
      assumptions: [],
      warnings: [],
      debug: MealScanDebug(model: '', latencyMs: 0),
    );

    final entries = mealScanResultToPlateEntries(
      scan: scan,
      date: DateTime(2026, 1, 1),
      loggedAt: DateTime(2026, 1, 1, 12),
      idFactory: (i) => 'id-$i',
    );

    expect(entries, hasLength(3));

    expect(entries[0].id, 'id-0');
    expect(entries[0].foodName, 'Chicken');
    expect(entries[0].servingGrams, 200);
    expect(entries[0].portionLabel, '200g');
    expect(entries[0].calories, 330);

    expect(entries[1].id, 'id-1');
    expect(entries[1].foodName, 'Cucumber');
    expect(entries[1].servingGrams, 40);
    expect(entries[1].portionLabel, '4 slices');

    expect(entries[2].id, 'id-2');
    expect(entries[2].foodName, 'Mystery');
    expect(entries[2].servingGrams, 1);
    expect(entries[2].portionLabel, isNull);
    expect(entries[2].calories, 0);
    expect(entries[2].proteinGrams, 0);
    expect(entries[2].carbsGrams, 0);
    expect(entries[2].fatGrams, 0);
  });

  test(
    'does not attach a Food for a db-matched item and keeps absolute macros',
    () {
      const scan = MealScanResult(
        mealName: 'Meal',
        totals: MealScanTotals(
          caloriesKcal: 330,
          proteinGrams: 60,
          carbsGrams: 0,
          fatGrams: 7,
        ),
        items: [
          MealScanItem(
            name: 'Grilled chicken',
            quantity: 200,
            unit: 'g',
            grams: 200,
            caloriesKcal: 330,
            proteinGrams: 60,
            carbsGrams: 0,
            fatGrams: 7,
            foodId: 'a3f1c2d4-1111-2222-3333-444455556666',
            matchedName: 'Chicken breast, grilled',
            matchedSource: 'fdc',
            matchedTrustTier: 'verified',
            matchConfidence: 0.9,
            macroSource: 'db',
          ),
        ],
        confidence: 0.9,
        assumptions: [],
        warnings: [],
        debug: MealScanDebug(model: '', latencyMs: 0),
      );

      final entries = mealScanResultToPlateEntries(
        scan: scan,
        date: DateTime(2026, 1, 1),
        loggedAt: DateTime(2026, 1, 1, 12),
        idFactory: (i) => 'id-$i',
      );

      expect(entries, hasLength(1));
      // No Food is attached, so the edit sheet treats it as a free-form entry
      // and never rescales its macros from a null per-100g Food.
      expect(entries[0].food, isNull);
      // The backend's absolute macros remain on the entry untouched.
      expect(entries[0].calories, 330);
      expect(entries[0].proteinGrams, 60);
      expect(entries[0].carbsGrams, 0);
      expect(entries[0].fatGrams, 7);
    },
  );

  test(
    'logged serving uses the authoritative grams, not a diverging quantity',
    () {
      // Regression: the backend scales macros to the resolved `grams` (200) but
      // may carry a stale Gemini `quantity` (100 g). The diary must log 200 g —
      // matching the displayed weight + the macros — not 100 g.
      const scan = MealScanResult(
        mealName: 'Meal',
        totals: MealScanTotals(
          caloriesKcal: 330,
          proteinGrams: 60,
          carbsGrams: 0,
          fatGrams: 7,
        ),
        items: [
          MealScanItem(
            name: 'Hainanese chicken',
            quantity: 100,
            unit: 'g',
            grams: 200,
            caloriesKcal: 330,
            proteinGrams: 60,
            carbsGrams: 0,
            fatGrams: 7,
          ),
        ],
        confidence: 0.6,
        assumptions: [],
        warnings: [],
        debug: MealScanDebug(model: '', latencyMs: 0),
      );

      final entries = mealScanResultToPlateEntries(
        scan: scan,
        date: DateTime(2026, 1, 1),
        loggedAt: DateTime(2026, 1, 1, 12),
        idFactory: (i) => 'id-$i',
      );

      expect(entries[0].servingGrams, 200);
      expect(entries[0].portionLabel, '200g');
    },
  );
}
