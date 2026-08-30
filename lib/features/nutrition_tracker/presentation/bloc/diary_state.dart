import 'package:equatable/equatable.dart';

import '../../domain/models/food_log_entry.dart';
import '../../domain/models/nutrition_target_plan.dart';

class DiaryState extends Equatable {
  const DiaryState({
    required this.date,
    this.isLoading = false,
    this.hasLoaded = false,
    this.entries = const [],
    this.targets,
    this.errorMessage,
    this.totalCalories = 0,
    this.totalProtein = 0,
    this.totalCarbs = 0,
    this.totalFat = 0,
    this.dayWeightKg,
    this.latestWeightKg,
    this.latestWeightDate,
  });

  final DateTime date;
  final bool isLoading;

  /// True once an initial load for the current day has *resolved* (success or
  /// after data arrives). Distinguishes the pristine pre-fetch state from a
  /// genuinely empty diary so the first-run setup prompt never flashes while a
  /// returning user's data is still in flight.
  final bool hasLoaded;
  final List<FoodLogEntry> entries;
  final NutritionTargetPlan? targets;
  final String? errorMessage;
  final double totalCalories;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;
  final double? dayWeightKg;
  final double? latestWeightKg;
  final DateTime? latestWeightDate;

  DiaryState copyWith({
    DateTime? date,
    bool? isLoading,
    bool? hasLoaded,
    List<FoodLogEntry>? entries,
    NutritionTargetPlan? targets,
    String? errorMessage,
    double? totalCalories,
    double? totalProtein,
    double? totalCarbs,
    double? totalFat,
    double? dayWeightKg,
    bool clearDayWeightKg = false,
    double? latestWeightKg,
    bool clearLatestWeightKg = false,
    DateTime? latestWeightDate,
    bool clearLatestWeightDate = false,
  }) {
    return DiaryState(
      date: date ?? this.date,
      isLoading: isLoading ?? this.isLoading,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      entries: entries ?? this.entries,
      targets: targets ?? this.targets,
      errorMessage: errorMessage,
      totalCalories: totalCalories ?? this.totalCalories,
      totalProtein: totalProtein ?? this.totalProtein,
      totalCarbs: totalCarbs ?? this.totalCarbs,
      totalFat: totalFat ?? this.totalFat,
      dayWeightKg: clearDayWeightKg ? null : dayWeightKg ?? this.dayWeightKg,
      latestWeightKg: clearLatestWeightKg
          ? null
          : latestWeightKg ?? this.latestWeightKg,
      latestWeightDate: clearLatestWeightDate
          ? null
          : latestWeightDate ?? this.latestWeightDate,
    );
  }

  @override
  List<Object?> get props => [
    date,
    isLoading,
    hasLoaded,
    entries,
    targets,
    errorMessage,
    totalCalories,
    totalProtein,
    totalCarbs,
    totalFat,
    dayWeightKg,
    latestWeightKg,
    latestWeightDate,
  ];
}
