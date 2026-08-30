import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hustl_app/core/services/nutrition_widget_service.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/nutrition_target_plan.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';

class _MockFoodLogRepository extends Mock implements FoodLogRepository {}

class _MockNutritionTargetsRepository extends Mock
    implements NutritionTargetsRepository {}

void main() {
  late _MockFoodLogRepository foodLogRepository;
  late _MockNutritionTargetsRepository targetsRepository;
  late NutritionWidgetService service;

  final testDate = DateTime(2026, 2, 7, 15, 30);
  final normalizedDate = DateTime(2026, 2, 7);

  setUp(() {
    foodLogRepository = _MockFoodLogRepository();
    targetsRepository = _MockNutritionTargetsRepository();
    service = NutritionWidgetService(
      foodLogRepository: foodLogRepository,
      nutritionTargetsRepository: targetsRepository,
    );
  });

  test('buildSnapshot returns rounded totals and targets', () async {
    when(() => foodLogRepository.getLogsForDate(normalizedDate)).thenAnswer(
      (_) async => [
        FoodLogEntry(
          id: 'entry-1',
          date: normalizedDate,
          loggedAt: normalizedDate.add(const Duration(hours: 8)),
          servingGrams: 100,
          calories: 455.3,
          proteinGrams: 30.2,
          carbsGrams: 45.5,
          fatGrams: 12.2,
        ),
        FoodLogEntry(
          id: 'entry-2',
          date: normalizedDate,
          loggedAt: normalizedDate.add(const Duration(hours: 13)),
          servingGrams: 180,
          calories: 1181.9,
          proteinGrams: 92.6,
          carbsGrams: 80.1,
          fatGrams: 43.6,
        ),
      ],
    );

    when(() => targetsRepository.getCurrentPlan(normalizedDate)).thenAnswer(
      (_) async => NutritionTargetPlan(
        weekStart: DateTime(2026, 2, 2),
        mode: 'auto',
        goal: 'maintain',
        caloriesTarget: 2300,
        proteinTarget: 100,
        carbsTarget: 301,
        fatTarget: 76,
      ),
    );

    final snapshot = await service.buildSnapshot(date: testDate);

    expect(snapshot.calories, 1637);
    expect(snapshot.caloriesTarget, 2300);
    expect(snapshot.protein, 123);
    expect(snapshot.proteinTarget, 100);
    expect(snapshot.fat, 56);
    expect(snapshot.fatTarget, 76);
    expect(snapshot.carbs, 126);
    expect(snapshot.carbsTarget, 301);
  });

  test('buildSnapshot falls back to zeros when repositories fail', () async {
    when(
      () => foodLogRepository.getLogsForDate(normalizedDate),
    ).thenThrow(Exception('offline'));
    when(
      () => targetsRepository.getCurrentPlan(normalizedDate),
    ).thenThrow(Exception('unauthorized'));

    final snapshot = await service.buildSnapshot(date: testDate);

    expect(snapshot.calories, 0);
    expect(snapshot.caloriesTarget, 0);
    expect(snapshot.protein, 0);
    expect(snapshot.proteinTarget, 0);
    expect(snapshot.fat, 0);
    expect(snapshot.fatTarget, 0);
    expect(snapshot.carbs, 0);
    expect(snapshot.carbsTarget, 0);
  });

  test(
    'buildSnapshot falls back to zeros when repositories are unregistered',
    () async {
      final isolatedGetIt = GetIt.asNewInstance();
      addTearDown(() => isolatedGetIt.reset());

      final serviceWithoutRepos = NutritionWidgetService(getIt: isolatedGetIt);
      final snapshot = await serviceWithoutRepos.buildSnapshot(date: testDate);

      expect(snapshot.calories, 0);
      expect(snapshot.caloriesTarget, 0);
      expect(snapshot.protein, 0);
      expect(snapshot.proteinTarget, 0);
      expect(snapshot.fat, 0);
      expect(snapshot.fatTarget, 0);
      expect(snapshot.carbs, 0);
      expect(snapshot.carbsTarget, 0);
    },
  );
}
