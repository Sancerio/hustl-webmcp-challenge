import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/data/sources/local_food_index.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Small hardcoded sample (8 foods) mirroring the shape produced by
/// `tool/build_foods_index.dart` (`assets/data/foods_generic.json`). It packs a
/// few prefix families ("tom*", "oat*") plus a branded row so the FTS5 search
/// and `Food` mapping can be exercised end to end.
const _sampleAsset = '''
[
  {
    "id": "fdc-1",
    "name": "Tomato, red, ripe, raw",
    "caloriesPer100g": 18,
    "proteinGramsPer100g": 0.88,
    "carbsGramsPer100g": 3.89,
    "fatGramsPer100g": 0.2,
    "source": "fdc",
    "dataType": "SR Legacy"
  },
  {
    "id": "fdc-2",
    "name": "Cherry tomatoes",
    "brand": "Acme Farms",
    "caloriesPer100g": 18,
    "proteinGramsPer100g": 0.9,
    "carbsGramsPer100g": 3.9,
    "fatGramsPer100g": 0.2,
    "source": "fdc",
    "dataType": "Branded"
  },
  {
    "id": "fdc-3",
    "name": "Chicken breast, grilled",
    "caloriesPer100g": 165,
    "proteinGramsPer100g": 31,
    "carbsGramsPer100g": 0,
    "fatGramsPer100g": 3.6,
    "source": "fdc",
    "dataType": "SR Legacy"
  },
  {
    "id": "fdc-4",
    "name": "Oats, rolled, dry",
    "caloriesPer100g": 379,
    "proteinGramsPer100g": 13.2,
    "carbsGramsPer100g": 67.7,
    "fatGramsPer100g": 6.5,
    "source": "fdc",
    "dataType": "SR Legacy"
  },
  {
    "id": "fdc-5",
    "name": "Oatmeal, cooked",
    "caloriesPer100g": 71,
    "proteinGramsPer100g": 2.5,
    "carbsGramsPer100g": 12,
    "fatGramsPer100g": 1.5,
    "source": "fdc",
    "dataType": "Survey (FNDDS)"
  },
  {
    "id": "fdc-6",
    "name": "Oat milk, unsweetened",
    "caloriesPer100g": 43,
    "proteinGramsPer100g": 0.8,
    "carbsGramsPer100g": 6.7,
    "fatGramsPer100g": 1.3,
    "source": "fdc",
    "dataType": "Branded"
  },
  {
    "id": "fdc-7",
    "name": "Banana, raw",
    "caloriesPer100g": 89,
    "proteinGramsPer100g": 1.1,
    "carbsGramsPer100g": 22.8,
    "fatGramsPer100g": 0.3,
    "source": "fdc",
    "dataType": "SR Legacy"
  },
  {
    "id": "fdc-8",
    "name": "Tomato sauce, canned",
    "caloriesPer100g": 24,
    "proteinGramsPer100g": 1.2,
    "carbsGramsPer100g": 5.3,
    "fatGramsPer100g": 0.3,
    "source": "fdc",
    "dataType": "SR Legacy"
  }
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
    tempDir = await Directory.systemTemp.createTemp('local_food_index_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  LocalFoodIndex makeIndex({String? assetOverride, bool throwAsset = false}) {
    return LocalFoodIndex(
      databaseFactory: databaseFactoryFfi,
      dbDirectoryProvider: () async => tempDir.path,
      loadAsset: (_) async {
        if (throwAsset) throw const FileSystemException('missing');
        return assetOverride ?? _sampleAsset;
      },
    );
  }

  test('can be instantiated with defaults', () {
    expect(LocalFoodIndex(), isNotNull);
  });

  // (1) Build an FTS5 DB from an injected sample and confirm a prefix search
  // ("tom*") returns the expected name + brand matches.
  test(
    'builds FTS5 DB from injected sample and matches a "tom" prefix',
    () async {
      final index = makeIndex();
      final results = await index.search('tom');
      final ids = results.map((f) => f.id).toSet();

      // "Tomato, red...", "Cherry tomatoes", and "Tomato sauce..." all match the
      // tom* prefix; non-tomato foods must not.
      expect(ids, containsAll(<String>{'fdc-1', 'fdc-2', 'fdc-8'}));
      expect(ids, isNot(contains('fdc-3'))); // chicken
      expect(ids, isNot(contains('fdc-7'))); // banana
      expect(results, isNotEmpty);
      await index.close();
    },
  );

  // (2) A short prefix ("oat") returns the whole oat family (oats, oatmeal,
  // oat milk) and nothing else.
  test('prefix search "oat" returns matching oat rows', () async {
    final index = makeIndex();
    final results = await index.search('oat');
    final ids = results.map((f) => f.id).toSet();

    expect(ids, containsAll(<String>{'fdc-4', 'fdc-5', 'fdc-6'}));
    expect(ids, isNot(contains('fdc-7'))); // banana
    expect(ids, isNot(contains('fdc-1'))); // tomato
    await index.close();
  });

  // (3) Empty, symbol-only, and bare-operator queries are safe: no crash, empty
  // list. The "*" case is important because it is a raw FTS5 prefix operator.
  test('empty and garbage queries are safe and return empty', () async {
    final index = makeIndex();
    expect(await index.search(''), isEmpty);
    expect(await index.search('   '), isEmpty);
    expect(await index.search(r'$@#$%'), isEmpty);
    expect(await index.search('*'), isEmpty);
    await index.close();
  });

  // (4) A missing/unreadable asset degrades to an empty list, never an
  // exception, so callers can fall back to the backend.
  test('missing asset returns empty list without crashing', () async {
    final index = makeIndex(throwAsset: true);
    expect(await index.search('oat'), isEmpty);
    expect(await index.search('tomato'), isEmpty);
    await index.close();
  });

  test('empty asset returns empty list without crashing', () async {
    final index = makeIndex(assetOverride: '');
    expect(await index.search('oat'), isEmpty);
    await index.close();
  });

  // (5) Each row maps to a Food with the correct id/name/brand/macros and a
  // 'verified' trust tier.
  test('result maps to Food objects with verified trust tier', () async {
    final index = makeIndex();
    final results = await index.search('cherry');
    expect(results, hasLength(1));
    final food = results.first;
    expect(food.id, 'fdc-2');
    expect(food.name, 'Cherry tomatoes');
    expect(food.brand, 'Acme Farms');
    expect(food.source, 'fdc');
    expect(food.caloriesPer100g, 18);
    expect(food.proteinPer100g, 0.9);
    expect(food.carbsPer100g, 3.9);
    expect(food.fatPer100g, 0.2);
    expect(food.trustTier, 'verified');
    await index.close();
  });

  test('a food without a brand maps to a null brand', () async {
    final index = makeIndex();
    final results = await index.search('chicken');
    expect(results.single.brand, isNull);
    expect(results.single.trustTier, 'verified');
    await index.close();
  });

  test('search respects the limit argument', () async {
    final index = makeIndex();
    final results = await index.search('oat', limit: 2);
    expect(results, hasLength(2));
    await index.close();
  });

  // Persistence: the DB builds once (hash recorded) and is reused on the next
  // launch with an identical asset.
  test('builds DB once and reuses it on next launch (hash check)', () async {
    final dbFile = File('${tempDir.path}/foods_fts5.db');

    final first = makeIndex();
    await first.search('tomato');
    await first.close();
    expect(dbFile.existsSync(), isTrue);
    final modifiedFirst = dbFile.lastModifiedSync();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('foods_index_asset_hash'), isNotNull);

    final second = makeIndex();
    final results = await second.search('tomato');
    expect(results, isNotEmpty);
    await second.close();
    expect(dbFile.lastModifiedSync(), modifiedFirst);
  });

  // When the bundled asset changes, the index rebuilds and old rows disappear.
  test('rebuilds when bundled asset hash changes', () async {
    final first = makeIndex();
    await first.search('tomato');
    await first.close();

    const changedAsset = '''
    [
      {
        "id": "fdc-99",
        "name": "Strawberry, raw",
        "caloriesPer100g": 32,
        "proteinGramsPer100g": 0.7,
        "carbsGramsPer100g": 7.7,
        "fatGramsPer100g": 0.3,
        "source": "fdc",
        "dataType": "SR Legacy"
      }
    ]
    ''';

    final second = makeIndex(assetOverride: changedAsset);
    final strawberry = await second.search('straw');
    expect(strawberry.single.id, 'fdc-99');
    // Old data is gone after the rebuild.
    expect(await second.search('tomato'), isEmpty);
    await second.close();
  });
}
