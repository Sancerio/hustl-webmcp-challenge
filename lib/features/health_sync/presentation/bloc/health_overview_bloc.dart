import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../domain/models/daily_health_summary.dart';
import '../../domain/models/daily_recovery_snapshot.dart';
import '../../domain/models/health_metric_sample.dart';
import '../../domain/models/recovery_signal_availability.dart';
import '../../domain/repositories/health_metrics_repository.dart';
import '../../domain/usecases/derive_health_insights.dart';
import '../../domain/usecases/load_latest_readiness.dart';

part 'health_overview_event.dart';
part 'health_overview_state.dart';

class HealthOverviewBloc
    extends Bloc<HealthOverviewEvent, HealthOverviewState> {
  HealthOverviewBloc(
    this._repository, {
    DeriveHealthInsightsUseCase? deriveInsights,
  }) : _deriveInsights = deriveInsights ?? DeriveHealthInsightsUseCase(),
       super(HealthOverviewState.initial()) {
    on<HealthOverviewStarted>(_onStarted);
    on<HealthOverviewDateRangeChanged>(_onRangeChanged);
    on<HealthOverviewRefreshed>(_onRefreshed);
  }

  final HealthMetricsRepository _repository;
  final DeriveHealthInsightsUseCase _deriveInsights;

  Future<void> _onStarted(
    HealthOverviewStarted event,
    Emitter<HealthOverviewState> emit,
  ) async {
    await _loadData(
      emit,
      rangeStart: state.rangeStart,
      rangeEnd: state.rangeEnd,
      forceRefresh: event.forceRefresh,
    );
  }

  Future<void> _onRangeChanged(
    HealthOverviewDateRangeChanged event,
    Emitter<HealthOverviewState> emit,
  ) async {
    await _loadData(
      emit,
      rangeStart: event.start,
      rangeEnd: event.end,
      forceRefresh: event.forceRefresh,
    );
  }

  Future<void> _onRefreshed(
    HealthOverviewRefreshed event,
    Emitter<HealthOverviewState> emit,
  ) async {
    await _loadData(
      emit,
      rangeStart: state.rangeStart,
      rangeEnd: state.rangeEnd,
      forceRefresh: true,
    );
  }

  Future<void> _loadData(
    Emitter<HealthOverviewState> emit, {
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required bool forceRefresh,
  }) async {
    final hasVisibleData =
        state.status == HealthOverviewStatus.ready && state.hasData;

    if (hasVisibleData) {
      // Refetch: keep everything on screen; just mark the refresh in flight.
      emit(
        state.copyWith(
          isRefreshing: true,
          refreshError: null,
          errorMessage: null,
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
        ),
      );
    } else {
      emit(
        state.copyWith(
          status: HealthOverviewStatus.loading,
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
          errorMessage: null,
          syncWarnings: const [],
          recoverySnapshots: const [],
          metricCounts: const {},
          nutritionEntryCount: 0,
          fallbackUsed: false,
          loadedFromCache: false,
          signalAvailability: RecoverySignalAvailability.empty,
          isRefreshing: false,
          refreshError: null,
        ),
      );
    }

    try {
      // Fetch a lead of extra history BEFORE the displayed range so the recovery
      // algorithm's baselines (28d) and chronic load (42d) are computed on real
      // history instead of the display window alone. Everything below is then
      // trimmed back to [displayStart]..[displayEnd] so charts/lists/counts show
      // exactly the same days as before — the lead exists purely to warm up the
      // scoring behind them.
      final displayStart = DateTime(
        rangeStart.year,
        rangeStart.month,
        rangeStart.day,
      );
      final displayEnd = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
      final displayEndInclusive = DateTime(
        rangeEnd.year,
        rangeEnd.month,
        rangeEnd.day,
        23,
        59,
        59,
        999,
      );
      final snapshot = await _repository.loadSnapshot(
        start: displayStart.subtract(
          const Duration(days: LoadLatestReadinessUseCase.baselineLeadDays),
        ),
        end: rangeEnd,
        forceRefresh: forceRefresh,
      );

      final summaries = snapshot.dailySummaries
          .where(
            (summary) =>
                !summary.date.isBefore(displayStart) &&
                !summary.date.isAfter(displayEnd),
          )
          .toList();

      summaries.sort((a, b) => a.date.compareTo(b.date));

      final latest = summaries.isEmpty ? null : summaries.last;
      final recoverySnapshots =
          snapshot.recoverySnapshots
              .where(
                (daily) =>
                    !daily.date.isBefore(displayStart) &&
                    !daily.date.isAfter(displayEnd),
              )
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));

      // Trim raw samples back to the display window too so metric counts and the
      // latest-body-measurement fallbacks reflect exactly the displayed days,
      // not the wider fetch lead.
      final metrics = snapshot.metrics
          .where(
            (m) =>
                !m.startTime.isBefore(displayStart) &&
                !m.startTime.isAfter(displayEndInclusive),
          )
          .toList();

      final insights = _deriveInsights(
        summaries,
        recoverySnapshots: recoverySnapshots,
      );
      final weightTrend = _calculateWeeklyWeightChange(summaries);
      final metricCounts = <HealthMetricType, int>{};
      for (final metric in metrics) {
        metricCounts.update(
          metric.type,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }

      double? latestWeight = latest?.latestWeightKg;
      if (latestWeight == null) {
        final weights = metrics
            .where((m) => m.type == HealthMetricType.weight)
            .toList();
        if (weights.isNotEmpty) {
          latestWeight = weights.last.valueInPreferredUnit;
        }
      }

      double? latestHeight = latest?.latestHeightCm;
      if (latestHeight == null) {
        final heights = metrics
            .where((m) => m.type == HealthMetricType.height)
            .toList();
        if (heights.isNotEmpty) {
          latestHeight = heights.last.valueInPreferredUnit;
        }
      }

      double? latestBmi = latest?.bodyMassIndex;
      if (latestBmi == null) {
        final bmis = metrics
            .where((m) => m.type == HealthMetricType.bodyMassIndex)
            .toList();
        if (bmis.isNotEmpty) {
          latestBmi = bmis.last.valueInPreferredUnit;
        } else if (latestWeight != null && latestHeight != null) {
          final meters = latestHeight / 100.0;
          if (meters > 0) {
            latestBmi = latestWeight / (meters * meters);
          }
        }
      }

      emit(
        state.copyWith(
          status: summaries.isEmpty
              ? HealthOverviewStatus.empty
              : HealthOverviewStatus.ready,
          summaries: summaries,
          recoverySnapshots: recoverySnapshots,
          insights: insights,
          syncWarnings: snapshot.warnings,
          latestWeightKg: latestWeight,
          latestHeightCm: latestHeight,
          latestBmi: latestBmi,
          weeklyWeightChangeKg: weightTrend,
          lastSyncedAt: snapshot.lastSyncedAt,
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
          metricCounts: metricCounts,
          nutritionEntryCount: snapshot.nutritionEntries
              .where(
                (n) =>
                    !n.timestamp.isBefore(displayStart) &&
                    !n.timestamp.isAfter(displayEndInclusive),
              )
              .length,
          fallbackUsed: snapshot.fallbackUsed,
          loadedFromCache: snapshot.loadedFromCache,
          assumedPermissions: snapshot.assumedPermissions,
          rawPermissionResult: snapshot.rawPermissionResult,
          signalAvailability: snapshot.signalAvailability,
          isRefreshing: false,
          refreshError: null,
        ),
      );
    } catch (error) {
      if (hasVisibleData) {
        // A transient refresh failure must not destroy the rendered dashboard:
        // keep the stale data and surface a quiet, kind snack instead.
        emit(
          state.copyWith(
            isRefreshing: false,
            refreshError:
                "Couldn't refresh your health data. Showing your last synced view.",
          ),
        );
      } else {
        emit(
          state.copyWith(
            status: HealthOverviewStatus.error,
            errorMessage: 'Failed to load health data',
            isRefreshing: false,
          ),
        );
      }
    }
  }

  double? _calculateWeeklyWeightChange(List<DailyHealthSummary> summaries) {
    if (summaries.length < 2) return null;
    final weights = summaries
        .map((summary) => summary.latestWeightKg)
        .whereType<double>()
        .toList();
    if (weights.length < 2) return null;
    final last = weights.last;
    final previous = weights.length > 6
        ? weights[weights.length - 7]
        : weights.first;
    return last - previous;
  }
}
