import 'package:collection/collection.dart';
import '../models/daily_health_summary.dart';
import '../models/health_metric_sample.dart';
import '../models/nutrition_log_entry.dart';

class BuildDailyHealthSummariesUseCase {
  List<DailyHealthSummary> call({
    required List<HealthMetricSample> metrics,
    required List<NutritionLogEntry> nutritionEntries,
  }) {
    final groupedMetrics = groupBy<HealthMetricSample, DateTime>(metrics, (
      sample,
    ) {
      final localEnd = sample.localEndTime;
      return DateTime(localEnd.year, localEnd.month, localEnd.day);
    });
    final groupedNutrition = groupBy<NutritionLogEntry, DateTime>(
      nutritionEntries,
      (entry) => DateTime(
        entry.timestamp.year,
        entry.timestamp.month,
        entry.timestamp.day,
      ),
    );

    final allDates = <DateTime>{
      ...groupedMetrics.keys,
      ...groupedNutrition.keys,
    };

    final summaries = allDates.map((date) {
      final metricSamples = List<HealthMetricSample>.from(
        groupedMetrics[date] ?? const [],
      );
      final nutritionLogs = List<NutritionLogEntry>.from(
        groupedNutrition[date] ?? const [],
      );

      metricSamples.sort((a, b) => a.endTime.compareTo(b.endTime));
      nutritionLogs.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      HealthMetricSample? latestOf(HealthMetricType type) {
        return metricSamples.reversed.firstWhereOrNull((m) => m.type == type);
      }

      final latestWeight = latestOf(
        HealthMetricType.weight,
      )?.valueInPreferredUnit;
      final latestHeight = latestOf(
        HealthMetricType.height,
      )?.valueInPreferredUnit;

      double? bmi;
      if (latestWeight != null && latestHeight != null && latestHeight > 0) {
        final meters = latestHeight / 100.0;
        bmi = meters == 0 ? null : latestWeight / (meters * meters);
      }

      double totalCalories = 0;
      double totalProtein = 0;
      double totalCarbs = 0;
      double totalFat = 0;
      double? totalWater;
      double? totalFiber;
      double? totalSugar;
      double? totalSodium;

      for (final entry in nutritionLogs) {
        totalCalories += entry.calories;
        totalProtein += entry.proteinGrams;
        totalCarbs += entry.carbsGrams;
        totalFat += entry.fatGrams;
        if (entry.waterMilliliters != null) {
          totalWater = (totalWater ?? 0) + entry.waterMilliliters! / 1000;
        }
        if (entry.fiberGrams != null) {
          totalFiber = (totalFiber ?? 0) + entry.fiberGrams!;
        }
        if (entry.sugarGrams != null) {
          totalSugar = (totalSugar ?? 0) + entry.sugarGrams!;
        }
        if (entry.sodiumMilligrams != null) {
          totalSodium = (totalSodium ?? 0) + entry.sodiumMilligrams!;
        }
      }

      return DailyHealthSummary(
        date: date,
        latestWeightKg: latestWeight,
        latestHeightCm: latestHeight,
        bodyMassIndex: bmi,
        bodyFatPercentage: latestOf(
          HealthMetricType.bodyFatPercentage,
        )?.valueInPreferredUnit,
        basalMetabolicRate: latestOf(
          HealthMetricType.basalMetabolicRate,
        )?.valueInPreferredUnit,
        metrics: metricSamples,
        nutritionLogs: nutritionLogs,
        macros: DailyMacroBreakdown(
          calories: totalCalories,
          proteinGrams: totalProtein,
          carbsGrams: totalCarbs,
          fatGrams: totalFat,
          waterLiters: totalWater,
          fiberGrams: totalFiber,
          sugarGrams: totalSugar,
          sodiumMilligrams: totalSodium,
        ),
      );
    }).toList()..sort((a, b) => a.date.compareTo(b.date));

    return summaries;
  }
}
