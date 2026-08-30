import 'package:equatable/equatable.dart';

class MealScanTotals extends Equatable {
  const MealScanTotals({
    required this.caloriesKcal,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
  });

  final double? caloriesKcal;
  final double? proteinGrams;
  final double? carbsGrams;
  final double? fatGrams;

  factory MealScanTotals.fromMap(Map<String, dynamic> map) => MealScanTotals(
    caloriesKcal: (map['caloriesKcal'] as num?)?.toDouble(),
    proteinGrams: (map['proteinGrams'] as num?)?.toDouble(),
    carbsGrams: (map['carbsGrams'] as num?)?.toDouble(),
    fatGrams: (map['fatGrams'] as num?)?.toDouble(),
  );

  @override
  List<Object?> get props => [caloriesKcal, proteinGrams, carbsGrams, fatGrams];
}

class MealScanItem extends Equatable {
  const MealScanItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.grams,
    required this.caloriesKcal,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
    this.foodId,
    this.matchedName,
    this.matchedSource,
    this.matchedTrustTier,
    this.matchConfidence,
    this.macroSource,
  });

  final String name;
  final double? quantity;
  final String? unit;
  final double? grams;
  final double? caloriesKcal;
  final double? proteinGrams;
  final double? carbsGrams;
  final double? fatGrams;

  /// Backend food row this item matched to (UUID), when the AI resolved the
  /// item against the DB rather than fabricating macros.
  final String? foodId;
  final String? matchedName;
  final String? matchedSource;
  final String? matchedTrustTier;
  final double? matchConfidence;

  /// Provenance of the macros: 'db' (from a matched backend food) or
  /// 'fabricated' (AI-estimated).
  final String? macroSource;

  bool get isDbMatched => macroSource == 'db';

  factory MealScanItem.fromMap(Map<String, dynamic> map) => MealScanItem(
    name: (map['name'] ?? '').toString(),
    quantity: (map['quantity'] as num?)?.toDouble(),
    unit: map['unit']?.toString(),
    grams: (map['grams'] as num?)?.toDouble(),
    caloriesKcal: (map['caloriesKcal'] as num?)?.toDouble(),
    proteinGrams: (map['proteinGrams'] as num?)?.toDouble(),
    carbsGrams: (map['carbsGrams'] as num?)?.toDouble(),
    fatGrams: (map['fatGrams'] as num?)?.toDouble(),
    foodId: map['foodId']?.toString(),
    matchedName: map['matchedName']?.toString(),
    matchedSource: map['matchedSource']?.toString(),
    matchedTrustTier: map['matchedTrustTier']?.toString(),
    matchConfidence: (map['matchConfidence'] as num?)?.toDouble(),
    macroSource: map['macroSource']?.toString(),
  );

  MealScanItem copyWith({
    String? name,
    double? quantity,
    String? unit,
    double? grams,
    double? caloriesKcal,
    double? proteinGrams,
    double? carbsGrams,
    double? fatGrams,
    String? foodId,
    String? matchedName,
    String? matchedSource,
    String? matchedTrustTier,
    double? matchConfidence,
    String? macroSource,
  }) => MealScanItem(
    name: name ?? this.name,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    grams: grams ?? this.grams,
    caloriesKcal: caloriesKcal ?? this.caloriesKcal,
    proteinGrams: proteinGrams ?? this.proteinGrams,
    carbsGrams: carbsGrams ?? this.carbsGrams,
    fatGrams: fatGrams ?? this.fatGrams,
    foodId: foodId ?? this.foodId,
    matchedName: matchedName ?? this.matchedName,
    matchedSource: matchedSource ?? this.matchedSource,
    matchedTrustTier: matchedTrustTier ?? this.matchedTrustTier,
    matchConfidence: matchConfidence ?? this.matchConfidence,
    macroSource: macroSource ?? this.macroSource,
  );

  @override
  List<Object?> get props => [
    name,
    quantity,
    unit,
    grams,
    caloriesKcal,
    proteinGrams,
    carbsGrams,
    fatGrams,
    foodId,
    matchedName,
    matchedSource,
    matchedTrustTier,
    matchConfidence,
    macroSource,
  ];
}

class MealScanDebug extends Equatable {
  const MealScanDebug({required this.model, required this.latencyMs});

  final String model;
  final int latencyMs;

  factory MealScanDebug.fromMap(Map<String, dynamic> map) => MealScanDebug(
    model: (map['model'] ?? '').toString(),
    latencyMs: (map['latencyMs'] as num?)?.toInt() ?? 0,
  );

  @override
  List<Object?> get props => [model, latencyMs];
}

class MealScanResult extends Equatable {
  const MealScanResult({
    required this.mealName,
    required this.totals,
    required this.items,
    required this.confidence,
    required this.assumptions,
    required this.warnings,
    required this.debug,
  });

  final String mealName;
  final MealScanTotals totals;
  final List<MealScanItem> items;
  final double confidence;
  final List<String> assumptions;
  final List<String> warnings;
  final MealScanDebug debug;

  factory MealScanResult.fromMap(Map<String, dynamic> map) => MealScanResult(
    mealName: (map['mealName'] ?? '').toString(),
    totals: map['totals'] is Map
        ? MealScanTotals.fromMap(Map<String, dynamic>.from(map['totals']))
        : const MealScanTotals(
            caloriesKcal: null,
            proteinGrams: null,
            carbsGrams: null,
            fatGrams: null,
          ),
    items: (map['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => MealScanItem.fromMap(Map<String, dynamic>.from(e)))
        .toList(growable: false),
    confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
    assumptions: (map['assumptions'] as List? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList(growable: false),
    warnings: (map['warnings'] as List? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList(growable: false),
    debug: map['debug'] is Map
        ? MealScanDebug.fromMap(Map<String, dynamic>.from(map['debug']))
        : const MealScanDebug(model: '', latencyMs: 0),
  );

  @override
  List<Object?> get props => [
    mealName,
    totals,
    items,
    confidence,
    assumptions,
    warnings,
    debug,
  ];
}
