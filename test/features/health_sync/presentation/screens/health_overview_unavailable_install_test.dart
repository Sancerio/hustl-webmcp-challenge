import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/health_sync/domain/models/recovery_signal_availability.dart';
import 'package:hustl_app/features/health_sync/domain/repositories/health_metrics_repository.dart';
import 'package:hustl_app/features/health_sync/presentation/screens/health_overview_screen.dart';

/// A fake repository whose permission status reports the service as
/// unavailable (as Health Connect does when it is missing/out-of-date on
/// Android), while [getProviderAvailability] reports whatever the test sets.
class _FakeHealthRepo implements HealthMetricsRepository {
  _FakeHealthRepo(
    this._provider, {
    this.permissionsStatus = const HealthPermissionsStatus(
      hasPermissions: false,
      isServiceAvailable: false,
    ),
    this.permissionsStatusFuture,
  });

  final HealthProviderAvailability _provider;
  final HealthPermissionsStatus permissionsStatus;
  final Future<HealthPermissionsStatus>? permissionsStatusFuture;
  int installCalls = 0;

  @override
  Future<HealthPermissionsStatus> getPermissionsStatus() =>
      permissionsStatusFuture ?? Future.value(permissionsStatus);

  @override
  Future<HealthProviderAvailability> getProviderAvailability() async =>
      _provider;

  @override
  Future<void> installHealthConnect() async {
    installCalls++;
  }

  @override
  Future<HealthPermissionsStatus> requestPermissions() async =>
      const HealthPermissionsStatus(
        hasPermissions: false,
        isServiceAvailable: false,
      );

  @override
  Future<HealthSnapshot> loadSnapshot({
    required DateTime start,
    required DateTime end,
    bool forceRefresh = false,
  }) async => HealthSnapshot(
    rangeStart: start,
    rangeEnd: end,
    metrics: const [],
    nutritionEntries: const [],
    dailySummaries: const [],
    recoverySnapshots: const [],
    lastSyncedAt: DateTime(2024, 1, 1),
  );

  @override
  Future<void> clearCache() async {}

  @override
  Future<void> resetPermissionDenialFlag() async {}
}

void main() {
  testWidgets(
    'unavailable + needsInstall routes to the install CTA, not the dead-end '
    'unsupported view',
    (tester) async {
      final repo = _FakeHealthRepo(HealthProviderAvailability.needsInstall);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: HealthOverviewScreen(repositoryOverride: repo),
        ),
      );
      // Permission-status load + post-frame + provider-availability probe.
      await tester.pumpAndSettle();

      // The install CTA is reachable.
      expect(find.text('Get Health Connect'), findsOneWidget);
      expect(find.text('Mobile device required'), findsOneWidget);
      expect(find.text('Live health sync'), findsNothing);
      // And we did NOT dead-end on the unsupported-device copy.
      expect(
        find.textContaining('Health data needs a supported device'),
        findsNothing,
      );

      // Tapping the CTA routes to the install action.
      await tester.ensureVisible(find.text('Get Health Connect'));
      await tester.pump();
      await tester.tap(find.text('Get Health Connect'));
      await tester.pump();
      expect(repo.installCalls, 1);
    },
  );

  testWidgets(
    'unavailable + needsUpdate routes to the update CTA (same Play listing)',
    (tester) async {
      final repo = _FakeHealthRepo(HealthProviderAvailability.needsUpdate);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: HealthOverviewScreen(repositoryOverride: repo),
        ),
      );
      await tester.pumpAndSettle();

      // The update CTA button is reachable (distinct copy from the install
      // state). The title also reads "Update Health Connect", so target the
      // FilledButton specifically.
      final updateCta = find.widgetWithText(
        FilledButton,
        'Update Health Connect',
      );
      expect(updateCta, findsOneWidget);
      expect(find.text('Get Health Connect'), findsNothing);
      expect(find.text('Mobile device required'), findsOneWidget);
      expect(find.text('Live health sync'), findsNothing);
      // And we did NOT dead-end on the unsupported-device copy.
      expect(
        find.textContaining('Health data needs a supported device'),
        findsNothing,
      );

      // Tapping the CTA routes to the same install/update action.
      await tester.ensureVisible(updateCta);
      await tester.pump();
      await tester.tap(updateCta);
      await tester.pump();
      expect(repo.installCalls, 1);
    },
  );

  testWidgets(
    'unavailable + genuinely unsupported keeps the unsupported-device copy',
    (tester) async {
      final repo = _FakeHealthRepo(HealthProviderAvailability.unsupported);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: HealthOverviewScreen(repositoryOverride: repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Health data needs a supported device'),
        findsOneWidget,
      );
      expect(find.text('Mobile device required'), findsOneWidget);
      expect(find.text('Live health sync'), findsNothing);
      expect(find.text('Get Health Connect'), findsNothing);
    },
  );

  testWidgets('granted permissions show live health sync', (tester) async {
    final repo = _FakeHealthRepo(
      HealthProviderAvailability.available,
      permissionsStatus: const HealthPermissionsStatus(
        hasPermissions: true,
        isServiceAvailable: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: HealthOverviewScreen(repositoryOverride: repo)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Live health sync'), findsOneWidget);
    expect(find.text('Checking health sync'), findsNothing);
  });

  testWidgets('pending permission check shows checking health sync', (
    tester,
  ) async {
    final pendingStatus = Completer<HealthPermissionsStatus>();
    final repo = _FakeHealthRepo(
      HealthProviderAvailability.available,
      permissionsStatusFuture: pendingStatus.future,
    );

    await tester.pumpWidget(
      MaterialApp(home: HealthOverviewScreen(repositoryOverride: repo)),
    );
    await tester.pump();

    expect(find.text('Checking health sync'), findsOneWidget);
    expect(find.text('Live health sync'), findsNothing);
  });

  testWidgets('preview label wins over permission status', (tester) async {
    final repo = _FakeHealthRepo(
      HealthProviderAvailability.available,
      permissionsStatus: const HealthPermissionsStatus(
        hasPermissions: true,
        isServiceAvailable: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HealthOverviewScreen(repositoryOverride: repo, previewMode: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preview data'), findsOneWidget);
    expect(find.text('Live health sync'), findsNothing);
  });
}
