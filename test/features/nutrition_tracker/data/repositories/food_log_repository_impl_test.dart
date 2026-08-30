import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/services/token_storage.dart';
import 'package:hustl_app/features/nutrition_tracker/data/datasources/hustl_backend_nutrition_api.dart';
import 'package:hustl_app/features/nutrition_tracker/data/repositories/food_log_repository_impl.dart';
import 'package:hustl_app/features/nutrition_tracker/data/services/offline_food_log_queue.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/utils/go_to_ranking.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configurable fake that records the order of calls so a test can assert the
/// pending-create flush (`addFoodLogs`) runs before the suggestions fetch
/// (`getFoodSuggestions`). Each method can be told to throw to simulate offline.
class _FakeApi extends HustlBackendNutritionApi {
  _FakeApi({
    this.suggestionsResult = const {},
    this.suggestionsThrows = false,
    this.addThrows = false,
    this.listThrows = false,
  }) : super(tokens: TokenStorage());

  final Map<String, List<Map<String, dynamic>>> suggestionsResult;
  bool suggestionsThrows;
  bool addThrows;
  bool listThrows;

  final List<String> calls = [];

  @override
  Future<List<Map<String, dynamic>>> listFoodLogs(DateTime date) async {
    calls.add('listFoodLogs');
    if (listThrows) {
      throw HustlBackendNutritionApiException(
        statusCode: 503,
        code: 'food_logs_failed',
        message: 'Couldn’t load your food log. Please try again.',
      );
    }
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> addFoodLogs(
    List<Map<String, dynamic>> payloads,
  ) async {
    calls.add('addFoodLogs');
    if (addThrows) {
      throw HustlBackendNutritionApiException(
        statusCode: 503,
        code: 'food_logs_insert_failed',
        message: 'Couldn’t save your food log. Please try again.',
      );
    }
    // Echo the payloads back as if the server stored them (each gets an id).
    return [
      for (var i = 0; i < payloads.length; i++)
        {
          'id': 'server-$i',
          'date': payloads[i]['date'],
          'logged_at': payloads[i]['loggedAt'],
          'serving_grams': payloads[i]['servingGrams'],
          'calories': payloads[i]['calories'],
          'protein_grams': payloads[i]['proteinGrams'],
          'carbs_grams': payloads[i]['carbsGrams'],
          'fat_grams': payloads[i]['fatGrams'],
          'food_name': payloads[i]['foodName'],
        },
    ];
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>> getFoodSuggestions({
    int tzOffsetMinutes = 0,
    int recentLimit = 12,
    int suggestionLimit = 4,
  }) async {
    calls.add('getFoodSuggestions');
    if (suggestionsThrows) {
      throw HustlBackendNutritionApiException(
        statusCode: 503,
        code: 'food_suggestions_failed',
        message: 'Couldn’t load suggestions. Please try again.',
      );
    }
    return suggestionsResult;
  }
}

FoodLogEntry _entry({
  required String id,
  required String foodName,
  required DateTime loggedAt,
  double calories = 100,
}) {
  return FoodLogEntry(
    id: id,
    date: DateTime(loggedAt.year, loggedAt.month, loggedAt.day),
    loggedAt: loggedAt,
    servingGrams: 100,
    calories: calories,
    proteinGrams: 10,
    carbsGrams: 10,
    fatGrams: 5,
    foodName: foodName,
  );
}

/// A pending entry for an on-device generic food: it carries a non-backend asset
/// id (e.g. `fdc-171705`) on its [Food], exactly like a logged catalog generic.
/// `toPayload()` sends such an id as `foodId: null`, so the backend groups the
/// synced row by normalized `food_name` — the case [backendCompatibleKey] must
/// match so the pending and server rows collapse to one.
FoodLogEntry _entryWithFood({
  required String id,
  required String foodId,
  required String foodName,
  required DateTime loggedAt,
}) {
  return FoodLogEntry(
    id: id,
    date: DateTime(loggedAt.year, loggedAt.month, loggedAt.day),
    loggedAt: loggedAt,
    servingGrams: 100,
    calories: 100,
    proteinGrams: 10,
    carbsGrams: 10,
    fatGrams: 5,
    foodName: foodName,
    food: Food(id: foodId, name: foodName),
  );
}

Map<String, dynamic> _snapshot(String foodName, DateTime loggedAt) => {
  'food_name': foodName,
  'serving_grams': 100,
  'calories': 100,
  'protein_grams': 10,
  'carbs_grams': 10,
  'fat_grams': 5,
  'logged_at': loggedAt.toUtc().toIso8601String(),
};

void main() {
  late OfflineFoodLogQueue queue;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    queue = OfflineFoodLogQueue();
  });

