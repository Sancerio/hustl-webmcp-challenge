import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/exercise_library/data/datasources/exercise_cache_local_datasource.dart';
import 'package:hustl_app/features/exercise_library/data/datasources/exercise_custom_api.dart';
import 'package:hustl_app/features/exercise_library/data/datasources/hustl_backend_exercise_api.dart';
import 'package:hustl_app/features/exercise_library/data/repositories/exercise_repository_impl.dart';
import 'package:hustl_app/features/exercise_library/data/datasources/exercise_seed_datasource.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/exercise_library/data/datasources/custom_exercise_local_datasource.dart';
import 'package:hustl_app/core/services/token_storage.dart';

class _FakeBackend extends HustlBackendExerciseApi {
  final List<Exercise> toReturn;
  _FakeBackend(this.toReturn);

  @override
  Future<List<Exercise>> listExercises({
    int limit = 500,
    int offset = 0,
    String? search,
    String? muscle,
  }) async {
    return toReturn;
  }
}

class _MemoryCache implements ExerciseCacheDataSource {
  List<Exercise>? store;
  int saveCalls = 0;
  DateTime? lastUpdated;
  _MemoryCache([this.store]);

  @override
  Future<List<Exercise>?> getAll() async => store;

  @override
  Future<void> saveAll(List<Exercise> items) async {
    saveCalls++;
    store = items;
    lastUpdated = DateTime.now();
  }

  @override
  Future<DateTime?> getLastUpdated() async => lastUpdated;
}

Exercise ex(String name) => Exercise(name: name, muscles: const ['Chest']);

class _FakeCustom implements CustomExerciseDataSource {
  List<Exercise> items = const [];
  @override
  Future<void> add(Exercise exercise) async {
    items = [...items, exercise];
  }

  @override
  Future<List<Exercise>> getAll() async => items;

  @override
  Future<void> setAll(List<Exercise> exercises) async {
    items = [...exercises];
  }

  @override
  Future<void> removeById(String id) async {
    items = items.where((e) => e.id != id).toList();
  }

  @override
  Future<void> removeByNameCaseInsensitive(String name) async {
    final n = name.toLowerCase();
    items = items.where((e) => e.name.toLowerCase() != n).toList();
  }
}

class _TokenStorageFake extends TokenStorage {
  @override
  Future<String?> getAccessToken() async => 'access-token';
}

class _CustomApiFake extends ExerciseCustomApi {
  _CustomApiFake({this.saved, this.error});

  final Exercise? saved;
  final Object? error;
  int createCalls = 0;

  @override
  Future<Exercise> createOrUpdate({
    required String accessToken,
    required Map<String, dynamic> payload,
  }) async {
    createCalls += 1;
    final failure = error;
    if (failure != null) throw failure;
    return saved!;
  }
}

class _FailingNormalizedAddCustom extends _FakeCustom {
  int addCalls = 0;
  final List<String> removedIds = [];

  @override
  Future<void> add(Exercise exercise) async {
    addCalls += 1;
    if (addCalls == 2) {
      throw const CustomExercisePersistenceException(
        CustomExerciseWriteOperation.add,
      );
    }
    await super.add(exercise);
  }

  @override
  Future<void> removeById(String id) async {
    removedIds.add(id);
    await super.removeById(id);
  }
}

