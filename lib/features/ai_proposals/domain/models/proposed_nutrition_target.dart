import 'package:equatable/equatable.dart';

/// The proposed nutrition four-tuple carried by a `nutrition_targets` proposal.
///
/// Mirrors the backend `proposedPayload` shape:
/// `{ caloriesTarget, proteinTarget, carbsTarget, fatTarget, weekStart,
///    rationale? }`. These are the numbers the assistant proposed; on apply the
/// app reconciles carbs and clamps the app's nutrition floor, so the persisted numbers
/// may differ slightly.
class ProposedNutritionTarget extends Equatable {
  const ProposedNutritionTarget({
    required this.caloriesTarget,
    required this.proteinTarget,
    required this.carbsTarget,
    required this.fatTarget,
    this.weekStart,
    this.rationale,
  });

  final double caloriesTarget;
  final double proteinTarget;
  final double carbsTarget;
  final double fatTarget;

  /// The resolved week (Monday) the targets apply to, as `YYYY-MM-DD`.
  final DateTime? weekStart;
  final String? rationale;

  static double _num(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0;
    return 0;
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw)?.toLocal();
    }
    return null;
  }

  /// Parse from the backend `proposedPayload` map. Returns null when the map is
  /// absent or empty (e.g. a non-nutrition proposal).
  static ProposedNutritionTarget? fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return ProposedNutritionTarget(
      caloriesTarget: _num(json['caloriesTarget']),
      proteinTarget: _num(json['proteinTarget']),
      carbsTarget: _num(json['carbsTarget']),
      fatTarget: _num(json['fatTarget']),
      weekStart: _parseDate(json['weekStart']),
      rationale: json['rationale']?.toString(),
    );
  }

  @override
  List<Object?> get props => [
    caloriesTarget,
    proteinTarget,
    carbsTarget,
    fatTarget,
    weekStart,
    rationale,
  ];
}
