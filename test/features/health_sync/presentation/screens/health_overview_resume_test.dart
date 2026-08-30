import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/core/widgets/hustl_inline_skeleton.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_health_summary.dart';
import 'package:hustl_app/features/health_sync/domain/models/recovery_signal_availability.dart';
import 'package:hustl_app/features/health_sync/domain/repositories/health_metrics_repository.dart';
import 'package:hustl_app/features/health_sync/presentation/screens/health_overview_screen.dart';

/// A fake repository with granted permissions and a one-summary snapshot, so
/// the screen reaches the rendered dashboard without a platform channel.
/// Models the fake in
/// `health_overview_unavailable_install_test.dart` (lines 11-61), extended to
/// report granted permissions, return real summaries, and count
/// [loadSnapshot] calls so a resume-triggered refresh is observable.
class _FakeHealthRepo implements HealthMetricsRepository {
  int loadSnapshotCalls = 0;

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
    loadSnapshotCalls++;
    return HealthSnapshot(
      rangeStart: start,
      rangeEnd: end,
      metrics: const [],
      nutritionEntries: const [],
      dailySummaries: [
        DailyHealthSummary(
          date: DateTime(end.year, end.month, end.day),
          metrics: const [],
          nutritionLogs: const [],
          macros: const DailyMacroBreakdown(
            calories: 0,
            proteinGrams: 0,
            carbsGrams: 0,
            fatGrams: 0,
          ),
        ),
      ],
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

void main() {
  testWidgets(
    'resume re-checks permissions and refreshes data without a skeleton '
    'flash',
    (tester) async {
      final repo = _FakeHealthRepo();

      await tester.pumpWidget(
        MaterialApp(home: HealthOverviewScreen(repositoryOverride: repo)),
      );
      // Permission status load -> Granted -> first HealthOverviewStarted load.
      await tester.pumpAndSettle();

      // The dashboard is rendered before backgrounding.
      expect(find.byType(HustlInlineSkeleton), findsNothing);
      final loadsBeforeResume = repo.loadSnapshotCalls;

      // Simulate the app being backgrounded and resumed.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // No full-screen skeleton flash on the frames right after resume: the
      // rendered dashboard stays visible while the silent permission
      // re-check and the non-destructive refresh happen in the background.
      expect(find.byType(HustlInlineSkeleton), findsNothing);

      await tester.pumpAndSettle();

      // Exactly one extra load happened: the resume-triggered refresh.
      expect(repo.loadSnapshotCalls, loadsBeforeResume + 1);
      expect(find.byType(HustlInlineSkeleton), findsNothing);
    },
  );
}
