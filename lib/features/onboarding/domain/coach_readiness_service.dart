import '../../health_sync/domain/repositories/health_metrics_repository.dart';
import '../../nutrition_tracker/domain/repositories/food_log_repository.dart';
import '../../workout_logging/domain/repositories/workout_repository.dart';
import 'coach_readiness.dart';

/// A point-in-time read of how much the coach knows, plus the raw inputs used to
/// compute it. Drives the first-win "Building your plan" summary: the readiness
/// gauge ([readiness] + [filledCount]) and its supporting [note].
class CoachReadinessSnapshot {
  const CoachReadinessSnapshot({
    required this.readiness,
    required this.workouts,
    required this.meals,
    required this.healthConnected,
    required this.approvedProposals,
    required this.filledCount,
    required this.note,
  });

  /// Depth-weighted coach readiness in [0, 1].
  final double readiness;

  /// Completed workout sessions found in local history.
  final int workouts;

  /// Meals logged today (a cheap, honest-but-incomplete proxy for intake depth).
  final int meals;

  /// Whether the Health provider is connected (permissions granted).
  final bool healthConnected;

  /// Coach proposals the user has approved. There is no cheap client-side
  /// approved-count API yet, so this is currently always 0 (honest-but-
  /// incomplete) — and structurally 0 at first-win time anyway.
  final int approvedProposals;

  /// How many of the four pillars currently have ANY data (drives node visuals).
  final int filledCount;

  /// Short, honest guidance on what would sharpen the plan next.
  final String note;
}

/// Computes a [CoachReadinessSnapshot] from the real repositories. Every read is
/// wrapped in try/catch + a short timeout and degrades to 0/false on any
/// failure, so the first-win summary always renders and never blocks or throws.
class CoachReadinessService {
  CoachReadinessService({
    required WorkoutRepository workoutRepository,
    FoodLogRepository? foodLogRepository,
    HealthMetricsRepository? healthMetricsRepository,
  }) : _workoutRepository = workoutRepository,
       _foodLogRepository = foodLogRepository,
       _healthMetricsRepository = healthMetricsRepository;

  final WorkoutRepository _workoutRepository;
  final FoodLogRepository? _foodLogRepository;
  final HealthMetricsRepository? _healthMetricsRepository;

  static const Duration _readTimeout = Duration(seconds: 2);

  Future<CoachReadinessSnapshot> snapshot() async {
    final workouts = await _countCompletedWorkouts();
    final meals = await _countMealsToday();
    final healthConnected = await _readHealthConnected();
    // No cheap client-side count of APPROVED proposals exists, and a brand-new
    // user at first-win has approved none — so this stays 0 (honest).
    const approvedProposals = 0;

    final readiness = CoachReadiness.estimate(
      workouts: workouts,
      meals: meals,
      healthConnected: healthConnected,
      approvedProposals: approvedProposals,
    );

    final filledCount = <bool>[
      workouts > 0,
      meals > 0,
      healthConnected,
      approvedProposals > 0,
    ].where((filled) => filled).length;

    return CoachReadinessSnapshot(
      readiness: readiness,
      workouts: workouts,
      meals: meals,
      healthConnected: healthConnected,
      approvedProposals: approvedProposals,
      filledCount: filledCount,
      note: _noteFor(meals: meals, healthConnected: healthConnected),
    );
  }

  Future<int> _countCompletedWorkouts() async {
    try {
      final sessions = await _workoutRepository
          .getWorkoutSessions(limit: 50)
          .timeout(_readTimeout);
      return sessions.where((s) => s.isCompleted).length;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _countMealsToday() async {
    final repo = _foodLogRepository;
    if (repo == null) return 0;
    try {
      final logs = await repo
          .getLogsForDate(DateTime.now())
          .timeout(_readTimeout);
      return logs.length;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> _readHealthConnected() async {
    final repo = _healthMetricsRepository;
    if (repo == null) return false;
    try {
      final status = await repo.getPermissionsStatus().timeout(_readTimeout);
      return status.hasPermissions;
    } catch (_) {
      return false;
    }
  }

  String _noteFor({required int meals, required bool healthConnected}) {
    final missing = <String>[
      if (meals <= 0) 'log meals',
      if (!healthConnected) 'connect Health',
    ];
    if (missing.isEmpty) {
      return 'Your coach has what it needs — keep logging to sharpen it.';
    }
    final joined = missing.join(' + ');
    final capitalized = joined[0].toUpperCase() + joined.substring(1);
    return '$capitalized to sharpen your plan.';
  }
}
