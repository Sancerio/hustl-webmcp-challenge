import 'package:equatable/equatable.dart';

/// A single exercise inside a proposed template plan.
///
/// Mirrors `proposedExercises[]` from the backend `ProposalDetail`:
/// `{exerciseId, sets, restTimerSeconds, repsTarget?, weightTarget?,
///   rpeTarget?, slug?, notes?}`. NOTE: `exerciseId` is the exercise NAME
/// (free text), not a stable id.
class ProposedExercise extends Equatable {
  const ProposedExercise({
    required this.name,
    required this.sets,
    required this.restTimerSeconds,
    this.repsTarget,
    this.weightTarget,
    this.rpeTarget,
    this.slug,
    this.notes,
  });

  /// The exercise name (free text) — the backend ships this as `exerciseId`.
  final String name;
  final int sets;
  final int restTimerSeconds;
  final int? repsTarget;
  final double? weightTarget;
  final double? rpeTarget;
  final String? slug;
  final String? notes;

  factory ProposedExercise.fromJson(Map<String, dynamic> json) {
    return ProposedExercise(
      name: json['exerciseId']?.toString() ?? '',
      sets: (json['sets'] as num?)?.toInt() ?? 1,
      restTimerSeconds: (json['restTimerSeconds'] as num?)?.toInt() ?? 0,
      repsTarget: (json['repsTarget'] as num?)?.toInt(),
      weightTarget: (json['weightTarget'] as num?)?.toDouble(),
      rpeTarget: (json['rpeTarget'] as num?)?.toDouble(),
      slug: json['slug']?.toString(),
      notes: json['notes']?.toString(),
    );
  }

  /// Adapts this proposed exercise into the opaque Map shape the existing
  /// template-detail widgets render: `{exerciseId:<name>, sets:int,
  /// restTimerSeconds:int, notes?, previousSets:[...]}`. The synthesized
  /// `previousSets` entries carry the proposed reps/rpe/weight, and `notes` is
  /// surfaced at the top level, so the approval tile discloses EVERYTHING apply
  /// persists into the template (apply maps weightTarget + notes into the saved
  /// sets) — nothing is applied that the user didn't see.
  Map<String, dynamic> toRenderMap() {
    final reps = repsTarget ?? 0;
    final rpe = rpeTarget?.round();
    final trimmedNotes = notes?.trim();
    return {
      'exerciseId': name,
      'sets': sets,
      'restTimerSeconds': restTimerSeconds,
      if (trimmedNotes != null && trimmedNotes.isNotEmpty) 'notes': trimmedNotes,
      'previousSets': [
        for (var i = 0; i < sets; i++)
          {
            'reps': reps,
            if (rpe != null) 'rpe': rpe,
            'weight': weightTarget ?? 0.0,
          },
      ],
    };
  }

  @override
  List<Object?> get props => [
    name,
    sets,
    restTimerSeconds,
    repsTarget,
    weightTarget,
    rpeTarget,
    slug,
    notes,
  ];
}

/// How a proposed exercise name resolved AS OF PROPOSAL TIME (not a guarantee
/// at apply time — see the spec's `resolvedExercisesAsOfProposal`).
enum ResolvedAs { catalog, existingCustom, willCreateCustom, unknown }

ResolvedAs resolvedAsFromString(String? raw) {
  switch (raw) {
    case 'catalog':
      return ResolvedAs.catalog;
    case 'existing_custom':
      return ResolvedAs.existingCustom;
    case 'will_create_custom':
      return ResolvedAs.willCreateCustom;
    default:
      return ResolvedAs.unknown;
  }
}

/// A proposal-time snapshot of how a name resolved.
class ResolvedExercise extends Equatable {
  const ResolvedExercise({
    required this.name,
    required this.resolvedAs,
    this.exerciseId,
    this.slug,
  });

  final String name;
  final ResolvedAs resolvedAs;
  final String? exerciseId;
  final String? slug;

  bool get willCreateCustom => resolvedAs == ResolvedAs.willCreateCustom;

  factory ResolvedExercise.fromJson(Map<String, dynamic> json) {
    return ResolvedExercise(
      name: json['name']?.toString() ?? '',
      resolvedAs: resolvedAsFromString(json['resolvedAs']?.toString()),
      exerciseId: json['exerciseId']?.toString(),
      slug: json['slug']?.toString(),
    );
  }

  @override
  List<Object?> get props => [name, resolvedAs, exerciseId, slug];
}
