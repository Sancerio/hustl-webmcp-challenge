import 'proposal_detail.dart';

class NutritionProposalInput {
  const NutritionProposalInput({
    required this.caloriesTarget,
    required this.proteinTarget,
    required this.carbsTarget,
    required this.fatTarget,
    this.rationale,
  });

  final int caloriesTarget;
  final double proteinTarget;
  final double carbsTarget;
  final double fatTarget;
  final String? rationale;

  Map<String, Object?> toJson() => {
    'caloriesTarget': caloriesTarget,
    'proteinTarget': proteinTarget,
    'carbsTarget': carbsTarget,
    'fatTarget': fatTarget,
    if (rationale != null && rationale!.isNotEmpty) 'rationale': rationale,
  };
}

class NutritionProposalResult {
  const NutritionProposalResult({
    required this.status,
    required this.proposalId,
    required this.proposal,
  });

  final String status;
  final String proposalId;
  final ProposalDetail proposal;

  bool get isDuplicate => status == 'duplicate';
}
