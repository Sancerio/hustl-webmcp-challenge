import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/exercise.dart';

abstract class ExerciseCacheDataSource {
  Future<List<Exercise>?> getAll();
  Future<void> saveAll(List<Exercise> items);
  Future<DateTime?> getLastUpdated();
}

class ExerciseCacheLocalDataSource implements ExerciseCacheDataSource {
  // Bump cache version when the Exercise schema changes (e.g., adding
  // `loggingMode`) so older cached payloads don’t override updated seed/backend.
  static const String _key = 'cached_exercises_v3';
  static const String _metaKey = 'cached_exercises_v3_meta';

  @override
  Future<List<Exercise>?> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      final List<dynamic> data = jsonDecode(jsonStr) as List<dynamic>;
      return data
          .map((e) => Exercise.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveAll(List<Exercise> items) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(items.map((e) => e.toMap()).toList());
    await prefs.setString(_key, jsonStr);
    await prefs.setString(
      _metaKey,
      jsonEncode({
        'updated_at': DateTime.now().toIso8601String(),
        'count': items.length,
      }),
    );
  }

  @override
  Future<DateTime?> getLastUpdated() async {
    final prefs = await SharedPreferences.getInstance();
    final meta = prefs.getString(_metaKey);
    if (meta == null) return null;
    try {
      final m = jsonDecode(meta) as Map<String, dynamic>;
      final s = m['updated_at'] as String?;
      if (s == null || s.isEmpty) return null;
      return DateTime.tryParse(s);
    } catch (_) {
      return null;
    }
  }
}
