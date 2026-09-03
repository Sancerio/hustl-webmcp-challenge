import 'package:equatable/equatable.dart';

import 'proposal_detail.dart';

class FoodLogProposalItem extends Equatable {
  const FoodLogProposalItem({
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

  Map<String, Object?> toJson() => {
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

class FoodLogProposalInput extends Equatable {
  const FoodLogProposalInput({
    required this.date,
    required this.items,
    this.note,
  });

  /// Explicit user-local calendar date in YYYY-MM-DD form.
  final String date;
  final List<FoodLogProposalItem> items;
  final String? note;

  Map<String, Object?> toJson() => {
    'date': date,
    'items': items.map((item) => item.toJson()).toList(growable: false),
    if (note != null && note!.isNotEmpty) 'note': note,
  };

  @override
  List<Object?> get props => [date, items, note];
}

class FoodLogProposalResult {
  const FoodLogProposalResult({
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
