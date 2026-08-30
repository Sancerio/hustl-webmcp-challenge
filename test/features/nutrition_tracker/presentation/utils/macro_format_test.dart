import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/utils/macro_format.dart';

void main() {
  group('formatMacros', () {
    test('renders P/F/C order, number-then-letter, dot-separated, no cal', () {
      expect(formatMacros(protein: 30, fat: 10, carbs: 42), '30P · 10F · 42C');
    });

    test('prefixes "NNN Cal · " when calories provided', () {
      expect(
        formatMacros(protein: 30, fat: 10, carbs: 42, calories: 380),
        '380 Cal · 30P · 10F · 42C',
      );
    });

    test('rounds each value to a whole number', () {
      expect(
        formatMacros(protein: 30.4, fat: 9.6, carbs: 41.5, calories: 379.9),
        '380 Cal · 30P · 10F · 42C',
      );
    });

    test('omits null macros instead of rendering them as 0', () {
      // A partial AI estimate (unsure of fat) must not read as 0F.
      expect(
        formatMacros(protein: 30, fat: null, carbs: 42, calories: 380),
        '380 Cal · 30P · 42C',
      );
      expect(formatMacros(protein: null, fat: null, carbs: null), '');
    });
  });
}
