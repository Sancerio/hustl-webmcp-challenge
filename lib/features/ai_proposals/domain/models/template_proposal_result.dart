import 'package:equatable/equatable.dart';

import 'proposal_detail.dart';

class TemplateProposalConflict implements Exception {
  const TemplateProposalConflict();
}

class ProposalUnavailable implements Exception {
  const ProposalUnavailable(this.code);

  final String code;
}

class TemplateProposalUnavailable extends ProposalUnavailable {
  const TemplateProposalUnavailable(super.code);
}

class TemplateProposalExercise extends Equatable {
  const TemplateProposalExercise({
    required this.exerciseId,
    required this.sets,
    required this.restTimerSeconds,
    this.slug,
    this.repsTarget,
    this.weightTarget,
    this.rpeTarget,
    this.notes,
  });

  final String exerciseId;
  final String? slug;
  final int sets;
  final int? repsTarget;
  final int restTimerSeconds;
  final double? weightTarget;
  final int? rpeTarget;
  final String? notes;

  Map<String, Object?> toJson() => {
    'exerciseId': exerciseId,
    if (slug != null) 'slug': slug,
    'sets': sets,
    if (repsTarget != null) 'repsTarget': repsTarget,
    'restTimerSeconds': restTimerSeconds,
    if (weightTarget != null) 'weightTarget': weightTarget,
    if (rpeTarget != null) 'rpeTarget': rpeTarget,
    if (notes != null) 'notes': notes,
  };

  @override
  List<Object?> get props => [
    exerciseId,
    slug,
    sets,
    repsTarget,
    restTimerSeconds,
    weightTarget,
    rpeTarget,
    notes,
  ];
}

class TemplateProposalPlan extends Equatable {
  const TemplateProposalPlan({
    required this.name,
    required this.exercises,
    this.description,
  });

  final String name;
  final String? description;
  final List<TemplateProposalExercise> exercises;

  Map<String, Object?> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    'exercises': exercises
        .map((exercise) => exercise.toJson())
        .toList(growable: false),
  };

  @override
  List<Object?> get props => [name, description, exercises];
}

class TemplateProposalResult {
  const TemplateProposalResult({
    required this.status,
    required this.proposalId,
    required this.proposal,
  });

  final String status;
  final String proposalId;
  final ProposalDetail proposal;
}
