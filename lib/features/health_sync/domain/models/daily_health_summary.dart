import 'package:equatable/equatable.dart';
import 'health_metric_sample.dart';
import 'nutrition_log_entry.dart';

class DailyMacroBreakdown extends Equatable {
  const DailyMacroBreakdown({
    required this.calories,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
    this.waterLiters,
    this.fiberGrams,
    this.sugarGrams,
    this.sodiumMilligrams,
  });

  final double calories;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;
  final double? waterLiters;
  final double? fiberGrams;
  final double? sugarGrams;
  final double? sodiumMilligrams;

  double get proteinPercent =>
      calories == 0 ? 0 : (proteinGrams * 4 / calories).clamp(0, 1);
  double get carbPercent =>
      calories == 0 ? 0 : (carbsGrams * 4 / calories).clamp(0, 1);
  double get fatPercent =>
      calories == 0 ? 0 : (fatGrams * 9 / calories).clamp(0, 1);

  @override
  List<Object?> get props => [
    calories,
    proteinGrams,
    carbsGrams,
    fatGrams,
    waterLiters,
    fiberGrams,
    sugarGrams,
    sodiumMilligrams,
  ];
}

class DailyHealthSummary extends Equatable {
  const DailyHealthSummary({
    required this.date,
    this.latestWeightKg,
    this.latestHeightCm,
    this.bodyMassIndex,
    this.bodyFatPercentage,
    this.basalMetabolicRate,
    required this.metrics,
    required this.nutritionLogs,
    required this.macros,
  });

  final DateTime date;
  final double? latestWeightKg;
  final double? latestHeightCm;
  final double? bodyMassIndex;
  final double? bodyFatPercentage;
  final double? basalMetabolicRate;
  final List<HealthMetricSample> metrics;
  final List<NutritionLogEntry> nutritionLogs;
  final DailyMacroBreakdown macros;

  bool get hasNutritionData => nutritionLogs.isNotEmpty || macros.calories > 0;

  @override
  List<Object?> get props => [
    date,
    latestWeightKg,
    latestHeightCm,
    bodyMassIndex,
    bodyFatPercentage,
    basalMetabolicRate,
    metrics,
    nutritionLogs,
    macros,
  ];
}
