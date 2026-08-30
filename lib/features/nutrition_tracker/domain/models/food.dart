import 'package:equatable/equatable.dart';

class Food extends Equatable {
  const Food({
    required this.id,
    required this.name,
    this.brand,
    this.barcode,
    this.source = 'fdc',
    this.servingSizeGrams,
    this.caloriesPer100g,
    this.proteinPer100g,
    this.carbsPer100g,
    this.fatPer100g,
    this.fiberPer100g,
    this.sugarPer100g,
    this.sodiumMgPer100g,
    this.completeness = 0,
    this.trustTier,
    this.macrosIncomplete = false,
    this.loggedCount,
    this.lastLoggedAt,
  });

  final String id;
  final String name;
  final String? brand;
  final String? barcode;
  final String source; // fdc/custom
  final double? servingSizeGrams;
  final double? caloriesPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;
  final double? fiberPer100g;
  final double? sugarPer100g;
  final double? sodiumMgPer100g;
  final double completeness;

  /// Backend-derived data-provenance tier: 'verified' (lab/government-grade),
  /// 'community' (crowd-sourced), or 'custom' (user's own). Null when the row
  /// predates the field. Drives the trust badge on search results.
  final String? trustTier;

  /// True when the backend flagged this row as missing one or more core macros.
  final bool macrosIncomplete;

  /// For a `recent` search result (a food resurfaced from log history): how many
  /// times the user has logged this food in the lookback window. Null for
  /// provider/custom rows.
  final int? loggedCount;

  /// For a `recent` search result: when the user last logged this food (ISO).
  /// Null for provider/custom rows.
  final String? lastLoggedAt;

  bool get hasMacros =>
      caloriesPer100g != null &&
      proteinPer100g != null &&
      carbsPer100g != null &&
      fatPer100g != null;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'brand': brand,
    'barcode': barcode,
    'source': source,
    'serving_size_grams': servingSizeGrams,
    'calories_per_100g': caloriesPer100g,
    'protein_grams_per_100g': proteinPer100g,
    'carbs_grams_per_100g': carbsPer100g,
    'fat_grams_per_100g': fatPer100g,
    'fiber_grams_per_100g': fiberPer100g,
    'sugar_grams_per_100g': sugarPer100g,
    'sodium_mg_per_100g': sodiumMgPer100g,
    'completeness': completeness,
    'trustTier': trustTier,
    'macrosIncomplete': macrosIncomplete,
    'loggedCount': loggedCount,
    'lastLoggedAt': lastLoggedAt,
  };

  factory Food.fromMap(Map<String, dynamic> map) => Food(
    id: (map['id'] ?? '').toString(),
    name: (map['name'] ?? '').toString(),
    brand: map['brand']?.toString(),
    barcode: map['barcode']?.toString(),
    source: (map['source'] ?? 'fdc').toString(),
    servingSizeGrams: (map['serving_size_grams'] as num?)?.toDouble(),
    caloriesPer100g: (map['calories_per_100g'] as num?)?.toDouble(),
    proteinPer100g: (map['protein_grams_per_100g'] as num?)?.toDouble(),
    carbsPer100g: (map['carbs_grams_per_100g'] as num?)?.toDouble(),
    fatPer100g: (map['fat_grams_per_100g'] as num?)?.toDouble(),
    fiberPer100g: (map['fiber_grams_per_100g'] as num?)?.toDouble(),
    sugarPer100g: (map['sugar_grams_per_100g'] as num?)?.toDouble(),
    sodiumMgPer100g: (map['sodium_mg_per_100g'] as num?)?.toDouble(),
    completeness: (map['completeness'] as num?)?.toDouble() ?? 0,
    trustTier: map['trustTier']?.toString(),
    macrosIncomplete: map['macrosIncomplete'] == true,
    loggedCount: (map['loggedCount'] as num?)?.toInt(),
    lastLoggedAt: map['lastLoggedAt']?.toString(),
  );

  @override
  List<Object?> get props => [
    id,
    name,
    brand,
    barcode,
    source,
    servingSizeGrams,
    caloriesPer100g,
    proteinPer100g,
    carbsPer100g,
    fatPer100g,
    fiberPer100g,
    sugarPer100g,
    sodiumMgPer100g,
    completeness,
    trustTier,
    macrosIncomplete,
    loggedCount,
    lastLoggedAt,
  ];
}
