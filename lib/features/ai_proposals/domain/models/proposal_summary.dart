import 'package:equatable/equatable.dart';

/// The kind of write a proposal represents.
enum ProposalKind {
  templateCreate,
  templateEdit,
  nutritionTargets,
  foodLog,
  workoutLog,
  foodLogEdit,
  foodLogDelete,
  unknown,
}

ProposalKind proposalKindFromString(String? raw) {
  switch (raw) {
    case 'template_create':
      return ProposalKind.templateCreate;
    case 'template_edit':
      return ProposalKind.templateEdit;
    case 'nutrition_targets':
      return ProposalKind.nutritionTargets;
    case 'food_log':
      return ProposalKind.foodLog;
    case 'workout_log':
      return ProposalKind.workoutLog;
    case 'food_log_edit':
      return ProposalKind.foodLogEdit;
    case 'food_log_delete':
      return ProposalKind.foodLogDelete;
    default:
      return ProposalKind.unknown;
  }
}

/// A lightweight proposal row for the inbox list.
///
/// Mirrors the backend `ProposalSummary` contract:
/// `{ id, kind, status, templateName, exerciseCount, targetTemplateId,
///    summary, conflictReason, createdAt, expiresAt }`.
class ProposalSummary extends Equatable {
  const ProposalSummary({
    required this.id,
    required this.kind,
    required this.status,
    required this.templateName,
    required this.exerciseCount,
    required this.createdAt,
    this.targetTemplateId,
    this.summary,
    this.conflictReason,
    this.expiresAt,
    this.decidedAt,
    this.autoApplied = false,
    this.autoSource,
  });

  final String id;
  final ProposalKind kind;
  final String status;
  final String templateName;
  final int exerciseCount;
  final String? targetTemplateId;
  final String? summary;
  final String? conflictReason;
  final DateTime createdAt;
  final DateTime? expiresAt;

  /// When this proposal reached its terminal state (applied/reverted/rejected/
  /// expired). Null for still-pending proposals.
  final DateTime? decidedAt;
  final bool autoApplied;
  final String? autoSource;

  bool get isFirstPartyWebAutoLog =>
      autoApplied && autoSource == 'first_party_webmcp' && isFoodLog;

  bool get isEdit => kind == ProposalKind.templateEdit;
  bool get isNutrition => kind == ProposalKind.nutritionTargets;
  bool get isFoodLog => kind == ProposalKind.foodLog;
  bool get isWorkoutLog => kind == ProposalKind.workoutLog;

  /// A correction (edit) or removal (delete) of an EXISTING diary entry, as
  /// opposed to an add (`foodLog`). Both revise the food diary and are undoable.
  bool get isFoodLogEdit => kind == ProposalKind.foodLogEdit;
  bool get isFoodLogDelete => kind == ProposalKind.foodLogDelete;
  bool get isFoodLogRevision => isFoodLogEdit || isFoodLogDelete;

  /// Whether this proposal writes to the food diary (add OR revise) — used to
  /// route the diary refresh after approve/undo.
  bool get touchesFoodDiary => isFoodLog || isFoodLogRevision;

  /// Log kinds (food add/edit/delete + workout log) WRITE diary/history data on
  /// approve and are the kinds that support post-apply undo.
  bool get isLog => isFoodLog || isWorkoutLog || isFoodLogRevision;
  bool get isPending => status == 'pending';
  bool get isApplied => status == 'applied';

  /// Whether a history row can still offer an inline Undo — only applied log
  /// kinds (food add/edit/delete + workout log) support post-apply revert.
  bool get isRevertable => isApplied && isLog;

  static DateTime _parseDate(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw)?.toLocal() ?? DateTime.now();
    }
    return DateTime.now();
  }

  static DateTime? _parseNullableDate(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw)?.toLocal();
    }
    return null;
  }

  factory ProposalSummary.fromJson(Map<String, dynamic> json) {
    return ProposalSummary(
      id: json['id']?.toString() ?? '',
      kind: proposalKindFromString(json['kind']?.toString()),
      status: json['status']?.toString() ?? 'pending',
      templateName: json['templateName']?.toString() ?? 'Untitled template',
      exerciseCount: (json['exerciseCount'] as num?)?.toInt() ?? 0,
      targetTemplateId: json['targetTemplateId']?.toString(),
      summary: json['summary']?.toString(),
      conflictReason: json['conflictReason']?.toString(),
      createdAt: _parseDate(json['createdAt']),
      expiresAt: _parseNullableDate(json['expiresAt']),
      decidedAt: _parseNullableDate(json['decidedAt']),
      autoApplied: json['autoApplied'] == true,
      autoSource: json['autoSource']?.toString(),
    );
  }

  /// Returns a copy with [status] and/or [decidedAt] replaced (used by the
  /// history cubit to flip a just-reverted row locally without a re-fetch —
  /// the server stamps a fresh `decided_at` on revert, so the local copy
  /// advances its terminal time to match).
  ProposalSummary copyWith({String? status, DateTime? decidedAt}) {
    return ProposalSummary(
      id: id,
      kind: kind,
      status: status ?? this.status,
      templateName: templateName,
      exerciseCount: exerciseCount,
      createdAt: createdAt,
      targetTemplateId: targetTemplateId,
      summary: summary,
      conflictReason: conflictReason,
      expiresAt: expiresAt,
      decidedAt: decidedAt ?? this.decidedAt,
      autoApplied: autoApplied,
      autoSource: autoSource,
    );
  }

  @override
  List<Object?> get props => [
    id,
    kind,
    status,
    templateName,
    exerciseCount,
    targetTemplateId,
    summary,
    conflictReason,
    createdAt,
    expiresAt,
    decidedAt,
    autoApplied,
    autoSource,
  ];
}
