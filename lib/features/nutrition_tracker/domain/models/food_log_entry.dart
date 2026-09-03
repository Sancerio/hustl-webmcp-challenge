import 'package:equatable/equatable.dart';

import 'food.dart';

/// Matches a canonical backend UUID (8-4-4-4-12 hex, case-insensitive).
final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// True only for a canonical backend `Food.id` (a UUID). On-device generic
/// foods carry asset ids like `fdc-171705`, which the backend cannot resolve,
/// so callers must treat them as reference-less (log by value, no favorite).
bool isBackendFoodId(String? id) {
  if (id == null || id.isEmpty) return false;
  return _uuidPattern.hasMatch(id);
}

class FoodLogEntry extends Equatable {
  const FoodLogEntry({
    required this.id,
    required this.date,
    required this.loggedAt,
    required this.servingGrams,
    required this.calories,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
    this.fiberGrams,
    this.sugarGrams,
    this.sodiumMg,
    this.food,
    this.foodName,
    this.portionLabel,
    this.source = 'self',
  });

  final String id;
  final DateTime date;
  final DateTime loggedAt;
  DateTime get consumedAt => loggedAt;
  final double servingGrams;
  final double calories;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;
  final double? fiberGrams;
  final double? sugarGrams;
  final double? sodiumMg;
  final Food? food;
  final String? foodName;
  final String? portionLabel;
  final String source;

  FoodLogEntry copyWith({
    String? id,
    DateTime? date,
    DateTime? loggedAt,
    double? servingGrams,
    double? calories,
    double? proteinGrams,
    double? carbsGrams,
    double? fatGrams,
    double? fiberGrams,
    double? sugarGrams,
    double? sodiumMg,
    Food? food,
    String? foodName,
    String? portionLabel,
    String? source,
  }) => FoodLogEntry(
    id: id ?? this.id,
    date: date ?? this.date,
    loggedAt: loggedAt ?? this.loggedAt,
    servingGrams: servingGrams ?? this.servingGrams,
    calories: calories ?? this.calories,
    proteinGrams: proteinGrams ?? this.proteinGrams,
    carbsGrams: carbsGrams ?? this.carbsGrams,
    fatGrams: fatGrams ?? this.fatGrams,
    fiberGrams: fiberGrams ?? this.fiberGrams,
    sugarGrams: sugarGrams ?? this.sugarGrams,
    sodiumMg: sodiumMg ?? this.sodiumMg,
    food: food ?? this.food,
    foodName: foodName ?? this.foodName,
    portionLabel: portionLabel ?? this.portionLabel,
    source: source ?? this.source,
  );

  Map<String, dynamic> toPayload() => {
    'date': date.toIso8601String().substring(0, 10),
    'consumedAt': loggedAt.toUtc().toIso8601String(),
    // Local-only generic foods carry an asset id (e.g. "fdc-171705") that the
    // backend cannot resolve. The log payload already snapshots every macro, so
    // reference the food by id only when it is a canonical backend UUID; else
    // log it by value (food_id is nullable, like manual/scan logs).
    'foodId': isBackendFoodId(food?.id) ? food!.id : null,
    'foodName': foodName ?? food?.name,
    'servingGrams': servingGrams,
    'calories': calories,
    'proteinGrams': proteinGrams,
    'carbsGrams': carbsGrams,
    'fatGrams': fatGrams,
    if (fiberGrams != null) 'fiberGrams': fiberGrams,
    if (sugarGrams != null) 'sugarGrams': sugarGrams,
    if (sodiumMg != null) 'sodiumMg': sodiumMg,
    'source': source,
  };

  factory FoodLogEntry.fromMap(Map<String, dynamic> map) => FoodLogEntry(
    id: (map['id'] ?? '').toString(),
    date: DateTime.parse(map['date'] as String),
    loggedAt: DateTime.parse(
      (map['consumed_at'] ?? map['logged_at']) as String,
    ),
    servingGrams: (map['serving_grams'] as num?)?.toDouble() ?? 0,
    calories: (map['calories'] as num?)?.toDouble() ?? 0,
    proteinGrams: (map['protein_grams'] as num?)?.toDouble() ?? 0,
    carbsGrams: (map['carbs_grams'] as num?)?.toDouble() ?? 0,
    fatGrams: (map['fat_grams'] as num?)?.toDouble() ?? 0,
    fiberGrams: (map['fiber_grams'] as num?)?.toDouble(),
    sugarGrams: (map['sugar_grams'] as num?)?.toDouble(),
    sodiumMg: (map['sodium_mg'] as num?)?.toDouble(),
    foodName: map['food_name']?.toString(),
    source: map['source']?.toString() ?? 'self',
    food: map['food'] is Map
        ? Food.fromMap(Map<String, dynamic>.from(map['food'] as Map))
        : null,
  );

  /// Parses a re-loggable snapshot from `GET /api/nutrition/foods/suggestions`
  /// (the `suggestions`/`recents` arrays). Unlike [fromMap], a snapshot has NO
  /// `id` or `date` (it's a distinct-food summary, not a stored log row), so both
  /// fall back: the id to a synthetic temp id and the date to the snapshot's
  /// `logged_at` day. The snapshot's serving + macro fields are the user's
  /// last-used portion, so re-logging a staple keeps the portion they always use.
  factory FoodLogEntry.fromSnapshot(Map<String, dynamic> map) {
    final loggedAt = DateTime.parse(
      (map['consumed_at'] ??
              map['logged_at'] ??
              map['lastLoggedAt'] ??
              DateTime.now().toIso8601String())
          .toString(),
    );
    return FoodLogEntry(
      id: 'recent-${loggedAt.microsecondsSinceEpoch}',
      date: DateTime(loggedAt.year, loggedAt.month, loggedAt.day),
      loggedAt: loggedAt,
      servingGrams: (map['serving_grams'] as num?)?.toDouble() ?? 0,
      calories: (map['calories'] as num?)?.toDouble() ?? 0,
      proteinGrams: (map['protein_grams'] as num?)?.toDouble() ?? 0,
      carbsGrams: (map['carbs_grams'] as num?)?.toDouble() ?? 0,
      fatGrams: (map['fat_grams'] as num?)?.toDouble() ?? 0,
      fiberGrams: (map['fiber_grams'] as num?)?.toDouble(),
      sugarGrams: (map['sugar_grams'] as num?)?.toDouble(),
      sodiumMg: (map['sodium_mg'] as num?)?.toDouble(),
      foodName: map['food_name']?.toString(),
      source: map['source']?.toString() ?? 'self',
      food: map['food'] is Map
          ? Food.fromMap(Map<String, dynamic>.from(map['food'] as Map))
          : null,
    );
  }

  @override
  List<Object?> get props => [
    id,
    date,
    loggedAt,
    servingGrams,
    calories,
    proteinGrams,
    carbsGrams,
    fatGrams,
    fiberGrams,
    sugarGrams,
    sodiumMg,
    food,
    foodName,
    portionLabel,
    source,
  ];
}
