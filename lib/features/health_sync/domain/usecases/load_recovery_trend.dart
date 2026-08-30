import '../models/daily_recovery_snapshot.dart';
import '../repositories/health_metrics_repository.dart';
import 'load_latest_readiness.dart';

/// A small, sorted recent recovery trend for the compact "Recovery trend" card
/// on Progress (spec "Insights trend"). Like [LoadLatestReadinessUseCase] this
/// is a single lightweight read of the SAME pipeline the `/health` dashboard
/// uses — it never duplicates scoring logic and never disagrees with Health.
///
/// Every failure mode collapses to an empty list so Progress renders exactly as
/// today when recovery is absent: no permissions, no device data, an empty
/// window, or any thrown error all yield `[]`.
class LoadRecoveryTrendUseCase {
  const LoadRecoveryTrendUseCase(this._repository);

  final HealthMetricsRepository _repository;

  /// The trailing window the trend actually displays (last ~14 days).
  static const int displayWindowDays = 14;

  /// Snapshots (oldest → newest) that carry recovery signal, within the trailing
  /// [displayWindowDays]. We fetch [LoadLatestReadinessUseCase.baselineLeadDays]
  /// extra days before the display start purely to warm up baselines /
  /// chronic load; those lead days are trimmed off the returned trend so the
  /// card's semantics don't change. Best-effort and side-effect free; returns
  /// `[]` on any error or when no recovery data is available.
  Future<List<DailyRecoverySnapshot>> call() async {
    try {
      final end = DateTime.now();
      final displayStart = DateTime(
        end.year,
        end.month,
        end.day,
      ).subtract(const Duration(days: displayWindowDays));
      final fetchStart = displayStart.subtract(
        const Duration(days: LoadLatestReadinessUseCase.baselineLeadDays),
      );
      final snapshot = await _repository.loadSnapshot(
        start: fetchStart,
        end: DateTime(end.year, end.month, end.day),
      );
      final recovery =
          snapshot.recoverySnapshots
              .where((s) => s.hasRecoveryData)
              .where((s) => !s.date.isBefore(displayStart))
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));
      return recovery;
    } catch (_) {
      return const [];
    }
  }
}
