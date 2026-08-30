import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/services/nutrition_label_parser.dart';

void main() {
  test('parses basic Nutrition Facts panel (per serving)', () {
    const text = '''
My Cereal
Nutrition Facts
Serving size 1 cup (228g)
Calories 260
Total Fat 12g
Total Carbohydrate 31g
Protein 5g
''';

    final parsed = parseNutritionLabelText(text);
    expect(parsed.valuesPer100g, isFalse);
    expect(parsed.servingSizeGrams, closeTo(228, 0.01));
    expect(parsed.caloriesKcal, closeTo(260, 0.01));
    expect(parsed.fatGrams, closeTo(12, 0.01));
    expect(parsed.carbsGrams, closeTo(31, 0.01));
    expect(parsed.proteinGrams, closeTo(5, 0.01));
  });

  test('detects per 100g labels', () {
    const text = '''
Nutrition Information
Per 100 g
Energy 450 kcal
Fat 20g
Carbohydrate 50g
Protein 10g
''';

    final parsed = parseNutritionLabelText(text);
    expect(parsed.valuesPer100g, isTrue);
    expect(parsed.servingSizeGrams, isNull);
    expect(parsed.caloriesKcal, closeTo(450, 0.01));
    expect(parsed.fatGrams, closeTo(20, 0.01));
    expect(parsed.carbsGrams, closeTo(50, 0.01));
    expect(parsed.proteinGrams, closeTo(10, 0.01));
  });

  test('computes calories fallback from macros when missing', () {
    const text = '''
Protein 10g
Carbohydrate 20g
Total Fat 5g
''';

    final parsed = parseNutritionLabelText(text);
    expect(parsed.caloriesKcal, closeTo(165, 0.01));
    expect(parsed.proteinGrams, closeTo(10, 0.01));
    expect(parsed.carbsGrams, closeTo(20, 0.01));
    expect(parsed.fatGrams, closeTo(5, 0.01));
  });

  test('parses comma decimals and ignores fiber/sugar for carbs', () {
    const text = '''
Nutrition Facts
Calories 150
Total Carbohydrate 30g
Dietary Fiber 10g
Total Sugars 5g
Protein 7,5g
Fat 2,5g
''';

    final parsed = parseNutritionLabelText(text);
    expect(parsed.caloriesKcal, closeTo(150, 0.01));
    expect(parsed.carbsGrams, closeTo(30, 0.01));
    expect(parsed.proteinGrams, closeTo(7.5, 0.01));
    expect(parsed.fatGrams, closeTo(2.5, 0.01));
  });
}
