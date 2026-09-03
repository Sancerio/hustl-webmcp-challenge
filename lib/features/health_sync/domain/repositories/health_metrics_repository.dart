import '../models/daily_health_summary.dart';
import '../models/daily_recovery_snapshot.dart';
import '../models/health_metric_sample.dart';
import '../models/nutrition_log_entry.dart';
import '../models/recovery_signal_availability.dart';

class HealthPermissionsStatus {
  const HealthPermissionsStatus({
    required this.hasPermissions,
    required this.isServiceAvailable,
    this.deniedPermanently = false,
    this.rawPermissionResult,
    this.assumedGranted = false,
  });

  final bool hasPermissions;
  final bool isServiceAvailable;
  final bool deniedPermanently;
  final bool? rawPermissionResult;
  final bool assumedGranted;
}

class HealthSnapshot {
  const HealthSnapshot({
    required this.rangeStart,
    required this.rangeEnd,
    required this.metrics,
    required this.nutritionEntries,
    required this.dailySummaries,
    required this.recoverySnapshots,
    required this.lastSyncedAt,
    this.warnings = const [],
    this.loadedFromCache = false,
    this.fallbackUsed = false,
    this.assumedPermissions = false,
    this.rawPermissionResult,
    this.signalAvailability = RecoverySignalAvailability.empty,
  });

  final DateTime rangeStart;
  final DateTime rangeEnd;
  final List<HealthMetricSample> metrics;
  final List<NutritionLogEntry> nutritionEntries;
  final List<DailyHealthSummary> dailySummaries;
  final List<DailyRecoverySnapshot> recoverySnapshots;
  final DateTime lastSyncedAt;
  final List<String> warnings;
  final bool loadedFromCache;
  final bool fallbackUsed;
  final bool assumedPermissions;
  final bool? rawPermissionResult;

  /// Which recovery signals are actually flowing (derived from real reads, not a
  /// permission boolean) plus provider reachability. Defaults to "no signals
  /// yet" so surfaces render exactly as today when absent.
  final RecoverySignalAvailability signalAvailability;
}

abstract class HealthMetricsRepository {
  Future<HealthPermissionsStatus> getPermissionsStatus();
  Future<HealthPermissionsStatus> requestPermissions();
  Future<HealthSnapshot> loadSnapshot({
    required DateTime start,
    required DateTime end,
    bool forceRefresh = false,
  });
  Future<void> clearCache();
  Future<void> resetPermissionDenialFlag();

  /// Reachability of the underlying provider (Android Health Connect status /
  /// iOS HealthKit). Drives the connect-flow install routing; never gates data.
  Future<HealthProviderAvailability> getProviderAvailability();

  /// Routes the user to install / update Health Connect (Android only). No-op on
  /// other platforms.
  Future<void> installHealthConnect();
}
