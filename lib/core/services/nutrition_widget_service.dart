import 'dart:developer' as dev;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:get_it/get_it.dart';
import 'package:home_widget/home_widget.dart';

import '../../features/nutrition_tracker/domain/models/food_log_entry.dart';
import '../../features/nutrition_tracker/domain/models/nutrition_target_plan.dart';
import '../../features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import '../../features/nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';

class NutritionWidgetSnapshot {
  const NutritionWidgetSnapshot({
    required this.calories,
    required this.caloriesTarget,
    required this.protein,
    required this.proteinTarget,
    required this.fat,
    required this.fatTarget,
    required this.carbs,
    required this.carbsTarget,
  });

  final int calories;
  final int caloriesTarget;
  final int protein;
  final int proteinTarget;
  final int fat;
  final int fatTarget;
  final int carbs;
  final int carbsTarget;
}

/// Coordinates data shared with the native nutrition home-screen widgets.
class NutritionWidgetService {
  NutritionWidgetService({
    FoodLogRepository? foodLogRepository,
    NutritionTargetsRepository? nutritionTargetsRepository,
    GetIt? getIt,
  }) : _foodLogRepository = foodLogRepository,
       _nutritionTargetsRepository = nutritionTargetsRepository,
       _getIt = getIt ?? GetIt.instance;

  static const String androidProviderName =
      'com.hustl.app.widget.NutritionSummaryWidgetProvider';
  static const String iosWidgetKind = 'NutritionSummaryWidget';

  static const String caloriesKey = 'nutrition_widget_calories';
  static const String caloriesTargetKey = 'nutrition_widget_calories_target';
  static const String proteinKey = 'nutrition_widget_protein';
  static const String proteinTargetKey = 'nutrition_widget_protein_target';
  static const String fatKey = 'nutrition_widget_fat';
  static const String fatTargetKey = 'nutrition_widget_fat_target';
  static const String carbsKey = 'nutrition_widget_carbs';
  static const String carbsTargetKey = 'nutrition_widget_carbs_target';
  static const String updatedAtKey = 'nutrition_widget_updated_at';

  FoodLogRepository? _foodLogRepository;
  NutritionTargetsRepository? _nutritionTargetsRepository;
  final GetIt _getIt;

  Future<void> updateNutritionSummaryWidget({DateTime? date}) async {
    if (!_isHomeWidgetSupported) {
      return;
    }

    final NutritionWidgetSnapshot snapshot = await buildSnapshot(date: date);
    final DateTime now = DateTime.now().toUtc();

    try {
      await Future.wait([
        HomeWidget.saveWidgetData<int>(caloriesKey, snapshot.calories),
        HomeWidget.saveWidgetData<int>(
          caloriesTargetKey,
          snapshot.caloriesTarget,
        ),
        HomeWidget.saveWidgetData<int>(proteinKey, snapshot.protein),
        HomeWidget.saveWidgetData<int>(
          proteinTargetKey,
          snapshot.proteinTarget,
        ),
        HomeWidget.saveWidgetData<int>(fatKey, snapshot.fat),
        HomeWidget.saveWidgetData<int>(fatTargetKey, snapshot.fatTarget),
        HomeWidget.saveWidgetData<int>(carbsKey, snapshot.carbs),
        HomeWidget.saveWidgetData<int>(carbsTargetKey, snapshot.carbsTarget),
        HomeWidget.saveWidgetData<String>(updatedAtKey, now.toIso8601String()),
      ]);

      await HomeWidget.updateWidget(
        qualifiedAndroidName: androidProviderName,
        iOSName: iosWidgetKind,
        name: iosWidgetKind,
      );
    } on MissingPluginException catch (error, stackTrace) {
      dev.log(
        'HomeWidget plugin unavailable; skipping nutrition widget refresh.',
        name: 'NutritionWidgetService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<NutritionWidgetSnapshot> buildSnapshot({DateTime? date}) async {
    final DateTime reference = date ?? DateTime.now();
    final DateTime day = DateTime(
      reference.year,
      reference.month,
      reference.day,
    );

    List<FoodLogEntry> entries = const <FoodLogEntry>[];
    NutritionTargetPlan? targets;
    final FoodLogRepository? foodLogRepository = _resolveFoodLogRepository();
    final NutritionTargetsRepository? nutritionTargetsRepository =
        _resolveNutritionTargetsRepository();

    if (foodLogRepository != null) {
      try {
        entries = await foodLogRepository.getLogsForDate(day);
      } catch (error, stackTrace) {
        dev.log(
          'Failed loading nutrition logs for widget',
          name: 'NutritionWidgetService',
          error: error,
          stackTrace: stackTrace,
        );
      }
    } else {
      dev.log(
        'FoodLogRepository not registered; using zeroed nutrition widget logs.',
        name: 'NutritionWidgetService',
      );
    }

    if (nutritionTargetsRepository != null) {
      try {
        targets = await nutritionTargetsRepository.getCurrentPlan(day);
      } catch (error, stackTrace) {
        dev.log(
          'Failed loading nutrition targets for widget',
          name: 'NutritionWidgetService',
          error: error,
          stackTrace: stackTrace,
        );
      }
    } else {
      dev.log(
        'NutritionTargetsRepository not registered; using zeroed nutrition targets.',
        name: 'NutritionWidgetService',
      );
    }

    final double calories = entries.fold<double>(
      0,
      (double total, FoodLogEntry entry) => total + entry.calories,
    );
    final double protein = entries.fold<double>(
      0,
      (double total, FoodLogEntry entry) => total + entry.proteinGrams,
    );
    final double fat = entries.fold<double>(
      0,
      (double total, FoodLogEntry entry) => total + entry.fatGrams,
    );
    final double carbs = entries.fold<double>(
      0,
      (double total, FoodLogEntry entry) => total + entry.carbsGrams,
    );

    return NutritionWidgetSnapshot(
      calories: _toWidgetInt(calories),
      caloriesTarget: _toWidgetInt(targets?.caloriesTarget ?? 0),
      protein: _toWidgetInt(protein),
      proteinTarget: _toWidgetInt(targets?.proteinTarget ?? 0),
      fat: _toWidgetInt(fat),
      fatTarget: _toWidgetInt(targets?.fatTarget ?? 0),
      carbs: _toWidgetInt(carbs),
      carbsTarget: _toWidgetInt(targets?.carbsTarget ?? 0),
    );
  }

  int _toWidgetInt(double value) {
    if (!value.isFinite) return 0;
    final int rounded = value.round();
    return rounded < 0 ? 0 : rounded;
  }

  FoodLogRepository? _resolveFoodLogRepository() {
    if (_foodLogRepository != null) return _foodLogRepository;
    if (!_getIt.isRegistered<FoodLogRepository>()) return null;
    _foodLogRepository = _getIt<FoodLogRepository>();
    return _foodLogRepository;
  }

  NutritionTargetsRepository? _resolveNutritionTargetsRepository() {
    if (_nutritionTargetsRepository != null) return _nutritionTargetsRepository;
    if (!_getIt.isRegistered<NutritionTargetsRepository>()) return null;
    _nutritionTargetsRepository = _getIt<NutritionTargetsRepository>();
    return _nutritionTargetsRepository;
  }

  bool get _isHomeWidgetSupported {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
