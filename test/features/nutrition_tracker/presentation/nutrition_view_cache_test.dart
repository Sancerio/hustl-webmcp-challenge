import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/nutrition_view_cache.dart';

void main() {
  final cache = NutritionViewCache.instance;
  setUp(cache.clear);

  group('NutritionViewCache', () {
    test('stores and returns a typed value', () {
      cache.set('insights:14', {'averages': {}});
      expect(cache.get<Map<String, dynamic>>('insights:14'), {'averages': {}});
    });

    test('returns null for a missing key (first load → skeleton)', () {
      expect(cache.get<Map<String, dynamic>>('insights:30'), isNull);
    });

    test('keys are independent', () {
      cache.set('weight:30', {'scale': []});
      expect(cache.get<Map<String, dynamic>>('insights:14'), isNull);
      expect(cache.get<Map<String, dynamic>>('weight:30'), {'scale': []});
    });

    test('clear drops everything (diary-change invalidation)', () {
      cache.set('insights:14', {'a': 1});
      cache.set('weight:30', {'b': 2});
      cache.clear();
      expect(cache.get<Map<String, dynamic>>('insights:14'), isNull);
      expect(cache.get<Map<String, dynamic>>('weight:30'), isNull);
    });
  });
}