  group('getSuggestions offline correctness', () {
    test(
      'overlays a pending/offline create into Recent ahead of server recents',
      () async {
        // A food logged offline (queued, not yet synced) — the flush will fail
        // to reach the server, so it stays queued.
        await queue.enqueueCreate(
          _entry(
            id: 'temp-1',
            foodName: 'Greek Yogurt',
            loggedAt: DateTime.utc(2026, 6, 19, 8),
          ),
        );

        final api = _FakeApi(
          addThrows: true, // offline flush leaves the create queued
          suggestionsResult: {
            'suggestions': const [],
            'recents': [_snapshot('Oatmeal', DateTime.utc(2026, 6, 18, 8))],
          },
        );
        final repo = FoodLogRepositoryImpl(api: api, offlineQueue: queue);

        final result = await repo.getSuggestions(tzOffsetMinutes: 0);

        final names = result.recents.map((e) => e.foodName).toList();
        // The offline-logged food appears in Recent even though it hasn't
        // synced, ahead of the older server recent.
        expect(names, contains('Greek Yogurt'));
        expect(names, contains('Oatmeal'));
        expect(names.first, 'Greek Yogurt'); // most-recent-first
      },
    );

    test(
      'dedupes a pending create against the server recent by food key',
      () async {
        // Same food queued offline AND present in server recents: one row only.
        await queue.enqueueCreate(
          _entry(
            id: 'temp-1',
            foodName: 'Greek Yogurt',
            loggedAt: DateTime.utc(2026, 6, 19, 8),
          ),
        );

        final api = _FakeApi(
          addThrows: true,
          suggestionsResult: {
            'suggestions': const [],
            'recents': [
              _snapshot('greek yogurt', DateTime.utc(2026, 6, 17, 8)),
            ],
          },
        );
        final repo = FoodLogRepositoryImpl(api: api, offlineQueue: queue);

        final result = await repo.getSuggestions(tzOffsetMinutes: 0);

        final keys = result.recents.map(goToFoodKey).toList();
        expect(keys.where((k) => k == 'greek yogurt').length, 1);
      },
    );

    test('dedupes a pending LOCAL-GENERIC food (fdc-* id) against the server '
        'name-keyed recent into a single row', () async {
      // A generic on-device food (asset id `fdc-171705`) logged offline. Its
      // `toPayload()` sends `foodId: null`, so once synced the backend groups
      // it by normalized food_name — and its server recent is name-keyed too.
      // Keying the pending row by `fdc-171705` (as `goToFoodKey` would) would
      // NOT collapse against the name-keyed server row, showing it twice.
      await queue.enqueueCreate(
        _entryWithFood(
          id: 'temp-1',
          foodId: 'fdc-171705',
          foodName: 'Greek Yogurt',
          loggedAt: DateTime.utc(2026, 6, 19, 8),
        ),
      );

      final api = _FakeApi(
        addThrows: true, // stays queued (pending overlay path)
        suggestionsResult: {
          'suggestions': const [],
          // Server recent for the SAME food, keyed by name (food_id null).
          'recents': [_snapshot('greek yogurt', DateTime.utc(2026, 6, 17, 8))],
        },
      );
      final repo = FoodLogRepositoryImpl(api: api, offlineQueue: queue);

      final result = await repo.getSuggestions(tzOffsetMinutes: 0);

      // Exactly one Recent row for the food — pending + server collapse.
      final matching = result.recents
          .where(
            (e) => (e.foodName ?? '').toLowerCase().trim() == 'greek yogurt',
          )
          .toList();
      expect(matching.length, 1);
      expect(result.recents.length, 1);
      // The pending entry (most-recent) is the representative.
      expect(matching.first.food?.id, 'fdc-171705');
    });

    test(
      'falls back to local pending aggregation (not empty) when the API throws',
      () async {
        await queue.enqueueCreate(
          _entry(
            id: 'temp-1',
            foodName: 'Banana',
            loggedAt: DateTime.utc(2026, 6, 19, 7),
          ),
        );
        await queue.enqueueCreate(
          _entry(
            id: 'temp-2',
            foodName: 'Eggs',
            loggedAt: DateTime.utc(2026, 6, 19, 8),
          ),
        );

        final api = _FakeApi(addThrows: true, suggestionsThrows: true);
        final repo = FoodLogRepositoryImpl(api: api, offlineQueue: queue);

        final result = await repo.getSuggestions(tzOffsetMinutes: 0);

        // Suggested-for-now is a server ranking, so it's gracefully empty...
        expect(result.suggestions, isEmpty);
        // ...but Recent survives offline, rebuilt from the pending queue,
        // most-recent-first.
        final names = result.recents.map((e) => e.foodName).toList();
        expect(names, ['Eggs', 'Banana']);
      },
    );

    test('flushes pending creates before calling getFoodSuggestions', () async {
      await queue.enqueueCreate(
        _entry(
          id: 'temp-1',
          foodName: 'Greek Yogurt',
          loggedAt: DateTime.utc(2026, 6, 19, 8),
        ),
      );

      final api = _FakeApi(
        // addFoodLogs succeeds: the create syncs, so the queue is drained.
        suggestionsResult: {
          'suggestions': const [],
          'recents': [_snapshot('Greek Yogurt', DateTime.utc(2026, 6, 19, 8))],
        },
      );
      final repo = FoodLogRepositoryImpl(api: api, offlineQueue: queue);

      await repo.getSuggestions(tzOffsetMinutes: 0);

      // The flush (addFoodLogs) runs strictly before the suggestions fetch so
      // server-side recents already include the just-synced log.
      expect(api.calls, ['addFoodLogs', 'getFoodSuggestions']);
      // And the create was consumed by the successful flush.
      expect(await queue.loadOps(), isEmpty);
    });

    test(
      'returns empty Recent when nothing is logged and the API throws',
      () async {
        final api = _FakeApi(suggestionsThrows: true);
        final repo = FoodLogRepositoryImpl(api: api, offlineQueue: queue);

        final result = await repo.getSuggestions(tzOffsetMinutes: 0);

        expect(result.suggestions, isEmpty);
        expect(result.recents, isEmpty);
      },
    );
  });

  group('getLogsForDateReadOnly', () {
    test('overlays pending entries without flushing writes', () async {
      await queue.enqueueCreate(
        _entry(
          id: 'temp-1',
          foodName: 'Banana',
          loggedAt: DateTime.utc(2026, 8, 26, 8),
        ),
      );
      final api = _FakeApi();
      final repo = FoodLogRepositoryImpl(api: api, offlineQueue: queue);

      final result = await repo.getLogsForDateReadOnly(
        DateTime.utc(2026, 8, 26),
      );

      expect(result.single.foodName, 'Banana');
      expect(api.calls, ['listFoodLogs']);
      expect(await queue.loadOps(), hasLength(1));
    });

    test('propagates backend failures instead of fabricating an empty day', () {
      final repo = FoodLogRepositoryImpl(
        api: _FakeApi(listThrows: true),
        offlineQueue: queue,
      );

      expect(
        () => repo.getLogsForDateReadOnly(DateTime.utc(2026, 8, 26)),
        throwsA(isA<HustlBackendNutritionApiException>()),
      );
    });
  });
}
