import 'package:equatable/equatable.dart';

import 'nutrition_goal_profile.dart';

class NutritionTargetPlan extends Equatable {
  const NutritionTargetPlan({
    required this.weekStart,
    required this.mode,
    required this.goal,
    this.ratePerWeek,
    required this.caloriesTarget,
    required this.proteinTarget,
    required this.carbsTarget,
    required this.fatTarget,
    this.rationale,
    this.lockedUntil,
    this.needsSetup = false,
    this.profile,
  });

  final DateTime weekStart;
  final String mode;
  final String goal;
  final double? ratePerWeek;
  final double caloriesTarget;
  final double proteinTarget;
  final double carbsTarget;
  final double fatTarget;
  final String? rationale;
  final DateTime? lockedUntil;
  final bool needsSetup;

  /// The persisted "about you" inputs (age/sex/height/weight/activity) so the
  /// goal sheet can prefill on reopen. Lives on `user_profiles`, not the weekly
  /// plan, so it rides alongside the plan in the targets response rather than in
  /// the plan row itself. Null when the backend did not include it.
  final NutritionGoalProfile? profile;

  factory NutritionTargetPlan.fromMap(Map<String, dynamic> map) =>
      NutritionTargetPlan(
        weekStart: DateTime.parse(map['week_start'] as String),
        mode: (map['mode'] ?? 'auto').toString(),
        goal: (map['goal'] ?? 'maintain').toString(),
        ratePerWeek: (map['rate_per_week'] as num?)?.toDouble(),
        caloriesTarget: (map['calories_target'] as num?)?.toDouble() ?? 0,
        proteinTarget: (map['protein_grams_target'] as num?)?.toDouble() ?? 0,
        carbsTarget: (map['carbs_grams_target'] as num?)?.toDouble() ?? 0,
        fatTarget: (map['fat_grams_target'] as num?)?.toDouble() ?? 0,
        rationale: map['rationale']?.toString(),
        lockedUntil: map['locked_until'] != null
            ? DateTime.tryParse(map['locked_until'] as String)
            : null,
        needsSetup: map['needsSetup'] == true,
        profile: map.containsKey('profile')
            ? NutritionGoalProfile.fromMap(
                (map['profile'] as Map?)?.cast<String, dynamic>(),
              )
            : null,
      );

  Map<String, dynamic> toPatchPayload() => {
    'mode': mode,
    'goal': goal,
    if (ratePerWeek != null) 'ratePerWeek': ratePerWeek,
    'caloriesTarget': caloriesTarget,
    'proteinTarget': proteinTarget,
    'carbsTarget': carbsTarget,
    'fatTarget': fatTarget,
    if (lockedUntil != null) 'lockUntil': lockedUntil!.toIso8601String(),
  };

  @override
  List<Object?> get props => [
    weekStart,
    mode,
    goal,
    ratePerWeek,
    caloriesTarget,
    proteinTarget,
    carbsTarget,
    fatTarget,
    rationale,
    lockedUntil,
    needsSetup,
    profile,
  ];
}
