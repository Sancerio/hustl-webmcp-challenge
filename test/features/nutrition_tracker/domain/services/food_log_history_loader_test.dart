import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/services/food_log_history_loader.dart';

class _WindowedFakeRepo implements FoodLogRepository {
  _WindowedFakeRepo(this.entries);

  /// Entries the "backend" holds; getLogsForRange filters them by window.
  final List<FoodLogEntry> entries;
  final List<({DateTime start, DateTime end})> calls = [];

  @override
  Future<List<FoodLogEntry>> getLogsForRange(DateTime start, DateTime end) async {
    calls.add((start: start, end: end));
    return entries
        .where((e) => !e.date.isBefore(start) && !e.date.isAfter(end))
        .toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

FoodLogEntry _entry(String id, DateTime date) => FoodLogEntry(
  id: id,
  date: date,
  loggedAt: date.add(const Duration(hours: 9)),
  servingGrams: 100,
  calories: 200,
  proteinGrams: 10,
  carbsGrams: 20,
  fatGrams: 5,
);

void main() {
  final today = DateTime(2026, 7, 5);

  test('collects entries across windows, oldest first', () async {
    final repo = _WindowedFakeRepo([
      _entry('recent', DateTime(2026, 7, 1)),
      _entry('older', DateTime(2025, 3, 1)), // previous window
    ]);
    final loader = FoodLogHistoryLoader(repository: repo);

    final all = await loader.loadAll(now: today);

    expect(all.map((e) => e.id).toList(), ['older', 'recent']);
    // Window 1 (data), window 2 (data), window 3 empty after data -> stop.
    expect(repo.calls, hasLength(3));
  });

  test('windows are contiguous, inclusive, and never exceed 366 days', () async {
    final repo = _WindowedFakeRepo(const []);
    final loader = FoodLogHistoryLoader(repository: repo);

    await loader.loadAll(now: today);

    for (final call in repo.calls) {
      final days = call.end.difference(call.start).inDays + 1;
      expect(days, lessThanOrEqualTo(FoodLogHistoryLoader.windowDays));
      expect(call.start.isAfter(call.end), isFalse);
    }
    expect(repo.calls.first.end, today);
    for (var i = 1; i < repo.calls.length; i++) {
      // Each older window ends the day before the previous window starts
      // (component arithmetic, like the loader, so DST can't skew midnight).
      final prevStart = repo.calls[i - 1].start;
      expect(
        repo.calls[i].end,
        DateTime(prevStart.year, prevStart.month, prevStart.day - 1),
      );
    }
  });

  test('with no data at all, walks to the 10-year floor and returns empty', () async {
    final repo = _WindowedFakeRepo(const []);
    final loader = FoodLogHistoryLoader(repository: repo);
    final progress = <int>[];

    final all = await loader.loadAll(
      now: today,
      onWindowFetched: progress.add,
    );

    expect(all, isEmpty);
    // ceil(3650 / 366) = 10 windows, the last clamped to the floor.
    expect(repo.calls, hasLength(10));
    expect(
      repo.calls.last.start,
      DateTime(today.year, today.month, today.day - FoodLogHistoryLoader.maxHistoryDays),
    );
    expect(progress, List.generate(10, (i) => i + 1));
  });

  test('a recent logging gap does not truncate older history', () async {
    // Data ONLY ~2 windows back: the leading empty window must not stop the
    // walk; the empty window AFTER the data must.
    final repo = _WindowedFakeRepo([
      _entry('ancient', DateTime(2024, 9, 1)),
    ]);
    final loader = FoodLogHistoryLoader(repository: repo);

    final all = await loader.loadAll(now: today);

    expect(all.map((e) => e.id).toList(), ['ancient']);
    // Window 1 empty (keep going), window 2 has it, window 3 empty -> stop.
    expect(repo.calls, hasLength(3));
  });

  test('a mid-fetch failure propagates instead of returning partial history', () async {
    final repo = _ThrowingRepo();
    final loader = FoodLogHistoryLoader(repository: repo);

    expect(() => loader.loadAll(now: today), throwsA(isA<StateError>()));
  });
}

class _ThrowingRepo implements FoodLogRepository {
  @override
  Future<List<FoodLogEntry>> getLogsForRange(DateTime start, DateTime end) async {
    throw StateError('offline');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
