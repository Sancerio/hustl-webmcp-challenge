import 'package:equatable/equatable.dart';

import 'proposal_detail.dart';

class FoodLogRevisionChanges extends Equatable {
  const FoodLogRevisionChanges({
    this.foodName,
    this.servingGrams,
    this.calories,
    this.proteinGrams,
    this.carbsGrams,
    this.fatGrams,
    this.fiberGrams,
    this.sugarGrams,
    this.sodiumMg,
  });

  final String? foodName;
  final double? servingGrams;
  final double? calories;
  final double? proteinGrams;
  final double? carbsGrams;
  final double? fatGrams;
  final double? fiberGrams;
  final double? sugarGrams;
  final double? sodiumMg;

  bool get isEmpty => toJson().isEmpty;

  Map<String, Object?> toJson() => {
    if (foodName != null) 'foodName': foodName,
    if (servingGrams != null) 'servingGrams': servingGrams,
    if (calories != null) 'calories': calories,
    if (proteinGrams != null) 'proteinGrams': proteinGrams,
    if (carbsGrams != null) 'carbsGrams': carbsGrams,
    if (fatGrams != null) 'fatGrams': fatGrams,
    if (fiberGrams != null) 'fiberGrams': fiberGrams,
    if (sugarGrams != null) 'sugarGrams': sugarGrams,
    if (sodiumMg != null) 'sodiumMg': sodiumMg,
  };

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

class FoodLogEditProposalInput extends Equatable {
  const FoodLogEditProposalInput({
    required this.targetEntryId,
    required this.changes,
  });

  final String targetEntryId;
  final FoodLogRevisionChanges changes;

  Map<String, Object?> toJson() => {
    'targetEntryId': targetEntryId,
    'changes': changes.toJson(),
  };

  @override
  List<Object?> get props => [targetEntryId, changes];
}

class FoodLogDeleteProposalInput extends Equatable {
  const FoodLogDeleteProposalInput({required this.targetEntryId});

  final String targetEntryId;

  Map<String, Object?> toJson() => {'targetEntryId': targetEntryId};

  @override
  List<Object?> get props => [targetEntryId];
}

class FoodLogRevisionProposalResult {
  const FoodLogRevisionProposalResult({
    required this.status,
    required this.proposalId,
    required this.proposal,
    this.humanMessage,
  });

  final String status;
  final String proposalId;
  final ProposalDetail proposal;
  final String? humanMessage;

  bool get requiresHumanReview => status != 'applied';
}

class FoodLogRevisionTargetUnavailable implements Exception {
  const FoodLogRevisionTargetUnavailable();
}
