import '../models/daily_recovery_snapshot.dart';
import '../repositories/health_metrics_repository.dart';

/// A tiny, non-blocking read of the latest readiness for the Train home.
///
/// Reuses the SAME recovery pipeline the `/health` dashboard uses — it calls
/// [HealthMetricsRepository.loadSnapshot], which internally builds
/// `DailyRecoverySnapshot`s via `BuildDailyRecoverySnapshotsUseCase`. We do NOT
/// pull in the whole `HealthOverviewBloc`; this is a single lightweight read so
/// the training home never duplicates scoring logic and never disagrees with
/// the dashboard.
///
/// Every failure mode collapses to `null` so the Train home renders exactly as
/// today when readiness is absent: no permissions, no device data, an empty
/// window, or any thrown error all return `null`.
class LoadLatestReadinessUseCase {
  const LoadLatestReadinessUseCase(this._repository);

  final HealthMetricsRepository _repository;

  /// Days of history the recovery algorithm needs BEFORE the first displayed
  /// day: 28d robust baselines + 42d chronic load (see
  /// BuildDailyRecoverySnapshotsUseCase.baselineWindowDays / chronicLoad42).
  /// The 42d chronic-load window dominates, so this is the single source of
  /// truth other recovery reads import for their fetch lead.
  static const int baselineLeadDays = 42;

  /// The trailing window the surface actually displays (last ~14 days). We fetch
  /// [baselineLeadDays] extra days before it purely to warm up baselines /
  /// chronic load, so coverage + confidence read correctly instead of
  /// permanently "calibrating".
  static const int displayWindowDays = 14;

  /// Returns the most recent [DailyRecoverySnapshot] that carries recovery
  /// signal within the display window, or `null` on any error or when none in
  /// the window has signal. Best-effort and side-effect free.
  Future<DailyRecoverySnapshot?> call() async {
    try {
      final end = DateTime.now();
      final normalizedEnd = DateTime(end.year, end.month, end.day);
      final displayStart = normalizedEnd.subtract(
        const Duration(days: displayWindowDays),
      );
      final snapshot = await _repository.loadSnapshot(
        start: displayStart.subtract(const Duration(days: baselineLeadDays)),
        end: normalizedEnd,
      );
      final recovery = snapshot.recoverySnapshots.toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      // Scan newest → oldest and surface the first day that actually carries
      // recovery signal. This falls back past an empty shell (no sleep/HRV/RHR),
      // common in the morning before HealthKit has today's sleep, to yesterday's
      // real readiness instead of rendering nothing. The fallback never leaves
      // the display window: the extra [baselineLeadDays] of fetched history
      // exist purely to warm up baselines, and month-old readiness must not be
      // rendered as current on the Train home.
      for (final day in recovery) {
        if (day.date.isBefore(displayStart)) break;
        if (day.hasRecoveryData) return day;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
