import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';

void main() {
  test('FoodLogEntry.toPayload sends consumedAt as UTC ISO string', () {
    final entry = FoodLogEntry(
      id: 'id-1',
      date: DateTime(2026, 1, 21),
      loggedAt: DateTime(2026, 1, 21, 8, 0, 0),
      servingGrams: 1,
      calories: 100,
      proteinGrams: 10,
      carbsGrams: 5,
      fatGrams: 2,
      foodName: 'Meal',
    );

    final payload = entry.toPayload();
    expect(payload['consumedAt'], entry.loggedAt.toUtc().toIso8601String());
    expect((payload['consumedAt'] as String).endsWith('Z'), isTrue);
  });

  group('isBackendFoodId', () {
    test('accepts a canonical UUID (case-insensitive)', () {
      expect(isBackendFoodId('123e4567-e89b-12d3-a456-426614174000'), isTrue);
      expect(isBackendFoodId('123E4567-E89B-12D3-A456-426614174000'), isTrue);
    });

    test('rejects on-device asset ids, empty, and null', () {
      expect(isBackendFoodId('fdc-171705'), isFalse);
      expect(isBackendFoodId(''), isFalse);
      expect(isBackendFoodId(null), isFalse);
    });

    test('rejects malformed UUID-like strings', () {
      // Wrong segment lengths / non-hex characters.
      expect(isBackendFoodId('123e4567-e89b-12d3-a456-42661417400'), isFalse);
      expect(
        isBackendFoodId('123e4567-e89b-12d3-a456-426614174000-extra'),
        isFalse,
      );
      expect(isBackendFoodId('zzze4567-e89b-12d3-a456-426614174000'), isFalse);
    });
  });

  group('FoodLogEntry.toPayload food reference', () {
    FoodLogEntry entryWith(Food food) => FoodLogEntry(
      id: 'id-1',
      date: DateTime(2026, 1, 21),
      loggedAt: DateTime(2026, 1, 21, 8, 0, 0),
      servingGrams: 100,
      calories: 100,
      proteinGrams: 10,
      carbsGrams: 5,
      fatGrams: 2,
      food: food,
    );

    test('local-id food logs by value: foodId null, snapshot present', () {
      final payload = entryWith(
        const Food(id: 'fdc-171705', name: 'Banana, raw'),
      ).toPayload();

      expect(payload['foodId'], isNull);
      // The snapshot still carries the food by value.
      expect(payload['foodName'], 'Banana, raw');
      expect(payload['calories'], 100);
      expect(payload['proteinGrams'], 10);
      expect(payload['servingGrams'], 100);
    });

    test('UUID food logs by reference: foodId set', () {
      const uuid = '123e4567-e89b-12d3-a456-426614174000';
      final payload = entryWith(
        const Food(id: uuid, name: 'Custom Shake'),
      ).toPayload();

      expect(payload['foodId'], uuid);
      expect(payload['foodName'], 'Custom Shake');
    });
  });
}