void main() {
  test(
    'returns cached when available and triggers background refresh',
    () async {
      final cached = [ex('Cached Bench'), ex('Cached Row')];
      final remote = [ex('Remote Bench'), ex('Remote Curl')];
      final repo = ExerciseRepositoryImpl(
        backendApi: _FakeBackend(remote),
        cache: _MemoryCache(cached),
        custom: _FakeCustom(),
      );

      final result = await repo.getAllExercises();
      expect(result, cached);
    },
  );

  test('returns builtin when no cache', () async {
    final seedList = [ex('Seed A'), ex('Seed B')];
    final repo = ExerciseRepositoryImpl(
      backendApi: _FakeBackend([ex('A'), ex('B')]),
      cache: _MemoryCache(null),
      seed: _FakeSeed(seedList),
      custom: _FakeCustom(),
    );

    final result = await repo.getAllExercises();
    expect(result, seedList);
  });

  test('filters by muscle locally', () async {
    final cache = _MemoryCache([
      const Exercise(name: 'Flat Bench', muscles: ['Chest']),
      const Exercise(name: 'Lat Pulldown', muscles: ['Back']),
    ]);
    final repo = ExerciseRepositoryImpl(
      backendApi: _FakeBackend(const []),
      cache: cache,
      seed: const _FakeSeed([]),
      custom: _FakeCustom(),
    );
    final chest = await repo.getExercisesByMuscle('chest');
    expect(chest.length, 1);
    expect(chest.first.name, 'Flat Bench');
  });

  test('remove by id does not remove others with same name', () async {
    final custom = _FakeCustom()
      ..items = [
        const Exercise(id: 'custom-1', name: 'Same', muscles: ['Chest']),
        const Exercise(id: 'custom-2', name: 'Same', muscles: ['Chest']),
      ];
    final repo = ExerciseRepositoryImpl(
      backendApi: _FakeBackend(const []),
      cache: _MemoryCache(const []),
      seed: const _FakeSeed([]),
      custom: custom,
    );
    await repo.removeCustomExercise(
      const Exercise(id: 'custom-1', name: 'Same', muscles: ['Chest']),
    );
    expect(custom.items.map((e) => e.id).toList(), ['custom-2']);
  });

  test('remove legacy (no id) removes by name', () async {
    final custom = _FakeCustom()
      ..items = [
        const Exercise(name: 'Legacy', muscles: ['Chest']),
        const Exercise(id: 'custom-3', name: 'Other', muscles: ['Chest']),
      ];
    final repo = ExerciseRepositoryImpl(
      backendApi: _FakeBackend(const []),
      cache: _MemoryCache(const []),
      seed: const _FakeSeed([]),
      custom: custom,
    );
    await repo.removeCustomExercise(
      const Exercise(name: 'Legacy', muscles: ['Chest']),
    );
    expect(custom.items.any((e) => e.name == 'Legacy'), isFalse);
    expect(custom.items.any((e) => e.id == 'custom-3'), isTrue);
  });

  test(
    'server-normalized local persistence failure reaches the caller',
    () async {
      const local = Exercise(
        id: 'custom-temporary',
        name: 'Cable Press',
        muscles: ['Chest'],
      );
      const normalized = Exercise(
        id: '11111111-1111-4111-8111-111111111111',
        name: 'Cable Press',
        muscles: ['Chest'],
        visibility: ExerciseVisibility.private,
      );
      final custom = _FailingNormalizedAddCustom();
      final api = _CustomApiFake(saved: normalized);
      final repo = ExerciseRepositoryImpl(
        customApi: api,
        custom: custom,
        tokens: _TokenStorageFake(),
      );

      await expectLater(
        repo.addCustomExercise(local),
        throwsA(
          isA<CustomExercisePersistenceException>().having(
            (error) => error.operation,
            'operation',
            CustomExerciseWriteOperation.add,
          ),
        ),
      );

      expect(api.createCalls, 1);
      expect(custom.addCalls, 2);
      expect(custom.removedIds, ['custom-temporary']);
      expect(
        custom.items,
        isEmpty,
        reason: 'the caller must be told when normalization lost local data',
      );
    },
  );

  test(
    'remote custom save failure keeps the successful local fallback',
    () async {
      const local = Exercise(
        id: 'custom-temporary',
        name: 'Cable Press',
        muscles: ['Chest'],
      );
      final custom = _FakeCustom();
      final api = _CustomApiFake(error: Exception('offline'));
      final repo = ExerciseRepositoryImpl(
        customApi: api,
        custom: custom,
        tokens: _TokenStorageFake(),
      );

      final result = await repo.addCustomExercise(local);

      expect(result, same(local));
      expect(api.createCalls, 2);
      expect(custom.items, [same(local)]);
    },
  );
}

class _FakeSeed implements ExerciseSeedDataSource {
  final List<Exercise> items;
  const _FakeSeed(this.items);
  @override
  Future<List<Exercise>> loadSeed() async => items;
}
