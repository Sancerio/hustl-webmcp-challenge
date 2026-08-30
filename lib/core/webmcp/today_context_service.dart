import '../../features/ai_proposals/domain/models/proposal_summary.dart';
import '../../features/ai_proposals/domain/repositories/proposals_repository.dart';
import '../../features/health_sync/domain/models/daily_recovery_snapshot.dart';
import '../../features/health_sync/domain/repositories/health_metrics_repository.dart';
import '../../features/health_sync/domain/usecases/load_latest_readiness.dart';
import '../../features/nutrition_tracker/domain/models/food_log_entry.dart';
import '../../features/nutrition_tracker/domain/models/nutrition_target_plan.dart';
import '../../features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import '../../features/nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';
import '../../features/workout_logging/domain/repositories/workout_repository.dart';
import 'today_context.dart';

class TodayContextService {
  const TodayContextService({
    required ReadOnlyWorkoutRepository workoutRepository,
    required HealthMetricsRepository healthRepository,
    required ReadOnlyFoodLogRepository foodLogRepository,
    required ReadOnlyNutritionTargetsRepository nutritionTargetsRepository,
    required ProposalsRepository proposalsRepository,
    DateTime Function()? clock,
  }) : _workoutRepository = workoutRepository,
       _healthRepository = healthRepository,
       _foodLogRepository = foodLogRepository,
       _nutritionTargetsRepository = nutritionTargetsRepository,
       _proposalsRepository = proposalsRepository,
       _clock = clock ?? DateTime.now;

  final ReadOnlyWorkoutRepository _workoutRepository;
  final HealthMetricsRepository _healthRepository;
  final ReadOnlyFoodLogRepository _foodLogRepository;
  final ReadOnlyNutritionTargetsRepository _nutritionTargetsRepository;
  final ProposalsRepository _proposalsRepository;
  final DateTime Function() _clock;

  Future<HustlTodayContext> load() async {
    final now = _clock().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final displayStart = today.subtract(
      const Duration(days: LoadLatestReadinessUseCase.displayWindowDays),
    );
    final healthStart = displayStart.subtract(
      const Duration(days: LoadLatestReadinessUseCase.baselineLeadDays),
    );

    // Start independent reads together. Each attempt contains its own failure,
    // so one unavailable pillar never suppresses the others.
    final workoutFuture = _attempt(
      () => _workoutRepository.getWorkoutSnapshotReadOnly(limit: 25),
    );
    final healthFuture = _attempt(
      () => _healthRepository.loadSnapshot(start: healthStart, end: today),
    );
    final foodFuture = _attempt(
      () => _foodLogRepository.getLogsForDateReadOnly(today),
    );
    final targetsFuture = _attempt(
      () => _nutritionTargetsRepository.getCurrentPlanReadOnly(today),
    );
    final proposalsFuture = _attempt(
      () => _proposalsRepository.listPending(limit: 50),
    );

    final workout = await workoutFuture;
    final health = await healthFuture;
    final food = await foodFuture;
    final targets = await targetsFuture;
    final proposals = await proposalsFuture;

    final unavailable = <String>[];
    final training = _trainingContext(workout);
    if (training.state == 'unavailable') unavailable.add('training');

    final recovery = _recoveryContext(health, displayStart);
    if (recovery.state == 'unavailable') unavailable.add('recovery');

    final nutrition = _nutritionContext(food, targets);
    if (!food.succeeded || !targets.succeeded) unavailable.add('nutrition');

    final coach = _coachContext(proposals);
    if (coach.state == 'unavailable') unavailable.add('coach');

    return HustlTodayContext(
      status: unavailable.isEmpty ? 'ready' : 'partial',
      asOf: _iso8601WithOffset(now),
      training: training,
      recovery: recovery,
      nutrition: nutrition,
      coach: coach,
      unavailableSections: unavailable,
    );
  }

  TrainingTodayContext _trainingContext(
    _Attempt<ReadOnlyWorkoutSnapshot> workout,
  ) {
    if (!workout.succeeded) {
      return const TrainingTodayContext(state: 'unavailable');
    }
    final activeSession = workout.value!.activeSession;
    if (activeSession != null) {
      return TrainingTodayContext(
        state: 'active',
        activeSessionId: activeSession.id,
        activeSessionName: activeSession.name,
      );
    }
    final completed =
        workout.value!.sessions.where((session) => session.isCompleted).toList()
          ..sort((a, b) => b.startTime.compareTo(a.startTime));
    if (completed.isEmpty) {
      return const TrainingTodayContext(state: 'ready_to_start');
    }
    final recommendation = completed.first;
    return TrainingTodayContext(
      state: 'repeat_recommended',
      recommendedSessionId: recommendation.id,
      recommendedSessionName: recommendation.name,
    );
  }

