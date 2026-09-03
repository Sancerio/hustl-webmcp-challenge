import 'package:equatable/equatable.dart';

class RecipeItem extends Equatable {
  const RecipeItem({
    required this.id,
    this.foodId,
    required this.foodName,
    required this.servingGrams,
    required this.calories,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
    this.fiberGrams,
    this.sugarGrams,
    this.sodiumMg,
  });

  final String id;
  final String? foodId;
  final String foodName;
  final double servingGrams;
  final double calories;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;
  final double? fiberGrams;
  final double? sugarGrams;
  final double? sodiumMg;

  Map<String, dynamic> toPayload() => {
    if (foodId != null) 'foodId': foodId,
    'foodName': foodName,
    'servingGrams': servingGrams,
    'calories': calories,
    'proteinGrams': proteinGrams,
    'carbsGrams': carbsGrams,
    'fatGrams': fatGrams,
    if (fiberGrams != null) 'fiberGrams': fiberGrams,
    if (sugarGrams != null) 'sugarGrams': sugarGrams,
    if (sodiumMg != null) 'sodiumMg': sodiumMg,
  };

  RecipeItem copyWith({
    String? id,
    String? foodId,
    String? foodName,
    double? servingGrams,
    double? calories,
    double? proteinGrams,
    double? carbsGrams,
    double? fatGrams,
    double? fiberGrams,
    double? sugarGrams,
    double? sodiumMg,
  }) => RecipeItem(
    id: id ?? this.id,
    foodId: foodId ?? this.foodId,
    foodName: foodName ?? this.foodName,
    servingGrams: servingGrams ?? this.servingGrams,
    calories: calories ?? this.calories,
    proteinGrams: proteinGrams ?? this.proteinGrams,
    carbsGrams: carbsGrams ?? this.carbsGrams,
    fatGrams: fatGrams ?? this.fatGrams,
    fiberGrams: fiberGrams ?? this.fiberGrams,
    sugarGrams: sugarGrams ?? this.sugarGrams,
    sodiumMg: sodiumMg ?? this.sodiumMg,
  );

  factory RecipeItem.fromMap(Map<String, dynamic> map) => RecipeItem(
    id: (map['id'] ?? '').toString(),
    foodId: map['food_id']?.toString() ?? map['foodId']?.toString(),
    foodName: (map['food_name'] ?? map['foodName'] ?? '').toString(),
    servingGrams:
        (map['serving_grams'] as num?)?.toDouble() ??
        (map['servingGrams'] as num?)?.toDouble() ??
        0,
    calories: (map['calories'] as num?)?.toDouble() ?? 0,
    proteinGrams:
        (map['protein_grams'] as num?)?.toDouble() ??
        (map['proteinGrams'] as num?)?.toDouble() ??
        0,
    carbsGrams:
        (map['carbs_grams'] as num?)?.toDouble() ??
        (map['carbsGrams'] as num?)?.toDouble() ??
        0,
    fatGrams:
        (map['fat_grams'] as num?)?.toDouble() ??
        (map['fatGrams'] as num?)?.toDouble() ??
        0,
    fiberGrams:
        (map['fiber_grams'] as num?)?.toDouble() ??
        (map['fiberGrams'] as num?)?.toDouble(),
    sugarGrams:
        (map['sugar_grams'] as num?)?.toDouble() ??
        (map['sugarGrams'] as num?)?.toDouble(),
    sodiumMg:
        (map['sodium_mg'] as num?)?.toDouble() ??
        (map['sodiumMg'] as num?)?.toDouble(),
  );

  @override
  List<Object?> get props => [
    id,
    foodId,
    foodName,
    servingGrams,
    calories,
    proteinGrams,
    carbsGrams,
    fatGrams,
    fiberGrams,
    sugarGrams,
    sodiumMg,
  ];
}

class Recipe extends Equatable {
  const Recipe({
    required this.id,
    required this.name,
    this.description,
    required this.servings,
    required this.items,
  });

  final String id;
  final String name;
  final String? description;
  final double servings;
  final List<RecipeItem> items;

  Map<String, dynamic> toPayload() => {
    'name': name,
    if (description != null) 'description': description,
    'servings': servings,
    'items': items.map((i) => i.toPayload()).toList(growable: false),
  };

  Recipe copyWith({
    String? id,
    String? name,
    String? description,
    double? servings,
    List<RecipeItem>? items,
  }) => Recipe(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    servings: servings ?? this.servings,
    items: items ?? this.items,
  );

  factory Recipe.fromMap(Map<String, dynamic> map) => Recipe(
    id: (map['id'] ?? '').toString(),
    name: (map['name'] ?? '').toString(),
    description: map['description']?.toString(),
    servings: (map['servings'] as num?)?.toDouble() ?? 1,
    items:
        ((map['recipe_items'] as List?) ?? (map['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => RecipeItem.fromMap(Map<String, dynamic>.from(e)))
            .toList(growable: false),
  );

  @override
  List<Object?> get props => [id, name, description, servings, items];
}
