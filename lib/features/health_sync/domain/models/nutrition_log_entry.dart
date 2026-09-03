import 'package:equatable/equatable.dart';

class NutritionLogEntry extends Equatable {
  const NutritionLogEntry({
    required this.timestamp,
    required this.calories,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
    this.fiberGrams,
    this.sugarGrams,
    this.sodiumMilligrams,
    this.waterMilliliters,
    this.source = 'unknown',
  });

  final DateTime timestamp;
  final double calories;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;
  final double? fiberGrams;
  final double? sugarGrams;
  final double? sodiumMilligrams;
  final double? waterMilliliters;
  final String source;

  double get waterLiters =>
      waterMilliliters == null ? 0 : waterMilliliters! / 1000;

  @override
  List<Object?> get props => [
    timestamp,
    calories,
    proteinGrams,
    carbsGrams,
    fatGrams,
    fiberGrams,
    sugarGrams,
    sodiumMilligrams,
    waterMilliliters,
    source,
  ];
}
