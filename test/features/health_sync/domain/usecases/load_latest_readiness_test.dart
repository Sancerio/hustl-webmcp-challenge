import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/domain/repositories/health_metrics_repository.dart';
import 'package:hustl_app/features/health_sync/domain/usecases/load_latest_readiness.dart';

/// Fake repository that returns a fixed set of recovery snapshots and captures
/// the requested [start] so tests can assert on the fetch lead.
class _FakeRepo implements HealthMetricsRepository {
  _FakeRepo(this._snapshots);

  final List<DailyRecoverySnapshot> _snapshots;
  DateTime? capturedStart;
  DateTime? capturedEnd;

  @override
  Future<HealthSnapshot> loadSnapshot({
    required DateTime start,
    required DateTime end,
    bool forceRefresh = false,
  }) async {
    capturedStart = start;
    capturedEnd = end;
    return HealthSnapshot(
      rangeStart: start,
      rangeEnd: end,
      metrics: const [],
      nutritionEntries: const [],
      dailySummaries: const [],
      recoverySnapshots: _snapshots,
      lastSyncedAt: DateTime.now(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DailyRecoverySnapshot _day(DateTime date, {bool withData = true}) =>
    DailyRecoverySnapshot(
      date: DateTime(date.year, date.month, date.day),
      sleepPerformanceScore: withData ? 80 : null,
      hrvValue: withData ? 55 : null,
      hrvKind: HrvKind.sdnn,
      restingHeartRateBpm: withData ? 54 : null,
      readinessScore: withData ? 70 : null,
      baselineCoverageDays: 21,
    );

void main() {
  final today = DateTime.now();
  DateTime dayAgo(int n) =>
      DateTime(today.year, today.month, today.day).subtract(Duration(days: n));

  test('falls back to the last real readiness when the newest day is an empty '
      'shell', () async {
    final repo = _FakeRepo([
      _day(dayAgo(2), withData: true), // yesterday-1: real readiness
      _day(dayAgo(0), withData: false), // today: empty shell (no sleep yet)
    ]);
    final result = await LoadLatestReadinessUseCase(repo)();

    expect(result, isNotNull);
    expect(
      result!.date,
      DateTime(dayAgo(2).year, dayAgo(2).month, dayAgo(2).day),
    );
    expect(result.hasRecoveryData, isTrue);
  });

  test(
    'returns null when no day in the window carries recovery signal',
    () async {
      final repo = _FakeRepo([
        _day(dayAgo(1), withData: false),
        _day(dayAgo(0), withData: false),
      ]);
      final result = await LoadLatestReadinessUseCase(repo)();

      expect(result, isNull);
    },
  );

  test('never surfaces stale readiness from the baseline lead: signal 20 days '
      'ago with empty shells since → null', () async {
    final repo = _FakeRepo([
      _day(dayAgo(20), withData: true), // outside the 14d display window
      _day(dayAgo(1), withData: false),
      _day(dayAgo(0), withData: false),
    ]);
    final result = await LoadLatestReadinessUseCase(repo)();

    expect(result, isNull);
  });

  test('fetches a start date ~56 days back (14d display + 42d lead)', () async {
    final repo = _FakeRepo([_day(dayAgo(0))]);
    await LoadLatestReadinessUseCase(repo)();

    expect(repo.capturedStart, isNotNull);
    final normToday = DateTime(today.year, today.month, today.day);
    final leadDays = normToday.difference(repo.capturedStart!).inDays;
    // 14 display + 42 lead = 56; allow ±1 for a midnight roll during the test.
    expect(leadDays, inInclusiveRange(55, 57));
    expect(LoadLatestReadinessUseCase.baselineLeadDays, 42);
  });

  test(
    'collapses any thrown error to null (best-effort, side-effect free)',
    () async {
      final result = await LoadLatestReadinessUseCase(_ThrowingRepo())();
      expect(result, isNull);
    },
  );
}

class _ThrowingRepo implements HealthMetricsRepository {
  @override
  Future<HealthSnapshot> loadSnapshot({
    required DateTime start,
    required DateTime end,
    bool forceRefresh = false,
  }) async => throw StateError('boom');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
