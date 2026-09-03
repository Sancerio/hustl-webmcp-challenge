import 'dart:math' as math;

import '../../features/nutrition_tracker/domain/models/nutrition_target_plan.dart';
import '../../features/nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';
import 'demo_persona.dart';

/// Deterministic in-memory [NutritionTargetsRepository] for demo mode.
///
/// Serves Alex's targets (2,200 kcal · P 160 / C 220 / F 70 g), a 90-day
/// weight journey (84.2 -> 81.6 kg, noisy scatter over a smooth downward
/// trend), and the insight / adherence / check-in blobs in the exact map
/// shapes the diary, insights and weight screens parse. Every value is a pure
/// function of the [anchor] date, so screenshots are reproducible (spec §10).
class DemoNutritionTargetsRepository
    implements NutritionTargetsRepository, ReadOnlyNutritionTargetsRepository {
  DemoNutritionTargetsRepository({required DateTime anchor})
    : _today = DateTime(anchor.year, anchor.month, anchor.day),
      _currentCaloriesTarget = caloriesTarget,
      _currentProteinTarget = proteinTarget,
      _currentCarbsTarget = carbsTarget,
      _currentFatTarget = fatTarget;

  final DateTime _today;
  double _currentCaloriesTarget;
  double _currentProteinTarget;
  double _currentCarbsTarget;
  double _currentFatTarget;

  static const int weightSeriesDays = 90;
  static const double caloriesTarget = 2200;
  static const double proteinTarget = 160;
  static const double carbsTarget = 220;
  static const double fatTarget = 70;

  String _dayKey(DateTime date) => DateTime(
    date.year,
    date.month,
    date.day,
  ).toIso8601String().substring(0, 10);

  /// Smooth body-weight trend (kg) for [dayFromStart] in `[0, days-1]`,
  /// interpolating linearly from the start weight to the end weight.
  double _trendKg(int dayFromStart, int days) {
    final progress = days <= 1 ? 1.0 : dayFromStart / (days - 1);
    return DemoPersona.weightStartKg +
        (DemoPersona.weightEndKg - DemoPersona.weightStartKg) * progress;
  }

  /// Noisy raw scale reading around the trend — deterministic sinusoid, no RNG.
  double _scaleKg(int dayFromStart, int days) {
    final trend = _trendKg(dayFromStart, days);
    final noise =
        math.sin(dayFromStart * 0.7) * 0.34 +
        math.cos(dayFromStart * 1.9) * 0.22 +
        math.sin(dayFromStart * 0.31) * 0.16;
    return double.parse((trend + noise).toStringAsFixed(2));
  }

  @override
  Future<NutritionTargetPlan?> getCurrentPlan(
    DateTime date, {
    bool readOnly = false,
  }) async {
    final weekStart = _today.subtract(Duration(days: _today.weekday - 1));
    return NutritionTargetPlan(
      weekStart: weekStart,
      mode: 'auto',
      goal: 'lose',
      ratePerWeek: 0.35,
      caloriesTarget: _currentCaloriesTarget,
      proteinTarget: _currentProteinTarget,
      carbsTarget: _currentCarbsTarget,
      fatTarget: _currentFatTarget,
      rationale:
          'Coached cut at ~0.35 kg/week with protein held high to retain muscle.',
    );
  }

  @override
  Future<NutritionTargetPlan?> getCurrentPlanReadOnly(DateTime date) =>
      getCurrentPlan(date, readOnly: true);

  @override
  Future<NutritionTargetPlan?> recalculatePlan(
    DateTime date, {
    String? mode,
    String? goal,
    double? ratePerWeek,
    Map<String, dynamic>? profile,
  }) => getCurrentPlan(date);

  @override
  Future<NutritionTargetPlan?> updatePlan(
    DateTime weekStart,
    Map<String, dynamic> patch,
  ) async {
    _currentCaloriesTarget =
        (patch['caloriesTarget'] as num?)?.toDouble() ?? _currentCaloriesTarget;
    _currentProteinTarget =
        (patch['proteinTarget'] as num?)?.toDouble() ?? _currentProteinTarget;
    _currentCarbsTarget =
        (patch['carbsTarget'] as num?)?.toDouble() ?? _currentCarbsTarget;
    _currentFatTarget =
        (patch['fatTarget'] as num?)?.toDouble() ?? _currentFatTarget;
    return getCurrentPlan(weekStart);
  }

  /// Applies the four reviewed values atomically in the in-memory evaluator.
  void applyTargets({
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
  }) {
    _currentCaloriesTarget = calories;
    _currentProteinTarget = protein;
    _currentCarbsTarget = carbs;
    _currentFatTarget = fat;
  }

  @override
  Future<Map<String, dynamic>> getWeightTrend(
    DateTime start,
    DateTime end,
  ) async {
    // Anchor the 90-day journey on `end` (today) regardless of requested range
    // so the latest reading is always "today".
    final scale = <Map<String, dynamic>>[];
    final trend = <Map<String, dynamic>>[];
    final sourcesByDate = <String, dynamic>{};
    for (var i = 0; i < weightSeriesDays; i++) {
      final dayFromStart = i;
      final date = _today.subtract(
        Duration(days: weightSeriesDays - 1 - dayFromStart),
      );
      // Log a weigh-in roughly every other day for a realistic scatter.
      if (dayFromStart.isEven || dayFromStart == weightSeriesDays - 1) {
        final key = _dayKey(date);
        scale.add({
          'date': key,
          'weightKg': _scaleKg(dayFromStart, weightSeriesDays),
          'source': 'self',
        });
        sourcesByDate[key] = const ['Manual'];
      }
      trend.add({
        'date': _dayKey(date),
        'trendKg': double.parse(
          _trendKg(dayFromStart, weightSeriesDays).toStringAsFixed(2),
        ),
      });
    }
    final latest = scale.isNotEmpty ? scale.last : null;
    return {
      'scale': scale,
      'trend': trend,
      'sourcesByDate': sourcesByDate,
      'healthSources': const <dynamic>[],
      'goalType': 'lose',
      'latest': latest,
      'hasWeightToday': latest != null && latest['date'] == _dayKey(_today),
    };
  }

  @override
  Future<void> addWeightSample(DateTime date, double weightKg) async {}

  @override
  Future<Map<String, dynamic>> getWeeklyAdherence(DateTime weekStart) async {
    // Seven daily adherence scores (0..1) with a strong, consistent week.
    const days = [0.92, 0.88, 0.95, 0.83, 0.9, 0.97, 0.86];
    final weeklyScore = days.reduce((a, b) => a + b) / days.length;
    return {
      'weeklyScore': double.parse(weeklyScore.toStringAsFixed(3)),
      'days': [
        for (final s in days) {'score': s},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getInsights(
    DateTime start,
    DateTime end, {
    bool momentumOptIn = false,
  }) async {
    // 14-day energy-balance window ending at `end`.
    final days = <Map<String, dynamic>>[];
    var intakeSum = 0.0;
    var targetSum = 0.0;
    var tdeeSum = 0.0;
    const window = 14;
    for (var i = 0; i < window; i++) {
      final date = _today.subtract(Duration(days: window - 1 - i));
      final intake = 2120 + math.sin(i * 0.8) * 180 + math.cos(i * 0.4) * 70;
      const target = caloriesTarget;
      final tdee = 2560 + math.sin(i * 0.5) * 90;
      intakeSum += intake;
      targetSum += target;
      tdeeSum += tdee;
      days.add({
        'date': _dayKey(date),
        'intakeCalories': double.parse(intake.toStringAsFixed(0)),
        'targetCalories': target,
        'tdeeKcal': double.parse(tdee.toStringAsFixed(0)),
      });
    }
    final avgIntake = intakeSum / window;
    final avgTarget = targetSum / window;
    final avgTdee = tdeeSum / window;
    return {
      'averages': {
        'calories': double.parse(avgIntake.toStringAsFixed(0)),
        'proteinGrams': 142.0,
        'carbsGrams': 198.0,
        'fatGrams': 63.0,
      },
      'flags': const [
        {
          'key': 'protein_on_track',
          'message': 'Protein is consistently near target — great for the cut.',
        },
      ],
      'energyBalance': {
        'days': days,
        'averages': {
          'intakeCalories': double.parse(avgIntake.toStringAsFixed(0)),
          'targetCalories': double.parse(avgTarget.toStringAsFixed(0)),
          'tdeeKcal': double.parse(avgTdee.toStringAsFixed(0)),
          'diffVsTarget': double.parse(
            (avgIntake - avgTarget).toStringAsFixed(0),
          ),
          'diffVsTdee': double.parse((avgIntake - avgTdee).toStringAsFixed(0)),
        },
      },
      'weight': {'observedDeltaKg': -0.78, 'expectedDeltaKg': -0.7},
    };
  }

  @override
  Future<String?> getCoachExplains(
    DateTime start,
    DateTime end, {
    bool momentumOptIn = false,
  }) async {
    // Demo mode never calls the backend LLM — the deterministic cards stand
    // alone, exactly as they do in prod with the server flag off.
    return null;
  }

  @override
  Future<Map<String, dynamic>> getWeeklyCheckIn(DateTime date) async {
    return {
      'deltas': const {
        'calories': -40.0,
        'protein': 0.0,
        'carbs': -10.0,
        'fat': 0.0,
      },
      'why': const {
        'capApplied': false,
        'tdeeKcal': 2560.0,
        'windowDays': 14,
        'confidence': 0.82,
      },
      'coverage': const {'weighInDays': 6, 'daysWithCaloriesLogged': 7},
    };
  }

  @override
  Future<NutritionTargetPlan?> applyWeeklyCheckIn(DateTime date) =>
      getCurrentPlan(date);

  @override
  Future<void> skipWeeklyCheckIn(DateTime date) async {}
}
