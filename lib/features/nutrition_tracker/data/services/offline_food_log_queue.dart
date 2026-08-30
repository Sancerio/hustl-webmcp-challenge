import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/food.dart';
import '../../domain/models/food_log_entry.dart';

class OfflineFoodLogQueue {
  static const _prefsKey = 'nutrition_pending_food_log_ops';

  Future<List<Map<String, dynamic>>> loadOps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> saveOps(List<Map<String, dynamic>> ops) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(ops));
  }

  /// Drop the entire pending queue. Used on sign-out / account deletion so a
  /// departing user's queued food-log ops can't later upload under another
  /// account.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  Future<void> enqueueCreate(FoodLogEntry entry) async {
    final ops = await loadOps();
    ops.add({
      'type': 'create',
      'id': entry.id,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'entry': _toOfflineMap(entry),
    });
    await saveOps(ops);
  }

  Future<void> enqueueUpdate(String id, Map<String, dynamic> patch) async {
    final ops = await loadOps();

    final createIndex = ops.indexWhere(
      (o) => o['type'] == 'create' && o['id'] == id,
    );
    if (createIndex != -1) {
      final existingEntry = Map<String, dynamic>.from(
        ops[createIndex]['entry'] as Map,
      );
      ops[createIndex]['entry'] = _applyPatch(existingEntry, patch);
      ops[createIndex]['createdAt'] = DateTime.now().millisecondsSinceEpoch;
      await saveOps(ops);
      return;
    }

    final updateIndex = ops.indexWhere(
      (o) => o['type'] == 'update' && o['id'] == id,
    );
    if (updateIndex != -1) {
      final existingPatch = Map<String, dynamic>.from(
        ops[updateIndex]['patch'] as Map,
      );
      existingPatch.addAll(patch);
      ops[updateIndex]['patch'] = existingPatch;
      ops[updateIndex]['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    } else {
      ops.add({
        'type': 'update',
        'id': id,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'patch': patch,
      });
    }

    await saveOps(ops);
  }

  Future<void> enqueueDelete(String id) async {
    final ops = await loadOps();
    ops.removeWhere(
      (o) =>
          (o['type'] == 'create' && o['id'] == id) ||
          (o['type'] == 'update' && o['id'] == id),
    );

    if (!id.startsWith('temp-')) {
      ops.add({
        'type': 'delete',
        'id': id,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    }

    await saveOps(ops);
  }

  List<FoodLogEntry> applyPendingForDate(
    DateTime date,
    List<FoodLogEntry> remoteEntries,
    List<Map<String, dynamic>> ops,
  ) {
    final day = date.toIso8601String().substring(0, 10);
    final items = remoteEntries.toList(growable: true);

    final relevant = ops.toList()
      ..sort(
        (a, b) => (a['createdAt'] as int? ?? 0).compareTo(
          b['createdAt'] as int? ?? 0,
        ),
      );

    for (final op in relevant) {
      final type = op['type'];
      final id = op['id']?.toString() ?? '';
      if (type == 'create') {
        final entryMap = op['entry'];
        if (entryMap is Map) {
          final entry = _fromOfflineMap(Map<String, dynamic>.from(entryMap));
          if (entry.date.toIso8601String().substring(0, 10) == day) {
            items.add(entry);
          }
        }
      } else if (type == 'update') {
        final patch = op['patch'];
        if (patch is Map) {
          final index = items.indexWhere((e) => e.id == id);
          if (index != -1) {
            items[index] = _fromOfflineMap(
              _applyPatch(
                _toOfflineMap(items[index]),
                Map<String, dynamic>.from(patch),
              ),
            );
          }
        }
      } else if (type == 'delete') {
        items.removeWhere((e) => e.id == id);
      }
    }

    items.sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
    return items;
  }

  FoodLogEntry entryFromOp(Map<String, dynamic> op) {
    final entryMap = Map<String, dynamic>.from(op['entry'] as Map);
    return _fromOfflineMap(entryMap);
  }

  DateTime _parseLocalDate(String raw) {
    final s = raw.trim();
    if (s.length == 10 && s[4] == '-' && s[7] == '-') {
      final parts = s.split('-');
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y != null && m != null && d != null) return DateTime(y, m, d);
    }
    return DateTime.parse(s);
  }

  Map<String, dynamic> _toOfflineMap(FoodLogEntry entry) => {
    'id': entry.id,
    'date': entry.date.toIso8601String().substring(0, 10),
    'loggedAt': entry.loggedAt.toUtc().toIso8601String(),
    'servingGrams': entry.servingGrams,
    'calories': entry.calories,
    'proteinGrams': entry.proteinGrams,
    'carbsGrams': entry.carbsGrams,
    'fatGrams': entry.fatGrams,
    if (entry.fiberGrams != null) 'fiberGrams': entry.fiberGrams,
    if (entry.sugarGrams != null) 'sugarGrams': entry.sugarGrams,
    if (entry.sodiumMg != null) 'sodiumMg': entry.sodiumMg,
    if (entry.foodName != null) 'foodName': entry.foodName,
    if (entry.food != null) 'food': entry.food!.toMap(),
  };

  FoodLogEntry _fromOfflineMap(Map<String, dynamic> map) {
    final foodMap = map['food'];
    Food? food;
    if (foodMap is Map) {
      food = Food.fromMap(Map<String, dynamic>.from(foodMap));
    }
    return FoodLogEntry(
      id: map['id'].toString(),
      date: _parseLocalDate(map['date'] as String),
      loggedAt: DateTime.parse(map['loggedAt'] as String),
      servingGrams: (map['servingGrams'] as num?)?.toDouble() ?? 0,
      calories: (map['calories'] as num?)?.toDouble() ?? 0,
      proteinGrams: (map['proteinGrams'] as num?)?.toDouble() ?? 0,
      carbsGrams: (map['carbsGrams'] as num?)?.toDouble() ?? 0,
      fatGrams: (map['fatGrams'] as num?)?.toDouble() ?? 0,
      fiberGrams: (map['fiberGrams'] as num?)?.toDouble(),
      sugarGrams: (map['sugarGrams'] as num?)?.toDouble(),
      sodiumMg: (map['sodiumMg'] as num?)?.toDouble(),
      food: food,
      foodName: map['foodName']?.toString(),
    );
  }

  Map<String, dynamic> _applyPatch(
    Map<String, dynamic> existing,
    Map<String, dynamic> patch,
  ) {
    final merged = Map<String, dynamic>.from(existing);
    for (final entry in patch.entries) {
      merged[entry.key] = entry.value;
    }
    return merged;
  }
}
