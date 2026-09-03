import 'package:equatable/equatable.dart';

/// One proposed food entry inside a `food_log` proposal. Mirrors a payload item:
/// `{ foodName, servingGrams, calories, proteinGrams, carbsGrams, fatGrams,
///    fiberGrams?, sugarGrams?, sodiumMg? }`.
class ProposedFoodItem extends Equatable {
  const ProposedFoodItem({
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

  final String foodName;
  final double servingGrams;
  final double calories;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;
  final double? fiberGrams;
  final double? sugarGrams;
  final double? sodiumMg;

  static double _num(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0;
    return 0;
  }

  static double? _optNum(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  factory ProposedFoodItem.fromJson(Map<String, dynamic> json) {
    return ProposedFoodItem(
      foodName: json['foodName']?.toString() ?? 'Food',
      servingGrams: _num(json['servingGrams']),
      calories: _num(json['calories']),
      proteinGrams: _num(json['proteinGrams']),
      carbsGrams: _num(json['carbsGrams']),
      fatGrams: _num(json['fatGrams']),
      fiberGrams: _optNum(json['fiberGrams']),
      sugarGrams: _optNum(json['sugarGrams']),
      sodiumMg: _optNum(json['sodiumMg']),
    );
  }

  @override
  List<Object?> get props => [
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

/// The proposed meal carried by a `food_log` proposal. The connected LLM
/// interpreted the user's voice/photo/text and produced these items; on approve
/// (or auto-approve) they're written to the diary as `source='ai'` entries, and
/// the whole proposal is undoable.
class ProposedFoodLog extends Equatable {
  const ProposedFoodLog({required this.items, this.date, this.note});

  final List<ProposedFoodItem> items;

  /// The user-local day (YYYY-MM-DD) the meal is logged to; null = today.
  final DateTime? date;
  final String? note;

  double get totalCalories => items.fold(0, (s, it) => s + it.calories);
  double get totalProtein => items.fold(0, (s, it) => s + it.proteinGrams);
  double get totalCarbs => items.fold(0, (s, it) => s + it.carbsGrams);
  double get totalFat => items.fold(0, (s, it) => s + it.fatGrams);

  static DateTime? _parseDate(Object? raw) {
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw)?.toLocal();
    return null;
  }

  /// Parse from the backend `proposedPayload` map. Returns null when absent.
  static ProposedFoodLog? fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    final items = (json['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((m) => ProposedFoodItem.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    return ProposedFoodLog(
      items: items,
      date: _parseDate(json['date']),
      note: json['note']?.toString(),
    );
  }

  @override
  List<Object?> get props => [items, date, note];
}
