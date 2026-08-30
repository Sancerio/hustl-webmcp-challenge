import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/exercise.dart';

abstract class CustomExerciseDataSource {
  Future<List<Exercise>> getAll();
  Future<void> add(Exercise exercise);
  Future<void> setAll(List<Exercise> exercises);
  Future<void> removeById(String id);
  Future<void> removeByNameCaseInsensitive(String name);
}

abstract interface class CustomExercisePreferencesStore {
  String? getString(String key);
  Future<bool> setString(String key, String value);
}

typedef CustomExercisePreferencesStoreLoader =
    Future<CustomExercisePreferencesStore> Function();

enum CustomExerciseWriteOperation {
  add,
  setAll,
  removeById,
  removeByNameCaseInsensitive,
}

class CustomExercisePersistenceException implements Exception {
  const CustomExercisePersistenceException(this.operation);

  final CustomExerciseWriteOperation operation;

  @override
  String toString() =>
      'CustomExercisePersistenceException: ${operation.name} write failed';
}

class CustomExerciseLocalDataSource implements CustomExerciseDataSource {
  static const String _key = 'custom_exercises_v1';

  CustomExerciseLocalDataSource({
    CustomExercisePreferencesStoreLoader? storeLoader,
  }) : _storeLoader = storeLoader ?? _loadSharedPreferencesStore;

  final CustomExercisePreferencesStoreLoader _storeLoader;

  static Future<CustomExercisePreferencesStore>
  _loadSharedPreferencesStore() async {
    return _SharedPreferencesCustomExerciseStore(
      await SharedPreferences.getInstance(),
    );
  }

  @override
  Future<List<Exercise>> getAll() async {
    final store = await _storeLoader();
    return _readAll(store);
  }

  List<Exercise> _readAll(CustomExercisePreferencesStore store) {
    final jsonStr = store.getString(_key);
    if (jsonStr == null || jsonStr.isEmpty) return const [];
    try {
      final List<dynamic> data = jsonDecode(jsonStr) as List<dynamic>;
      return data
          .map((e) => Exercise.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> add(Exercise exercise) async {
    final store = await _storeLoader();
    final existing = _readAll(store);
    // Replace by id if exists; otherwise append
    final List<Exercise> updated;
    if (exercise.id != null) {
      final idx = existing.indexWhere((e) => e.id == exercise.id);
      if (idx >= 0) {
        updated = List.of(existing)..[idx] = exercise;
      } else {
        updated = List.of(existing)..add(exercise);
      }
    } else {
      updated = List.of(existing)..add(exercise);
    }
    await _persist(store, updated, CustomExerciseWriteOperation.add);
  }

  @override
  Future<void> setAll(List<Exercise> exercises) async {
    final store = await _storeLoader();
    await _persist(store, exercises, CustomExerciseWriteOperation.setAll);
  }

  @override
  Future<void> removeById(String id) async {
    final store = await _storeLoader();
    final existing = _readAll(store);
    final updated = existing.where((e) => e.id != id).toList(growable: false);
    await _persist(store, updated, CustomExerciseWriteOperation.removeById);
  }

  @override
  Future<void> removeByNameCaseInsensitive(String name) async {
    final store = await _storeLoader();
    final existing = _readAll(store);
    final n = name.toLowerCase();
    final updated = existing
        .where((e) => e.name.toLowerCase() != n)
        .toList(growable: false);
    await _persist(
      store,
      updated,
      CustomExerciseWriteOperation.removeByNameCaseInsensitive,
    );
  }

  Future<void> _persist(
    CustomExercisePreferencesStore store,
    List<Exercise> exercises,
    CustomExerciseWriteOperation operation,
  ) async {
    final succeeded = await store.setString(
      _key,
      jsonEncode(exercises.map((e) => e.toMap()).toList()),
    );
    if (!succeeded) {
      throw CustomExercisePersistenceException(operation);
    }
  }
}

class _SharedPreferencesCustomExerciseStore
    implements CustomExercisePreferencesStore {
  const _SharedPreferencesCustomExerciseStore(this._preferences);

  final SharedPreferences _preferences;

  @override
  String? getString(String key) => _preferences.getString(key);

  @override
  Future<bool> setString(String key, String value) {
    return _preferences.setString(key, value);
  }
}
