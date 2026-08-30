import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/utils/go_to_ranking.dart';

FoodLogEntry _e(String food, {required int hour, int day = 0}) => FoodLogEntry(
  id: '$food-$hour-$day',
  date: DateTime(2026, 1, 23),
  loggedAt: DateTime(2026, 1, 23 - day, hour),
  servingGrams: 100,
  calories: 100,
  proteinGrams: 5,
  carbsGrams: 10,
  fatGrams: 2,
  foodName: food,
  source: 'self',
);

void main() {
  group('goToEntries', () {
    test('hour proximity boosts a food usually logged around now', () {
      // Coffee at 8am x3, Beer at 8pm x3. At 8am, Coffee should win.
      final entries = [
        _e('Coffee', hour: 8),
        _e('Coffee', hour: 8, day: 1),
        _e('Coffee', hour: 8, day: 2),
        _e('Beer', hour: 20),
        _e('Beer', hour: 20, day: 1),
        _e('Beer', hour: 20, day: 2),
      ];
      expect(goToEntries(entries, 8).first.foodName, 'Coffee');
      // ...and at 8pm the order flips.
      expect(goToEntries(entries, 20).first.foodName, 'Beer');
    });

    test('frequency wins when the hour is equal', () {
      final entries = [
        _e('Oats', hour: 8),
        _e('Oats', hour: 8, day: 1),
        _e('Oats', hour: 8, day: 2),
        _e('Eggs', hour: 8),
        _e('Eggs', hour: 8, day: 1),
      ];
      expect(goToEntries(entries, 8).first.foodName, 'Oats');
    });

    test('a one-off (logged once) is never a go-to', () {
      final entries = [
        _e('Cake', hour: 8),
        _e('Oats', hour: 8),
        _e('Oats', hour: 8, day: 1),
      ];
      final names = goToEntries(entries, 8).map((e) => e.foodName);
      expect(names, contains('Oats'));
      expect(names, isNot(contains('Cake')));
    });

    test('thin history returns empty (so the UI falls back to recents)', () {
      expect(goToEntries([_e('Apple', hour: 8)], 8), isEmpty);
      expect(goToEntries(const [], 8), isEmpty);
    });

    test('keeps the most-recent entry as the re-log representative', () {
      final entries = [_e('Tea', hour: 8), _e('Tea', hour: 8, day: 1)];
      expect(goToEntries(entries, 8).first.id, 'Tea-8-0');
    });
  });
}
