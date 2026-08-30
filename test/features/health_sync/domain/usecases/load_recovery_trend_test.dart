import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/domain/repositories/health_metrics_repository.dart';
import 'package:hustl_app/features/health_sync/domain/usecases/load_latest_readiness.dart';
import 'package:hustl_app/features/health_sync/domain/usecases/load_recovery_trend.dart';

/// Fake repository returning fixed recovery snapshots and capturing the fetch
/// [start] so tests can assert the baseline lead is fetched.
class _FakeRepo implements HealthMetricsRepository {
  _FakeRepo(this._snapshots);

  final List<DailyRecoverySnapshot> _snapshots;
  DateTime? capturedStart;

  @override
  Future<HealthSnapshot> loadSnapshot({
    required DateTime start,
    required DateTime end,
    bool forceRefresh = false,
  }) async {
    capturedStart = start;
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
  final normToday = DateTime(today.year, today.month, today.day);
  DateTime dayAgo(int n) => normToday.subtract(Duration(days: n));

  test('returns only the trailing 14 days (oldest → newest), with-signal only, '
      'even though 56d are fetched to warm baselines', () async {
    final repo = _FakeRepo([
      _day(dayAgo(30)), // inside the 42d lead — must be trimmed out
      _day(dayAgo(5)), // inside display window — kept
      _day(dayAgo(3), withData: false), // no signal — excluded
      _day(dayAgo(1)), // inside display window — kept
    ]);

    final result = await LoadRecoveryTrendUseCase(repo)();

    expect(result.map((s) => s.date).toList(), [dayAgo(5), dayAgo(1)]);
    expect(result.every((s) => s.hasRecoveryData), isTrue);
    // Ordered oldest → newest.
    expect(result.first.date.isBefore(result.last.date), isTrue);

    // The fetch reaches back 14 display + 42 lead days.
    expect(repo.capturedStart, isNotNull);
    final leadDays = normToday.difference(repo.capturedStart!).inDays;
    expect(leadDays, inInclusiveRange(55, 57));
    expect(LoadLatestReadinessUseCase.baselineLeadDays, 42);
  });

  test(
    'returns [] when no snapshot in the display window carries signal',
    () async {
      final repo = _FakeRepo([
        _day(dayAgo(30)), // only lead-window data
        _day(dayAgo(2), withData: false), // in window but no signal
      ]);
      final result = await LoadRecoveryTrendUseCase(repo)();
      expect(result, isEmpty);
    },
  );
}
