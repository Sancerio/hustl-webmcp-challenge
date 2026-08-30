import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/health_sync/domain/models/health_metric_sample.dart';
import 'package:hustl_app/features/health_sync/domain/models/nutrition_log_entry.dart';
import 'package:hustl_app/features/health_sync/domain/usecases/build_daily_health_summaries.dart';

void main() {
  final useCase = BuildDailyHealthSummariesUseCase();
  final date = DateTime(2024, 6, 10, 9);

  test('groups metrics and nutrition by calendar day', () {
    final metrics = [
      HealthMetricSample(
        type: HealthMetricType.weight,
        value: 82.0,
        unit: 'kg',
        startTime: date.subtract(const Duration(minutes: 10)),
        endTime: date.subtract(const Duration(minutes: 9)),
        source: 'scale',
      ),
      HealthMetricSample(
        type: HealthMetricType.height,
        value: 182.0,
        unit: 'cm',
        startTime: date.subtract(const Duration(minutes: 8)),
        endTime: date.subtract(const Duration(minutes: 7)),
        source: 'profile',
      ),
      HealthMetricSample(
        type: HealthMetricType.weight,
        value: 81.5,
        unit: 'kg',
        startTime: date.add(const Duration(hours: 12)),
        endTime: date.add(const Duration(hours: 12, minutes: 1)),
        source: 'scale',
      ),
    ];
    final nutrition = [
      NutritionLogEntry(
        timestamp: date.add(const Duration(hours: 1)),
        calories: 600,
        proteinGrams: 45,
        carbsGrams: 55,
        fatGrams: 20,
        waterMilliliters: 500,
        source: 'meal_log',
      ),
      NutritionLogEntry(
        timestamp: date.add(const Duration(hours: 13)),
        calories: 800,
        proteinGrams: 60,
        carbsGrams: 70,
        fatGrams: 30,
        fiberGrams: 12,
        sugarGrams: 15,
        source: 'meal_log',
      ),
    ];

    final summaries = useCase(metrics: metrics, nutritionEntries: nutrition);

    expect(summaries, hasLength(1));
    final summary = summaries.first;
    expect(summary.date, DateTime(2024, 6, 10));
    expect(summary.latestWeightKg, 81.5);
    expect(summary.latestHeightCm, 182.0);
    expect(summary.bodyMassIndex, closeTo(24.6, 0.1));
    expect(summary.macros.calories, 1400);
    expect(summary.macros.proteinGrams, 105);
    expect(summary.macros.carbsGrams, 125);
    expect(summary.macros.fatGrams, 50);
    expect(summary.macros.waterLiters, closeTo(0.5, 1e-3));
    expect(summary.macros.fiberGrams, 12);
    expect(summary.macros.sugarGrams, 15);
    expect(summary.macros.sodiumMilligrams, isNull);
  });

  test('returns empty list when no samples provided', () {
    final summaries = useCase(metrics: const [], nutritionEntries: const []);
    expect(summaries, isEmpty);
  });

  test('groups a UTC-normalized sample by its retained source-local day', () {
    final summaries = useCase(
      metrics: [
        HealthMetricSample(
          type: HealthMetricType.weight,
          value: 80,
          unit: 'kg',
          startTime: DateTime.utc(2026, 1, 2, 1),
          endTime: DateTime.utc(2026, 1, 2, 1),
          source: 'Travel scale',
          timezoneName: 'America/New_York',
          timezoneOffsetMinutes: -300,
        ),
      ],
      nutritionEntries: const [],
    );

    expect(summaries.single.date, DateTime(2026, 1, 1));
  });
}
