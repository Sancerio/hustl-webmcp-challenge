import 'package:equatable/equatable.dart';

import 'proposal_summary.dart';
import 'proposed_exercise.dart';
import 'proposed_food_log.dart';
import 'proposed_food_log_revision.dart';
import 'proposed_nutrition_target.dart';
import 'proposed_workout_log.dart';

/// Full proposal detail for the approval screen.
///
/// `ProposalDetail = ProposalSummary + { description, proposedExercises,
/// resolvedExercisesAsOfProposal, baseTemplateUpdatedAt, appliedResult,
/// proposedNutrition }`.
class ProposalDetail extends Equatable {
  const ProposalDetail({
    required this.summary,
    required this.proposedExercises,
    required this.resolvedExercises,
    this.description,
    this.baseTemplateUpdatedAt,
    this.appliedResult,
    this.proposedNutrition,
    this.proposedFoodLog,
    this.proposedWorkoutLog,
    this.proposedFoodLogRevision,
  });

  final ProposalSummary summary;
  final String? description;
  final List<ProposedExercise> proposedExercises;
  final List<ResolvedExercise> resolvedExercises;
  final DateTime? baseTemplateUpdatedAt;
  final Map<String, dynamic>? appliedResult;

  /// The proposed nutrition four-tuple, present only for nutrition proposals.
  final ProposedNutritionTarget? proposedNutrition;

  /// The proposed meal, present only for `food_log` proposals.
  final ProposedFoodLog? proposedFoodLog;

  /// The proposed completed workout, present only for `workout_log` proposals.
  final ProposedWorkoutLog? proposedWorkoutLog;

  /// The proposed revision, present only for `food_log_edit`/`food_log_delete`.
  final ProposedFoodLogRevision? proposedFoodLogRevision;

  // Convenience pass-throughs.
  String get id => summary.id;
  ProposalKind get kind => summary.kind;
  bool get isEdit => summary.isEdit;
  bool get isNutrition => summary.isNutrition;
  bool get isFoodLog => summary.isFoodLog;
  bool get isWorkoutLog => summary.isWorkoutLog;
  bool get isFoodLogEdit => summary.isFoodLogEdit;
  bool get isFoodLogDelete => summary.isFoodLogDelete;
  bool get isFoodLogRevision => summary.isFoodLogRevision;
  bool get touchesFoodDiary => summary.touchesFoodDiary;
  bool get isLog => summary.isLog;
  bool get isPending => summary.isPending;
  String get templateName => summary.templateName;
  String? get targetTemplateId => summary.targetTemplateId;
  String? get conflictReason => summary.conflictReason;

  /// Whether any proposed exercise will create a brand-new custom exercise.
  bool get hasNewCustomExercises =>
      resolvedExercises.any((r) => r.willCreateCustom);

  /// The proposed exercises adapted into the render-Map shape the existing
  /// template-detail widgets consume.
  List<Map<String, dynamic>> get renderExercises =>
      proposedExercises.map((e) => e.toRenderMap()).toList();

  static DateTime? _parseNullableDate(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw)?.toLocal();
    }
    return null;
  }

  factory ProposalDetail.fromJson(Map<String, dynamic> json) {
    final proposed = (json['proposedExercises'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((m) => ProposedExercise.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    final resolved =
        (json['resolvedExercisesAsOfProposal'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((m) => ResolvedExercise.fromJson(Map<String, dynamic>.from(m)))
            .toList();
    final applied = json['appliedResult'];
    final payload = json['proposedPayload'];
    final summary = ProposalSummary.fromJson(json);
    final payloadMap =
        payload is Map ? Map<String, dynamic>.from(payload) : null;
    return ProposalDetail(
      summary: summary,
      description: json['description']?.toString(),
      proposedExercises: proposed,
      resolvedExercises: resolved,
      baseTemplateUpdatedAt: _parseNullableDate(json['baseTemplateUpdatedAt']),
      appliedResult: applied is Map
          ? Map<String, dynamic>.from(applied)
          : null,
      // The single proposedPayload column carries a different shape per kind, so
      // parse it into the model that matches this proposal's kind.
      proposedNutrition: summary.isNutrition
          ? ProposedNutritionTarget.fromJson(payloadMap)
          : null,
      proposedFoodLog:
          summary.isFoodLog ? ProposedFoodLog.fromJson(payloadMap) : null,
      proposedWorkoutLog:
          summary.isWorkoutLog ? ProposedWorkoutLog.fromJson(payloadMap) : null,
      proposedFoodLogRevision: summary.isFoodLogRevision
          ? ProposedFoodLogRevision.fromJson(
              payloadMap,
              isDelete: summary.isFoodLogDelete,
            )
          : null,
    );
  }

  @override
  List<Object?> get props => [
    summary,
    description,
    proposedExercises,
    resolvedExercises,
    baseTemplateUpdatedAt,
    appliedResult,
    proposedNutrition,
    proposedFoodLog,
    proposedWorkoutLog,
    proposedFoodLogRevision,
  ];
}
