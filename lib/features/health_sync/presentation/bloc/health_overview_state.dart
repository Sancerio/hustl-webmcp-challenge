part of 'health_overview_bloc.dart';

enum HealthOverviewStatus { initial, loading, ready, empty, error }

const _kNoValue = Object();

class HealthOverviewState extends Equatable {
  const HealthOverviewState({
    required this.status,
    required this.rangeStart,
    required this.rangeEnd,
    required this.summaries,
    required this.recoverySnapshots,
    required this.insights,
    required this.syncWarnings,
    this.latestWeightKg,
    this.latestHeightCm,
    this.latestBmi,
    this.weeklyWeightChangeKg,
    this.lastSyncedAt,
    this.errorMessage,
    this.metricCounts = const {},
    this.nutritionEntryCount = 0,
    this.fallbackUsed = false,
    this.loadedFromCache = false,
    this.assumedPermissions = false,
    this.rawPermissionResult,
    this.signalAvailability = RecoverySignalAvailability.empty,
    this.isRefreshing = false,
    this.refreshError,
  });

  factory HealthOverviewState.initial() {
    final end = DateTime.now();
    final start = end.subtract(const Duration(days: 14));
    return HealthOverviewState(
      status: HealthOverviewStatus.initial,
      rangeStart: DateTime(start.year, start.month, start.day),
      rangeEnd: DateTime(end.year, end.month, end.day),
      summaries: const [],
      recoverySnapshots: const [],
      insights: const [],
      syncWarnings: const [],
      metricCounts: const {},
    );
  }

  final HealthOverviewStatus status;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final List<DailyHealthSummary> summaries;
  final List<DailyRecoverySnapshot> recoverySnapshots;
  final List<HealthInsight> insights;
  final List<String> syncWarnings;
  final double? latestWeightKg;
  final double? latestHeightCm;
  final double? latestBmi;
  final double? weeklyWeightChangeKg;
  final DateTime? lastSyncedAt;
  final String? errorMessage;
  final Map<HealthMetricType, int> metricCounts;
  final int nutritionEntryCount;
  final bool fallbackUsed;
  final bool loadedFromCache;
  final bool assumedPermissions;
  final bool? rawPermissionResult;

  /// Which recovery signals are actually flowing (data-driven) plus provider
  /// reachability. Powers the targeted re-grant prompt; defaults to empty so
  /// surfaces render exactly as today when absent.
  final RecoverySignalAvailability signalAvailability;

  /// True while a refetch (pull-to-refresh, resume, date-range change) is in
  /// flight over an already-rendered dashboard. `status` stays `ready` and
  /// the previous data stays visible the whole time.
  final bool isRefreshing;

  /// One-shot message set only when a refetch fails while good data is on
  /// screen; the dashboard stays rendered and a quiet snack surfaces this
  /// instead of a full-screen error.
  final String? refreshError;

  bool get hasData => summaries.isNotEmpty;

  HealthOverviewState copyWith({
    HealthOverviewStatus? status,
    DateTime? rangeStart,
    DateTime? rangeEnd,
    List<DailyHealthSummary>? summaries,
    List<DailyRecoverySnapshot>? recoverySnapshots,
    List<HealthInsight>? insights,
    List<String>? syncWarnings,
    Object? latestWeightKg = _kNoValue,
    Object? latestHeightCm = _kNoValue,
    Object? latestBmi = _kNoValue,
    Object? weeklyWeightChangeKg = _kNoValue,
    Object? lastSyncedAt = _kNoValue,
    Object? errorMessage = _kNoValue,
    Map<HealthMetricType, int>? metricCounts,
    int? nutritionEntryCount,
    bool? fallbackUsed,
    bool? loadedFromCache,
    bool? assumedPermissions,
    Object? rawPermissionResult = _kNoValue,
    RecoverySignalAvailability? signalAvailability,
    bool? isRefreshing,
    Object? refreshError = _kNoValue,
  }) {
    return HealthOverviewState(
      status: status ?? this.status,
      rangeStart: rangeStart ?? this.rangeStart,
      rangeEnd: rangeEnd ?? this.rangeEnd,
      summaries: summaries ?? this.summaries,
      recoverySnapshots: recoverySnapshots ?? this.recoverySnapshots,
      insights: insights ?? this.insights,
      syncWarnings: syncWarnings ?? this.syncWarnings,
      latestWeightKg: latestWeightKg == _kNoValue
          ? this.latestWeightKg
          : latestWeightKg as double?,
      latestHeightCm: latestHeightCm == _kNoValue
          ? this.latestHeightCm
          : latestHeightCm as double?,
      latestBmi: latestBmi == _kNoValue ? this.latestBmi : latestBmi as double?,
      weeklyWeightChangeKg: weeklyWeightChangeKg == _kNoValue
          ? this.weeklyWeightChangeKg
          : weeklyWeightChangeKg as double?,
      lastSyncedAt: lastSyncedAt == _kNoValue
          ? this.lastSyncedAt
          : lastSyncedAt as DateTime?,
      errorMessage: errorMessage == _kNoValue
          ? this.errorMessage
          : errorMessage as String?,
      metricCounts: metricCounts ?? this.metricCounts,
      nutritionEntryCount: nutritionEntryCount ?? this.nutritionEntryCount,
      fallbackUsed: fallbackUsed ?? this.fallbackUsed,
      loadedFromCache: loadedFromCache ?? this.loadedFromCache,
      assumedPermissions: assumedPermissions ?? this.assumedPermissions,
      rawPermissionResult: rawPermissionResult == _kNoValue
          ? this.rawPermissionResult
          : rawPermissionResult as bool?,
      signalAvailability: signalAvailability ?? this.signalAvailability,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      refreshError: refreshError == _kNoValue
          ? this.refreshError
          : refreshError as String?,
    );
  }

  @override
  List<Object?> get props => [
    status,
    rangeStart,
    rangeEnd,
    summaries,
    recoverySnapshots,
    insights,
    syncWarnings,
    latestWeightKg,
    latestHeightCm,
    latestBmi,
    weeklyWeightChangeKg,
    lastSyncedAt,
    errorMessage,
    metricCounts,
    nutritionEntryCount,
    fallbackUsed,
    loadedFromCache,
    assumedPermissions,
    rawPermissionResult,
    signalAvailability,
    isRefreshing,
    refreshError,
  ];
}
