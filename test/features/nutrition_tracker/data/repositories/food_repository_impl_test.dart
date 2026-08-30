import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/services/token_storage.dart';
import 'package:hustl_app/features/nutrition_tracker/data/datasources/hustl_backend_nutrition_api.dart';
import 'package:hustl_app/features/nutrition_tracker/data/repositories/food_repository_impl.dart';
import 'package:hustl_app/features/nutrition_tracker/data/sources/local_food_index.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Generic (unbranded) tomato + a branded one that collides by name with a
/// backend row so we can assert backend wins on dedupe.
const _localAsset = '''
[
  {
    "id": "local-tomato",
    "name": "Tomato, raw",
    "caloriesPer100g": 18,
    "proteinGramsPer100g": 0.9,
    "carbsGramsPer100g": 3.9,
    "fatGramsPer100g": 0.2,
    "source": "fdc",
    "dataType": "SR Legacy"
  },
  {
    "id": "local-ketchup",
    "name": "Ketchup",
    "brand": "Heinz",
    "caloriesPer100g": 100,
    "proteinGramsPer100g": 1,
    "carbsGramsPer100g": 25,
    "fatGramsPer100g": 0,
    "source": "fdc",
    "dataType": "Branded"
  }
]
''';

class _FakeApi extends HustlBackendNutritionApi {
  _FakeApi(this.result) : super(tokens: TokenStorage());

  final FoodSearchApiResult result;
  int searchCalls = 0;

  @override
  Future<FoodSearchApiResult> searchFoodsResult(
    String query, {
    int limit = 20,
  }) async {
    searchCalls++;
    return result;
  }
}

/// Always throws from [searchFoodsResult] to simulate an offline/non-2xx
/// backend (mirrors `HustlBackendNutritionApi`, which throws on any failure).
class _ThrowingApi extends HustlBackendNutritionApi {
  _ThrowingApi() : super(tokens: TokenStorage());

  int searchCalls = 0;

  @override
  Future<FoodSearchApiResult> searchFoodsResult(
    String query, {
    int limit = 20,
  }) async {
    searchCalls++;
    throw HustlBackendNutritionApiException(
      statusCode: 503,
      code: 'food_search_failed',
      message: 'Couldn’t search foods. Please try again.',
    );
  }
}

