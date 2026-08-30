import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/health_sync/domain/models/daily_health_summary.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/domain/models/health_metric_sample.dart';
import 'package:hustl_app/features/health_sync/domain/models/nutrition_log_entry.dart';
import 'package:hustl_app/features/health_sync/domain/models/recovery_signal_availability.dart';
import 'package:hustl_app/features/health_sync/domain/repositories/health_metrics_repository.dart';
import 'package:hustl_app/features/health_sync/presentation/bloc/health_permissions_bloc.dart';

/// Fake repository whose permission-status result is fully controllable, so
/// tests can move between granted/denied without going through a platform
/// channel. Models the fake in
/// `test/features/health_sync/presentation/screens/health_overview_unavailable_install_test.dart`,
/// extended with a settable [status].
class _FakeHealthRepo implements HealthMetricsRepository {
  _FakeHealthRepo({required this.status});

  HealthPermissionsStatus status;

  @override
  Future<HealthPermissionsStatus> getPermissionsStatus() async => status;

  @override
  Future<HealthPermissionsStatus> requestPermissions() async => status;

  @override
  Future<HealthSnapshot> loadSnapshot({
    required DateTime start,
    required DateTime end,
    bool forceRefresh = false,
  }) async => HealthSnapshot(
    rangeStart: start,
    rangeEnd: end,
    metrics: const <HealthMetricSample>[],
    nutritionEntries: const <NutritionLogEntry>[],
    dailySummaries: const <DailyHealthSummary>[],
    recoverySnapshots: const <DailyRecoverySnapshot>[],
    lastSyncedAt: DateTime(2024, 1, 1),
  );

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

const _grantedStatus = HealthPermissionsStatus(
  hasPermissions: true,
  isServiceAvailable: true,
);

void main() {
  group('HealthPermissionsBloc', () {
    blocTest<HealthPermissionsBloc, HealthPermissionsState>(
      'non-silent status request emits Loading then Granted',
      build: () =>
          HealthPermissionsBloc(_FakeHealthRepo(status: _grantedStatus)),
      act: (bloc) => bloc.add(const HealthPermissionsStatusRequested()),
      expect: () => [
        isA<HealthPermissionsLoading>(),
        isA<HealthPermissionsGranted>(),
      ],
    );

    blocTest<HealthPermissionsBloc, HealthPermissionsState>(
      'silent request while already Granted emits nothing '
      '(Granted == Granted is suppressed)',
      build: () =>
          HealthPermissionsBloc(_FakeHealthRepo(status: _grantedStatus)),
      // Prime a known prior state so the silent no-op is observable.
      seed: () => HealthPermissionsGranted(),
      act: (bloc) =>
          bloc.add(const HealthPermissionsStatusRequested(silent: true)),
      expect: () => const <HealthPermissionsState>[],
    );

    blocTest<HealthPermissionsBloc, HealthPermissionsState>(
      'silent request while Denied and the repo now grants emits Granted, '
      'with no Loading in between',
      build: () =>
          HealthPermissionsBloc(_FakeHealthRepo(status: _grantedStatus)),
      seed: () => const HealthPermissionsDenied(),
      act: (bloc) =>
          bloc.add(const HealthPermissionsStatusRequested(silent: true)),
      expect: () => [isA<HealthPermissionsGranted>()],
    );
  });
}
