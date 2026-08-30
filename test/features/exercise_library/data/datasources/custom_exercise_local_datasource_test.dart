import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/exercise_library/data/datasources/custom_exercise_local_datasource.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';

class _FakePreferencesStore implements CustomExercisePreferencesStore {
  _FakePreferencesStore({
    List<Exercise> initial = const [],
    this.succeeds = true,
  }) : _storedValue = initial.isEmpty
           ? null
           : jsonEncode(initial.map((exercise) => exercise.toMap()).toList());

  bool succeeds;
  String? _storedValue;
  int writeCount = 0;

  @override
  String? getString(String key) => _storedValue;

  @override
  Future<bool> setString(String key, String value) async {
    writeCount += 1;
    if (succeeds) {
      _storedValue = value;
    }
    return succeeds;
  }
}

CustomExerciseLocalDataSource _dataSource(_FakePreferencesStore store) {
  return CustomExerciseLocalDataSource(storeLoader: () async => store);
}

Matcher _throwsWriteFailure(CustomExerciseWriteOperation operation) {
  return throwsA(
    isA<CustomExercisePersistenceException>().having(
      (error) => error.operation,
      'operation',
      operation,
    ),
  );
}

void main() {
  const first = Exercise(
    id: 'custom-1',
    name: 'Cable Press',
    muscles: ['Chest'],
  );
  const second = Exercise(id: 'custom-2', name: 'Cable Row', muscles: ['Back']);

  group('failed writes', () {
    test(
      'add throws a typed persistence failure when setString is false',
      () async {
        final store = _FakePreferencesStore(
          initial: const [first],
          succeeds: false,
        );
        final dataSource = _dataSource(store);

        await expectLater(
          dataSource.add(second),
          _throwsWriteFailure(CustomExerciseWriteOperation.add),
        );

        expect(store.writeCount, 1);
        expect((await dataSource.getAll()).map((exercise) => exercise.id), [
          'custom-1',
        ]);
      },
    );

    test(
      'setAll throws a typed persistence failure when setString is false',
      () async {
        final store = _FakePreferencesStore(
          initial: const [first],
          succeeds: false,
        );
        final dataSource = _dataSource(store);

        await expectLater(
          dataSource.setAll(const [second]),
          _throwsWriteFailure(CustomExerciseWriteOperation.setAll),
        );

        expect(store.writeCount, 1);
        expect((await dataSource.getAll()).map((exercise) => exercise.id), [
          'custom-1',
        ]);
      },
    );

    test(
      'removeById throws a typed persistence failure when setString is false',
      () async {
        final store = _FakePreferencesStore(
          initial: const [first, second],
          succeeds: false,
        );
        final dataSource = _dataSource(store);

        await expectLater(
          dataSource.removeById('custom-1'),
          _throwsWriteFailure(CustomExerciseWriteOperation.removeById),
        );

        expect(store.writeCount, 1);
        expect((await dataSource.getAll()).map((exercise) => exercise.id), [
          'custom-1',
          'custom-2',
        ]);
      },
    );

    test(
      'legacy remove-by-name throws a typed persistence failure when setString is false',
      () async {
        final store = _FakePreferencesStore(
          initial: const [first, second],
          succeeds: false,
        );
        final dataSource = _dataSource(store);

        await expectLater(
          dataSource.removeByNameCaseInsensitive('CABLE PRESS'),
          _throwsWriteFailure(
            CustomExerciseWriteOperation.removeByNameCaseInsensitive,
          ),
        );

        expect(store.writeCount, 1);
        expect((await dataSource.getAll()).map((exercise) => exercise.id), [
          'custom-1',
          'custom-2',
        ]);
      },
    );
  });

  group('successful writes', () {
    test('add appends new ids and replaces an existing matching id', () async {
      final store = _FakePreferencesStore(initial: const [first]);
      final dataSource = _dataSource(store);

      await dataSource.add(second);
      await dataSource.add(
        const Exercise(
          id: 'custom-1',
          name: 'Updated Cable Press',
          muscles: ['Chest', 'Triceps'],
        ),
      );

      final stored = await dataSource.getAll();
      expect(store.writeCount, 2);
      expect(stored.map((exercise) => exercise.id), ['custom-1', 'custom-2']);
      expect(stored.first.name, 'Updated Cable Press');
      expect(stored.first.muscles, ['Chest', 'Triceps']);
    });

    test('setAll replaces the stored exercises', () async {
      final store = _FakePreferencesStore(initial: const [first]);
      final dataSource = _dataSource(store);

      await dataSource.setAll(const [second]);

      expect(store.writeCount, 1);
      expect((await dataSource.getAll()).map((exercise) => exercise.id), [
        'custom-2',
      ]);
    });

    test('removeById removes only the matching id', () async {
      const duplicateName = Exercise(
        id: 'custom-3',
        name: 'Cable Press',
        muscles: ['Chest'],
      );
      final store = _FakePreferencesStore(
        initial: const [first, duplicateName, second],
      );
      final dataSource = _dataSource(store);

      await dataSource.removeById('custom-1');

      expect(store.writeCount, 1);
      expect((await dataSource.getAll()).map((exercise) => exercise.id), [
        'custom-3',
        'custom-2',
      ]);
    });

    test('legacy remove-by-name remains case-insensitive', () async {
      const caseVariant = Exercise(name: 'CABLE PRESS', muscles: ['Chest']);
      final store = _FakePreferencesStore(
        initial: const [first, caseVariant, second],
      );
      final dataSource = _dataSource(store);

      await dataSource.removeByNameCaseInsensitive('cable press');

      expect(store.writeCount, 1);
      expect((await dataSource.getAll()).map((exercise) => exercise.id), [
        'custom-2',
      ]);
    });
  });
}