/// Local asset packing a single prefix family ("apple*") so a broad prefix can
/// return many local rows — used to prove local generics don't starve backend.
const _manyLocalAsset = '''
[
  {"id": "local-apple-1", "name": "Apple, raw", "source": "fdc", "dataType": "SR Legacy"},
  {"id": "local-apple-2", "name": "Apple juice", "source": "fdc", "dataType": "SR Legacy"},
  {"id": "local-apple-3", "name": "Apple sauce", "source": "fdc", "dataType": "SR Legacy"},
  {"id": "local-apple-4", "name": "Apple pie", "source": "fdc", "dataType": "SR Legacy"},
  {"id": "local-apple-5", "name": "Apple cider", "source": "fdc", "dataType": "SR Legacy"},
  {"id": "local-apple-6", "name": "Apple turnover", "source": "fdc", "dataType": "SR Legacy"},
  {"id": "local-apple-7", "name": "Apple crisp", "source": "fdc", "dataType": "SR Legacy"},
  {"id": "local-apple-8", "name": "Apple butter", "source": "fdc", "dataType": "SR Legacy"}
]
''';

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('food_repo_impl_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  LocalFoodIndex makeIndex() {
    return LocalFoodIndex(
      databaseFactory: databaseFactoryFfi,
      dbDirectoryProvider: () async => tempDir.path,
      loadAsset: (_) async => _localAsset,
    );
  }

  LocalFoodIndex makeIndexWithAsset(String asset) {
    return LocalFoodIndex(
      databaseFactory: databaseFactoryFfi,
      dbDirectoryProvider: () async => tempDir.path,
      loadAsset: (_) async => asset,
    );
  }

  FoodSearchApiResult backendResult(
    List<Map<String, dynamic>> items, {
    bool isStale = false,
    int? staleAgeMs,
  }) {
    return FoodSearchApiResult(
      items: items,
      isStale: isStale,
      staleAgeMs: staleAgeMs,
    );
  }

  group('searchFoodsResult without localFoodIndex (backend only)', () {
    test('returns backend foods and preserves stale flags', () async {
      final api = _FakeApi(
        backendResult(
          [
            {'id': 'backend-1', 'name': 'Ketchup', 'brand': 'Heinz'},
          ],
          isStale: true,
          staleAgeMs: 9000,
        ),
      );
      final repo = FoodRepositoryImpl(api: api);

      final result = await repo.searchFoodsResult('ketchup');

      expect(result.foods.map((f) => f.id), ['backend-1']);
      expect(result.isStale, isTrue);
      expect(result.staleAgeMs, 9000);
    });
  });

  group('searchFoodsResult with localFoodIndex (merge)', () {
    test('merges local generic with backend, local leads', () async {
      final api = _FakeApi(
        backendResult([
          {'id': 'backend-tuna', 'name': 'Tuna, canned', 'brand': 'StarKist'},
        ]),
      );
      final index = makeIndex();
      final repo = FoodRepositoryImpl(api: api, localFoodIndex: index);

      final result = await repo.searchFoodsResult('tomato');

      // Local "Tomato, raw" leads; backend row appended (no key collision).
      expect(result.foods.map((f) => f.id), ['local-tomato', 'backend-tuna']);
      await index.close();
    });

    test('dedupes by (name, brand) with backend winning', () async {
      final api = _FakeApi(
        backendResult([
          // Same (name, brand) as the local "Ketchup"/"Heinz" generic row.
          {
            'id': 'backend-ketchup',
            'name': 'Ketchup',
            'brand': 'Heinz',
            'trustTier': 'verified',
          },
        ]),
      );
      final index = makeIndex();
      final repo = FoodRepositoryImpl(api: api, localFoodIndex: index);

      final result = await repo.searchFoodsResult('ketchup');

      final ids = result.foods.map((f) => f.id).toList();
      expect(ids, contains('backend-ketchup'));
      expect(ids, isNot(contains('local-ketchup')));
      // Backend entry preserved its provenance.
      expect(
        result.foods.firstWhere((f) => f.id == 'backend-ketchup').trustTier,
        'verified',
      );
      await index.close();
    });

    test('preserves backend stale flags on merged result', () async {
      final api = _FakeApi(
        backendResult(
          [
            {'id': 'backend-x', 'name': 'Something else'},
          ],
          isStale: true,
          staleAgeMs: 12345,
        ),
      );
      final index = makeIndex();
      final repo = FoodRepositoryImpl(api: api, localFoodIndex: index);

      final result = await repo.searchFoodsResult('tomato');

      expect(result.isStale, isTrue);
      expect(result.staleAgeMs, 12345);
      await index.close();
    });

    test('falls back to backend-only when local returns empty', () async {
      final api = _FakeApi(
        backendResult([
          {'id': 'backend-only', 'name': 'Quinoa'},
        ]),
      );
      final index = makeIndex();
      final repo = FoodRepositoryImpl(api: api, localFoodIndex: index);

      // "quinoa" has no local match.
      final result = await repo.searchFoodsResult('quinoa');

      expect(result.foods.map((f) => f.id), ['backend-only']);
      await index.close();
    });

    test('queries both sources (backend is always hit)', () async {
      final api = _FakeApi(
        backendResult([
          {'id': 'backend-1', 'name': 'Tuna'},
        ]),
      );
      final index = makeIndex();
      final repo = FoodRepositoryImpl(api: api, localFoodIndex: index);

      await repo.searchFoodsResult('tomato');

      expect(api.searchCalls, 1);
      await index.close();
    });

    test('respects the limit on the merged set', () async {
      final api = _FakeApi(
        backendResult([
          {'id': 'b1', 'name': 'B One'},
          {'id': 'b2', 'name': 'B Two'},
          {'id': 'b3', 'name': 'B Three'},
        ]),
      );
      final index = makeIndex();
      final repo = FoodRepositoryImpl(api: api, localFoodIndex: index);

      final result = await repo.searchFoodsResult('tomato', limit: 2);

      expect(result.foods, hasLength(2));
      // Local generic leads.
      expect(result.foods.first.id, 'local-tomato');
      await index.close();
    });
  });

  group('searchFoodsResult offline-first (backend throws)', () {
    test(
      'backend throws + local has matches -> returns local, no throw',
      () async {
        final api = _ThrowingApi();
        final index = makeIndex();
        final repo = FoodRepositoryImpl(api: api, localFoodIndex: index);

        // "tomato" matches the local generic even though the backend errors.
        final result = await repo.searchFoodsResult('tomato');

        expect(api.searchCalls, 1);
        expect(result.foods.map((f) => f.id), ['local-tomato']);
        // Local results are fresh, not a stale backend cache.
        expect(result.isStale, isFalse);
        expect(result.staleAgeMs, isNull);
        await index.close();
      },
    );

    test('backend throws + local empty -> rethrows', () async {
      final api = _ThrowingApi();
      final index = makeIndex();
      final repo = FoodRepositoryImpl(api: api, localFoodIndex: index);

      // "quinoa" has no local match, so the backend error must surface.
      await expectLater(
        repo.searchFoodsResult('quinoa'),
        throwsA(isA<HustlBackendNutritionApiException>()),
      );
      await index.close();
    });
  });

  group('searchFoodsResult merge does not starve backend long-tail', () {
    test(
      'many local matches + backend rows + limit=N keeps backend rows',
      () async {
        // 8 local "apple*" rows would otherwise fill a small window entirely.
        final api = _FakeApi(
          backendResult([
            {
              'id': 'backend-apple-a',
              'name': 'Apple, branded A',
              'brand': 'Brand A',
            },
            {
              'id': 'backend-apple-b',
              'name': 'Apple, branded B',
              'brand': 'Brand B',
            },
          ]),
        );
        final index = makeIndexWithAsset(_manyLocalAsset);
        final repo = FoodRepositoryImpl(api: api, localFoodIndex: index);

        final result = await repo.searchFoodsResult('apple', limit: 4);
        final ids = result.foods.map((f) => f.id).toList();

        expect(result.foods, hasLength(4));
        // Local is capped at ceil(4/2)=2, so both backend rows survive.
        expect(ids, contains('backend-apple-a'));
        expect(ids, contains('backend-apple-b'));
        // Local generics still lead the list.
        expect(ids.first, startsWith('local-apple'));
        // And local did not monopolize the window.
        final localCount = ids
            .where((id) => id.startsWith('local-apple'))
            .length;
        expect(localCount, lessThanOrEqualTo(2));
        await index.close();
      },
    );
  });
}
