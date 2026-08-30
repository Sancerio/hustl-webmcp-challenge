import '../../domain/models/nutrition_target_plan.dart';
import '../../domain/repositories/nutrition_targets_repository.dart';
import '../datasources/hustl_backend_nutrition_api.dart';

class NutritionTargetsRepositoryImpl
    implements NutritionTargetsRepository, ReadOnlyNutritionTargetsRepository {
  NutritionTargetsRepositoryImpl({required this.api});

  final HustlBackendNutritionApi api;

  @override
  Future<NutritionTargetPlan?> getCurrentPlan(
    DateTime date, {
    bool readOnly = false,
  }) async {
    try {
      final data = await api.getTargets(date, readOnly: readOnly);
      final planMap = data['plan'];
      if (planMap is Map) {
        final needsSetup = data['needsSetup'] == true;
        return NutritionTargetPlan.fromMap(
          Map<String, dynamic>.from(planMap)
            ..['needsSetup'] = needsSetup
            ..['profile'] = data['profile'],
        );
      }
      return null;
    } catch (_) {
      // Guest/offline-friendly: diary can still render without targets.
      return null;
    }
  }

  @override
  Future<NutritionTargetPlan?> getCurrentPlanReadOnly(DateTime date) async {
    final data = await api.getTargets(date, readOnly: true);
    return _planFrom(data);
  }

  NutritionTargetPlan? _planFrom(Map<String, dynamic> data) {
    final planMap = data['plan'];
    if (planMap is! Map) return null;
    return NutritionTargetPlan.fromMap(
      Map<String, dynamic>.from(planMap)
        ..['needsSetup'] = data['needsSetup'] == true
        ..['profile'] = data['profile'],
    );
  }

  @override
  Future<NutritionTargetPlan?> recalculatePlan(
    DateTime date, {
    String? mode,
    String? goal,
    double? ratePerWeek,
    Map<String, dynamic>? profile,
  }) async {
    final data = await api.recalcTargets(date, {
      if (mode != null) 'mode': mode,
      if (goal != null) 'goal': goal,
      if (ratePerWeek != null) 'ratePerWeek': ratePerWeek,
      if (profile != null) 'profile': profile,
    });
    final planMap = data['plan'];
    if (planMap is Map) {
      final needsSetup = data['needsSetup'] == true;
      return NutritionTargetPlan.fromMap(
        Map<String, dynamic>.from(planMap)
          ..['needsSetup'] = needsSetup
          ..['profile'] = data['profile'],
      );
    }
    return null;
  }

  @override
  Future<NutritionTargetPlan?> updatePlan(
    DateTime weekStart,
    Map<String, dynamic> patch,
  ) async {
    final data = await api.patchTargets(
      weekStart.toIso8601String().substring(0, 10),
      patch,
    );
    final planMap = data['plan'];
    if (planMap is Map) {
      final needsSetup = data['needsSetup'] == true;
      return NutritionTargetPlan.fromMap(
        Map<String, dynamic>.from(planMap)
          ..['needsSetup'] = needsSetup
          ..['profile'] = data['profile'],
      );
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> getWeightTrend(
    DateTime start,
    DateTime end,
  ) async {
    return api.getWeightTrend(start, end);
  }

  @override
  Future<void> addWeightSample(DateTime date, double weightKg) async {
    await api.postWeightMetric(date, weightKg);
  }

  @override
  Future<Map<String, dynamic>> getWeeklyAdherence(DateTime weekStart) async {
    return api.getWeeklyAdherence(weekStart);
  }

  @override
  Future<Map<String, dynamic>> getInsights(
    DateTime start,
    DateTime end, {
    bool momentumOptIn = false,
  }) async {
    return api.getInsights(start, end, momentumOptIn: momentumOptIn);
  }

  @override
  Future<String?> getCoachExplains(
    DateTime start,
    DateTime end, {
    bool momentumOptIn = false,
  }) async {
    try {
      return await api.getCoachExplains(
        start,
        end,
        momentumOptIn: momentumOptIn,
      );
    } catch (_) {
      // Purely additive — never let a narrative fetch failure surface.
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> getWeeklyCheckIn(DateTime date) async {
    return api.getWeeklyCheckIn(date);
  }

  @override
  Future<NutritionTargetPlan?> applyWeeklyCheckIn(DateTime date) async {
    final data = await api.postWeeklyCheckInAction(date, 'apply');
    final planMap = data['plan'];
    if (planMap is Map) {
      final needsSetup = data['needsSetup'] == true;
      return NutritionTargetPlan.fromMap(
        Map<String, dynamic>.from(planMap)..['needsSetup'] = needsSetup,
      );
    }
    return null;
  }

  @override
  Future<void> skipWeeklyCheckIn(DateTime date) async {
    await api.postWeeklyCheckInAction(date, 'skip');
  }
}
