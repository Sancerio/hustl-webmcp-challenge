import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/health_sync/domain/models/daily_health_summary.dart';
import 'package:hustl_app/features/health_sync/domain/models/recovery_signal_availability.dart';
import 'package:hustl_app/features/health_sync/domain/repositories/health_metrics_repository.dart';
import 'package:hustl_app/features/health_sync/presentation/bloc/health_overview_bloc.dart';

/// Fake repository whose `loadSnapshot` result/failure is fully controllable,
/// so tests can drive first-load, refetch, and refresh-failure paths without
/// a platform channel. Models the fake in
/// `test/features/health_sync/presentation/screens/health_overview_unavailable_install_test.dart`,
/// extended so `loadSnapshot` can throw or return a snapshot with one
/// [DailyHealthSummary].
class _FakeHealthRepo implements HealthMetricsRepository {
  _FakeHealthRepo({this.throwOnLoad = false});

  final bool throwOnLoad;
  int loadCalls = 0;

  @override
  Future<HealthPermissionsStatus> getPermissionsStatus() async =>
      const HealthPermissionsStatus(
        hasPermissions: true,
        isServiceAvailable: true,
      );

  @override
  Future<HealthPermissionsStatus> requestPermissions() async =>
      const HealthPermissionsStatus(
        hasPermissions: true,
        isServiceAvailable: true,
      );

  @override
  Future<HealthSnapshot> loadSnapshot({
    required DateTime start,
    required DateTime end,
    bool forceRefresh = false,
  }) async {
    loadCalls++;
    if (throwOnLoad) {
      throw Exception('load failed');
    }
    return HealthSnapshot(
      rangeStart: start,
      rangeEnd: end,
      metrics: const [],
      nutritionEntries: const [],
      dailySummaries: [_summaryFor(end)],
      recoverySnapshots: const [],
      lastSyncedAt: DateTime(2024, 1, 1),
    );
  }

  @override
  Future<void> clearCache() async {}

  @override
  Future<void> resetPermissionDenialFlag() async {}

  @override
  Future<HealthProviderAvailability> getProviderAvailability() async =>
      HealthProviderAvailability.available;

  @override
  Future<void> installHealthConnect() async {}
}

DailyHealthSummary _summaryFor(DateTime date) => DailyHealthSummary(
  date: DateTime(date.year, date.month, date.day),
  metrics: const [],
  nutritionLogs: const [],
  macros: const DailyMacroBreakdown(
    calories: 0,
    proteinGrams: 0,
    carbsGrams: 0,
    fatGrams: 0,
  ),
);

/// A ready state with visible data, seeded so refetch/refresh-failure tests
/// don't have to drive a real first load first.
HealthOverviewState _readyStateWithData() {
  final initial = HealthOverviewState.initial();
  return initial.copyWith(
    status: HealthOverviewStatus.ready,
    summaries: [_summaryFor(initial.rangeEnd)],
  );
}

void main() {
  group('HealthOverviewBloc', () {
    blocTest<HealthOverviewBloc, HealthOverviewState>(
      'first load success emits loading then ready',
      build: () => HealthOverviewBloc(_FakeHealthRepo()),
      act: (bloc) => bloc.add(const HealthOverviewStarted()),
      expect: () => [
        isA<HealthOverviewState>().having(
          (s) => s.status,
          'status',
          HealthOverviewStatus.loading,
        ),
        isA<HealthOverviewState>()
            .having((s) => s.status, 'status', HealthOverviewStatus.ready)
            .having((s) => s.summaries, 'summaries', isNotEmpty),
      ],
    );

    blocTest<HealthOverviewBloc, HealthOverviewState>(
      'refetch from ready keeps summaries visible and never emits loading',
      build: () => HealthOverviewBloc(_FakeHealthRepo()),
      seed: _readyStateWithData,
      act: (bloc) => bloc.add(const HealthOverviewRefreshed()),
      expect: () => [
        // In-flight refetch: still ready, old data intact, refresh flagged.
        isA<HealthOverviewState>()
            .having((s) => s.status, 'status', HealthOverviewStatus.ready)
            .having((s) => s.isRefreshing, 'isRefreshing', true)
            .having((s) => s.summaries, 'summaries', isNotEmpty),
        // Refresh lands: still ready, refresh flag cleared.
        isA<HealthOverviewState>()
            .having((s) => s.status, 'status', HealthOverviewStatus.ready)
            .having((s) => s.isRefreshing, 'isRefreshing', false)
            .having((s) => s.summaries, 'summaries', isNotEmpty),
      ],
    );

    blocTest<HealthOverviewBloc, HealthOverviewState>(
      'refetch failure from ready keeps ready + summaries and sets '
      'refreshError',
      build: () => HealthOverviewBloc(_FakeHealthRepo(throwOnLoad: true)),
      seed: _readyStateWithData,
      act: (bloc) => bloc.add(const HealthOverviewRefreshed()),
      expect: () => [
        isA<HealthOverviewState>()
            .having((s) => s.status, 'status', HealthOverviewStatus.ready)
            .having((s) => s.isRefreshing, 'isRefreshing', true),
        isA<HealthOverviewState>()
            .having((s) => s.status, 'status', HealthOverviewStatus.ready)
            .having((s) => s.isRefreshing, 'isRefreshing', false)
            .having((s) => s.summaries, 'summaries', isNotEmpty)
            .having(
              (s) => s.refreshError,
              'refreshError',
              "Couldn't refresh your health data. Showing your last synced "
                  'view.',
            ),
      ],
    );

    blocTest<HealthOverviewBloc, HealthOverviewState>(
      'first-load failure sets status to error',
      build: () => HealthOverviewBloc(_FakeHealthRepo(throwOnLoad: true)),
      act: (bloc) => bloc.add(const HealthOverviewStarted()),
      expect: () => [
        isA<HealthOverviewState>().having(
          (s) => s.status,
          'status',
          HealthOverviewStatus.loading,
        ),
        isA<HealthOverviewState>().having(
          (s) => s.status,
          'status',
          HealthOverviewStatus.error,
        ),
      ],
    );
  });
}
