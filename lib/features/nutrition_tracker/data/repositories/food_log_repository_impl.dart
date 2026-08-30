import '../../domain/models/food_log_entry.dart';
import '../../domain/repositories/food_log_repository.dart';
import '../../presentation/utils/go_to_ranking.dart';
import '../datasources/hustl_backend_nutrition_api.dart';
import '../services/offline_food_log_queue.dart';

class FoodLogRepositoryImpl
    implements FoodLogRepository, ReadOnlyFoodLogRepository {
  FoodLogRepositoryImpl({required this.api, required this.offlineQueue});

  final HustlBackendNutritionApi api;
  final OfflineFoodLogQueue offlineQueue;

  Future<void> _flushPendingOps() async {
    final ops = await offlineQueue.loadOps();
    if (ops.isEmpty) return;
    final remaining = ops.toList();

    final createOps = remaining.where((o) => o['type'] == 'create').toList();
    if (createOps.isNotEmpty) {
      final byDate = <String, List<Map<String, dynamic>>>{};
      for (final op in createOps) {
        final entry = offlineQueue.entryFromOp(op);
        final day = entry.date.toIso8601String().substring(0, 10);
        byDate.putIfAbsent(day, () => []).add(op);
      }

      for (final group in byDate.values) {
        final payloads = group
            .map((o) => offlineQueue.entryFromOp(o).toPayload())
            .toList();
        try {
          await api.addFoodLogs(payloads);
          remaining.removeWhere((o) => group.contains(o));
        } catch (_) {
          await offlineQueue.saveOps(remaining);
          return;
        }
      }
    }

    final updateOps = remaining.where((o) => o['type'] == 'update').toList()
      ..sort(
        (a, b) => (a['createdAt'] as int? ?? 0).compareTo(
          b['createdAt'] as int? ?? 0,
        ),
      );
    for (final op in updateOps) {
      final id = op['id']?.toString() ?? '';
      final patch = op['patch'];
      if (patch is! Map) continue;
      try {
        await api.updateFoodLog(id, Map<String, dynamic>.from(patch));
        remaining.remove(op);
      } catch (_) {
        await offlineQueue.saveOps(remaining);
        return;
      }
    }

    final deleteOps = remaining.where((o) => o['type'] == 'delete').toList()
      ..sort(
        (a, b) => (a['createdAt'] as int? ?? 0).compareTo(
          b['createdAt'] as int? ?? 0,
        ),
      );
    for (final op in deleteOps) {
      final id = op['id']?.toString() ?? '';
      try {
        await api.deleteFoodLog(id);
        remaining.remove(op);
      } catch (_) {
        await offlineQueue.saveOps(remaining);
        return;
      }
    }

    await offlineQueue.saveOps(remaining);
  }

  @override
  Future<List<FoodLogEntry>> getLogsForDate(DateTime date) async {
    await _flushPendingOps();
    final ops = await offlineQueue.loadOps();
    try {
      final items = await api.listFoodLogs(date);
      final remote = items.map(FoodLogEntry.fromMap).toList(growable: false);
      return offlineQueue.applyPendingForDate(date, remote, ops);
    } catch (_) {
      return offlineQueue.applyPendingForDate(date, const [], ops);
    }
  }

  @override
  Future<List<FoodLogEntry>> getLogsForDateReadOnly(DateTime date) async {
    final ops = await offlineQueue.loadOps();
    final items = await api.listFoodLogs(date);
    final remote = items.map(FoodLogEntry.fromMap).toList(growable: false);
    return offlineQueue.applyPendingForDate(date, remote, ops);
  }

  @override
  Future<List<FoodLogEntry>> getLogsForRange(
    DateTime start,
    DateTime end,
  ) async {
    // Flush queued offline writes first (mirrors getLogsForDate) so the export
    // includes anything logged offline; but the read itself is online-only and
    // lets failures propagate — a data export must error loudly rather than
    // return a partial history the way the day view degrades.
    await _flushPendingOps();
    final items = await api.listFoodLogsRange(start, end);
    return items.map(FoodLogEntry.fromMap).toList(growable: false);
  }

  @override
  Future<FoodSuggestions> getSuggestions({
    required int tzOffsetMinutes,
    int recentLimit = 12,
    int suggestionLimit = 4,
  }) async {
    // Mirror getLogsForDate: flush queued creates first so server-side
    // recents/suggestions already include anything that just synced.
    await _flushPendingOps();
    final ops = await offlineQueue.loadOps();
    final pendingRecents = _pendingRecents(ops);

    try {
      final maps = await api.getFoodSuggestions(
        tzOffsetMinutes: tzOffsetMinutes,
        recentLimit: recentLimit,
        suggestionLimit: suggestionLimit,
      );
      List<FoodLogEntry> parse(String key) => (maps[key] ?? const [])
          .map(FoodLogEntry.fromSnapshot)
          .toList(growable: false);
      final suggestions = parse('suggestions');
      final recents = parse('recents');
      return FoodSuggestions(
        suggestions: suggestions,
        // Overlay foods logged offline (still queued) so they show in Recent
        // before the create syncs. Deduped by the same key the backend uses.
        recents: _overlayPending(
          pendingRecents,
          recents,
          suggestions,
          recentLimit,
        ),
      );
    } catch (_) {
      // Offline / non-2xx: "Suggested for now" is a server-computed ranking, so
      // it stays empty, but Recent must survive — rebuild it from the local
      // pending-create queue instead of returning empty.
      return FoodSuggestions(
        recents: pendingRecents.take(recentLimit).toList(growable: false),
      );
    }
  }

  /// Distinct foods from queued offline creates, most-recent-first, deduped by
  /// [backendCompatibleKey] (the backend-id|food_name key the server's recents
  /// use). The representative is the most recently logged entry for that food so
  /// a re-log reuses the last portion.
  List<FoodLogEntry> _pendingRecents(List<Map<String, dynamic>> ops) {
    final byFood = <String, FoodLogEntry>{};
    for (final op in ops) {
      if (op['type'] != 'create') continue;
      final entryMap = op['entry'];
      if (entryMap is! Map) continue;
      final entry = offlineQueue.entryFromOp(Map<String, dynamic>.from(op));
      final key = backendCompatibleKey(entry);
      if (key.isEmpty) continue;
      final existing = byFood[key];
      if (existing == null || entry.loggedAt.isAfter(existing.loggedAt)) {
        byFood[key] = entry;
      }
    }
    final recents = byFood.values.toList()
      ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
    return recents;
  }

  /// Merges offline [pending] creates ahead of the server [recents], excluding
  /// anything already shown under [suggestions], deduped by
  /// [backendCompatibleKey], and capped at [limit].
  List<FoodLogEntry> _overlayPending(
    List<FoodLogEntry> pending,
    List<FoodLogEntry> recents,
    List<FoodLogEntry> suggestions,
    int limit,
  ) {
    final seen = suggestions.map(backendCompatibleKey).toSet();
    final merged = <FoodLogEntry>[];
    for (final entry in [...pending, ...recents]) {
      final key = backendCompatibleKey(entry);
      if (key.isEmpty || !seen.add(key)) continue;
      merged.add(entry);
      if (merged.length >= limit) break;
    }
    return merged;
  }

  @override
  Future<List<FoodLogEntry>> addEntries(List<FoodLogEntry> entries) async {
    final payloads = entries.map((e) => e.toPayload()).toList();
    try {
      final maps = await api.addFoodLogs(payloads);
      return maps.map(FoodLogEntry.fromMap).toList(growable: false);
    } catch (_) {
      for (final entry in entries) {
        await offlineQueue.enqueueCreate(entry);
      }
      return entries;
    }
  }

  @override
  Future<FoodLogEntry> updateEntry(
    String id,
    Map<String, dynamic> patch,
  ) async {
    try {
      final map = await api.updateFoodLog(id, patch);
      return FoodLogEntry.fromMap(map);
    } catch (_) {
      await offlineQueue.enqueueUpdate(id, patch);
      final ops = await offlineQueue.loadOps();
      final createOp = ops.cast<Map<String, dynamic>>().firstWhere(
        (o) => o['type'] == 'create' && o['id'] == id,
        orElse: () => {},
      );
      if (createOp.isNotEmpty) {
        return offlineQueue.entryFromOp(createOp);
      }
      return FoodLogEntry(
        id: id,
        date: DateTime.now(),
        loggedAt: DateTime.now(),
        servingGrams: (patch['servingGrams'] as num?)?.toDouble() ?? 0,
        calories: (patch['calories'] as num?)?.toDouble() ?? 0,
        proteinGrams: (patch['proteinGrams'] as num?)?.toDouble() ?? 0,
        carbsGrams: (patch['carbsGrams'] as num?)?.toDouble() ?? 0,
        fatGrams: (patch['fatGrams'] as num?)?.toDouble() ?? 0,
      );
    }
  }

  @override
  Future<void> deleteEntry(String id) async {
    try {
      await api.deleteFoodLog(id);
    } catch (_) {
      await offlineQueue.enqueueDelete(id);
    }
  }

  @override
  Future<List<FoodLogEntry>> copyDay(
    DateTime fromDate,
    DateTime toDate, {
    bool replaceExisting = false,
  }) async {
    // Online-only: the copy is a server-side time-shift + recompute of a whole
    // day; let failures (incl. offline) surface to the caller for an error toast.
    final maps = await api.copyFoodLogs(
      fromDate: _ymd(fromDate),
      toDate: _ymd(toDate),
      replaceExisting: replaceExisting,
      tzOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
    );
    return maps.map(FoodLogEntry.fromMap).toList(growable: false);
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
