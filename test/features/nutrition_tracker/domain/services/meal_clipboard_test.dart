import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/services/meal_clipboard.dart';

FoodLogEntry _entry(String id) => FoodLogEntry(
  id: id,
  date: DateTime(2026, 6, 16),
  loggedAt: DateTime(2026, 6, 16, 8),
  servingGrams: 100,
  calories: 200,
  proteinGrams: 20,
  carbsGrams: 10,
  fatGrams: 5,
  foodName: 'Food $id',
);

void main() {
  group('MealClipboard', () {
    test('starts empty', () {
      final clipboard = MealClipboard();
      expect(clipboard.hasContent, isFalse);
      expect(clipboard.entries, isEmpty);
      expect(clipboard.count, 0);
      expect(clipboard.sourceDate, isNull);
    });

    test('copy snapshots entries and the source date', () {
      final clipboard = MealClipboard();
      clipboard.copy([
        _entry('a'),
        _entry('b'),
      ], sourceDate: DateTime(2026, 6, 15, 13, 30));
      expect(clipboard.hasContent, isTrue);
      expect(clipboard.count, 2);
      expect(clipboard.entries.map((e) => e.id), ['a', 'b']);
      // Source date is normalized to day-only.
      expect(clipboard.sourceDate, DateTime(2026, 6, 15));
    });

    test('copy with an empty list leaves the clipboard empty', () {
      final clipboard = MealClipboard();
      clipboard.copy(const [], sourceDate: DateTime(2026, 6, 15));
      expect(clipboard.hasContent, isFalse);
      expect(clipboard.sourceDate, isNull);
    });

    test('clear empties a populated clipboard', () {
      final clipboard = MealClipboard()
        ..copy([_entry('a')], sourceDate: DateTime(2026, 6, 15));
      expect(clipboard.hasContent, isTrue);
      clipboard.clear();
      expect(clipboard.hasContent, isFalse);
      expect(clipboard.entries, isEmpty);
      expect(clipboard.sourceDate, isNull);
    });

    test('entries snapshot is detached from the caller list and immutable', () {
      final source = [_entry('a')];
      final clipboard = MealClipboard()..copy(source);
      source.add(_entry('b'));
      // Mutating the original list does not change the clipboard.
      expect(clipboard.count, 1);
      // The exposed list is unmodifiable.
      expect(() => clipboard.entries.add(_entry('c')), throwsUnsupportedError);
    });
  });
}
