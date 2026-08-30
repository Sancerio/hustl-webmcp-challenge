import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/build_foods_index.dart';

/// A tiny USDA FoodData Central JSON snippet covering the transform's branches:
///   - Foundation row with full macros  -> kept
///   - SR Legacy row with full macros    -> kept
///   - Survey (FNDDS) row with full macros -> kept
///   - Branded row (out of scope)        -> dropped
///   - Foundation row missing carbs      -> dropped
const String _sampleUsdaJson = '''
{
  "FoundationFoods": [
    {
      "fdcId": 171705,
      "description": "Egg, whole, raw, fresh",
      "dataType": "Foundation",
      "foodNutrients": [
        {"nutrient": {"number": "208"}, "amount": 143},
        {"nutrient": {"number": "203"}, "amount": 12.6},
        {"nutrient": {"number": "205"}, "amount": 0.72},
        {"nutrient": {"number": "204"}, "amount": 9.51}
      ]
    },
    {
      "fdcId": 999001,
      "description": "Mystery powder, missing carbs",
      "dataType": "Foundation",
      "foodNutrients": [
        {"nutrient": {"number": "208"}, "amount": 200},
        {"nutrient": {"number": "203"}, "amount": 10},
        {"nutrient": {"number": "204"}, "amount": 5}
      ]
    }
  ],
  "SRLegacyFoods": [
    {
      "fdcId": 173410,
      "description": "Chicken breast, cooked",
      "dataType": "SR Legacy",
      "foodNutrients": [
        {"nutrient": {"number": "1008"}, "amount": 165},
        {"nutrient": {"number": "1003"}, "amount": 31},
        {"nutrient": {"number": "1005"}, "amount": 0},
        {"nutrient": {"number": "1004"}, "amount": 3.6}
      ]
    }
  ],
  "SurveyFoods": [
    {
      "fdcId": 200001,
      "description": "Rice, white, cooked",
      "dataType": "Survey (FNDDS)",
      "foodNutrients": [
        {"nutrientNumber": "208", "amount": 130},
        {"nutrientNumber": "203", "amount": 2.69},
        {"nutrientNumber": "205", "amount": 28.17},
        {"nutrientNumber": "204", "amount": 0.28}
      ]
    }
  ],
  "BrandedFoods": [
    {
      "fdcId": 555555,
      "description": "Super Crunch Cereal",
      "dataType": "Branded",
      "foodNutrients": [
        {"nutrient": {"number": "208"}, "amount": 380},
        {"nutrient": {"number": "203"}, "amount": 7},
        {"nutrient": {"number": "205"}, "amount": 80},
        {"nutrient": {"number": "204"}, "amount": 4}
      ]
    }
  ]
}
''';

/// Extracts every food object from the sample regardless of wrapper key, so the
/// test exercises [transformUsdaExport] against a realistic mixed input list
/// (Foundation + SR Legacy + Survey + Branded + an incomplete row).
List<Map> _allFoodsFromSample() {
  final decoded = jsonDecode(_sampleUsdaJson) as Map<String, dynamic>;
  final foods = <Map>[];
  for (final value in decoded.values) {
    if (value is List) {
      foods.addAll(value.whereType<Map>());
    }
  }
  return foods;
}

void main() {
  group('transformUsdaExport', () {
    test('keeps Foundation / SR Legacy / Survey rows, drops Branded', () {
      final result = transformUsdaExport(_allFoodsFromSample());

      final names = result.map((r) => r['name']).toList();
      expect(names, contains('Egg, whole, raw, fresh')); // Foundation
      expect(names, contains('Chicken breast, cooked')); // SR Legacy
      expect(names, contains('Rice, white, cooked')); // Survey (FNDDS)

      // Branded is out of scope and must never appear.
      expect(names, isNot(contains('Super Crunch Cereal')));
      expect(
        result.any((r) => r['dataType'] == 'Branded'),
        isFalse,
        reason: 'Branded rows must be filtered out',
      );
    });

    test('drops rows missing one or more core macros', () {
      final result = transformUsdaExport(_allFoodsFromSample());

      // The "Mystery powder" row has no carbohydrate nutrient -> dropped.
      expect(
        result.any((r) => r['name'] == 'Mystery powder, missing carbs'),
        isFalse,
      );

      // 5 input foods, 2 excluded (1 Branded, 1 missing-macro) -> 3 kept.
      expect(result, hasLength(3));
    });

    test('emits the expected compact output shape per row', () {
      final result = transformUsdaExport(_allFoodsFromSample());
      final egg = result.firstWhere(
        (r) => r['name'] == 'Egg, whole, raw, fresh',
      );

      expect(egg['id'], 'fdc-171705');
      expect(egg['name'], 'Egg, whole, raw, fresh');
      expect(egg['caloriesPer100g'], 143);
      expect(egg['proteinGramsPer100g'], 12.6);
      expect(egg['carbsGramsPer100g'], 0.72);
      expect(egg['fatGramsPer100g'], 9.51);
      expect(egg['source'], 'fdc');
      expect(egg['dataType'], 'Foundation');

      // Whole values are emitted as ints; fractional values stay double.
      expect(egg['caloriesPer100g'], isA<int>());
      expect(egg['proteinGramsPer100g'], isA<double>());

      // Generic-only: no brand/barcode fields leak through.
      expect(egg.containsKey('barcode'), isFalse);
      expect(egg.containsKey('brand'), isFalse);
    });

    test('reads energy from either FDC number 208 or 1008', () {
      final result = transformUsdaExport(_allFoodsFromSample());
      final chicken = result.firstWhere(
        (r) => r['name'] == 'Chicken breast, cooked',
      );
      expect(chicken['caloriesPer100g'], 165); // came from number "1008"

      final rice = result.firstWhere((r) => r['name'] == 'Rice, white, cooked');
      // Survey row uses the flat `nutrientNumber` shape.
      expect(rice['caloriesPer100g'], 130);
      expect(rice['carbsGramsPer100g'], 28.17);
    });

    test('produces output that round-trips through valid JSON', () {
      final result = transformUsdaExport(_allFoodsFromSample());

      final encoded = jsonEncode(result);
      final reparsed = jsonDecode(encoded);

      expect(reparsed, isA<List>());
      expect(reparsed as List, hasLength(3));
      for (final row in reparsed) {
        expect(row, isA<Map>());
        expect(
          (row as Map).keys,
          containsAll(<String>['id', 'name', 'source']),
        );
      }
    });

    test('returns an empty list when no rows qualify', () {
      // Only a Branded row -> nothing survives the dataType filter.
      final brandedOnly = <Map>[
        {
          'fdcId': 1,
          'description': 'Branded thing',
          'dataType': 'Branded',
          'foodNutrients': const [
            {
              'nutrient': {'number': '208'},
              'amount': 100,
            },
            {
              'nutrient': {'number': '203'},
              'amount': 1,
            },
            {
              'nutrient': {'number': '205'},
              'amount': 1,
            },
            {
              'nutrient': {'number': '204'},
              'amount': 1,
            },
          ],
        },
      ];
      expect(transformUsdaExport(brandedOnly), isEmpty);
    });
  });
}
