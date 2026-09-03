import '../models/nutrition_target_plan.dart';

/// Strict target lookup that never creates/carries a plan and propagates
/// failures so unavailable data remains distinct from no configured plan.
abstract interface class ReadOnlyNutritionTargetsRepository {
  Future<NutritionTargetPlan?> getCurrentPlanReadOnly(DateTime date);
}

abstract class NutritionTargetsRepository {
  /// Fetch the plan for [date]'s week. [readOnly] does a strictly read-only
  /// lookup (returns null if no plan exists) without creating/carrying one over;
  /// use it where a read must not mutate state (e.g. previewing a proposal).
  Future<NutritionTargetPlan?> getCurrentPlan(
    DateTime date, {
    bool readOnly = false,
  });
  Future<NutritionTargetPlan?> recalculatePlan(
    DateTime date, {
    String? mode,
    String? goal,
    double? ratePerWeek,
    Map<String, dynamic>? profile,
  });
  Future<NutritionTargetPlan?> updatePlan(
    DateTime weekStart,
    Map<String, dynamic> patch,
  );
  Future<Map<String, dynamic>> getWeightTrend(DateTime start, DateTime end);
  Future<void> addWeightSample(DateTime date, double weightKg);
  Future<Map<String, dynamic>> getWeeklyAdherence(DateTime weekStart);
  Future<Map<String, dynamic>> getInsights(
    DateTime start,
    DateTime end, {
    bool momentumOptIn = false,
  });

  /// Optional "Coach Explains" narrative (item 6), fetched lazily and only when
  /// the user has opted in. Returns null when off / gated / on any error.
  Future<String?> getCoachExplains(
    DateTime start,
    DateTime end, {
    bool momentumOptIn = false,
  });
  Future<Map<String, dynamic>> getWeeklyCheckIn(DateTime date);
  Future<NutritionTargetPlan?> applyWeeklyCheckIn(DateTime date);
  Future<void> skipWeeklyCheckIn(DateTime date);
}