  RecoveryTodayContext _recoveryContext(
    _Attempt<HealthSnapshot> health,
    DateTime displayStart,
  ) {
    if (!health.succeeded) {
      return const RecoveryTodayContext(state: 'unavailable');
    }
    final snapshot = health.value!;
    final recent = snapshot.recoverySnapshots.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    DailyRecoverySnapshot? latest;
    for (final day in recent) {
      if (day.date.isBefore(displayStart)) break;
      if (day.hasRecoveryData) {
        latest = day;
        break;
      }
    }

    final availability = snapshot.signalAvailability;
    final state = latest != null
        ? (latest.isCalibrating ? 'calibrating' : 'available')
        : availability.hasAnySignal
        ? 'connected_no_data'
        : availability.providerAvailability.name == 'available'
        ? 'no_data'
        : 'disconnected';

    return RecoveryTodayContext(
      state: state,
      date: latest == null ? null : _localDate(latest.date),
      score: latest?.isCalibrating == true
          ? null
          : latest?.readinessScore ?? latest?.recoveryScore,
      flowBand: latest?.flowBand?.name,
      confidence: latest?.confidence?.name,
      sleepHours: latest?.sleepDurationMinutes == null
          ? null
          : latest!.sleepDurationMinutes! / 60,
      providerState: availability.providerAvailability.name,
      missingSignals: availability.missingSignals
          .map((signal) => signal.name)
          .toList(growable: false),
      baselineCoverageDays: latest?.baselineCoverageDays,
    );
  }

  NutritionTodayContext _nutritionContext(
    _Attempt<List<FoodLogEntry>> food,
    _Attempt<NutritionTargetPlan?> targets,
  ) {
    final entries = food.value;
    final plan = targets.value;
    return NutritionTodayContext(
      state: !food.succeeded
          ? 'unavailable'
          : entries!.isEmpty
          ? 'empty'
          : 'tracking',
      targetState: !targets.succeeded
          ? 'unavailable'
          : plan == null
          ? 'not_configured'
          : plan.needsSetup
          ? 'needs_setup'
          : 'configured',
      calories: _sum(entries, (entry) => entry.calories),
      proteinGrams: _sum(entries, (entry) => entry.proteinGrams),
      carbsGrams: _sum(entries, (entry) => entry.carbsGrams),
      fatGrams: _sum(entries, (entry) => entry.fatGrams),
      caloriesTarget: plan?.caloriesTarget,
      proteinTarget: plan?.proteinTarget,
      carbsTarget: plan?.carbsTarget,
      fatTarget: plan?.fatTarget,
    );
  }

  CoachTodayContext _coachContext(_Attempt<List<ProposalSummary>> proposals) {
    if (!proposals.succeeded) {
      return const CoachTodayContext(state: 'unavailable');
    }
    return CoachTodayContext(
      state: 'available',
      pendingProposalCount: proposals.value!.length,
    );
  }
}

double? _sum(
  List<FoodLogEntry>? entries,
  double Function(FoodLogEntry entry) value,
) => entries?.fold<double>(0, (sum, entry) => sum + value(entry));

Future<_Attempt<T>> _attempt<T>(Future<T> Function() read) async {
  try {
    return _Attempt.success(await read());
  } catch (_) {
    return _Attempt<T>.failure();
  }
}

class _Attempt<T> {
  const _Attempt.success(this.value) : succeeded = true;
  const _Attempt.failure() : succeeded = false, value = null;

  final bool succeeded;
  final T? value;
}

String _localDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String _iso8601WithOffset(DateTime value) {
  final local = value.toLocal();
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final absoluteMinutes = offset.inMinutes.abs();
  final hours = (absoluteMinutes ~/ 60).toString().padLeft(2, '0');
  final minutes = (absoluteMinutes % 60).toString().padLeft(2, '0');
  return '${local.toIso8601String()}$sign$hours:$minutes';
}
