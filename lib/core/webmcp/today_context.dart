class HustlTodayContext {
  const HustlTodayContext({
    required this.status,
    required this.asOf,
    required this.training,
    required this.recovery,
    required this.nutrition,
    required this.coach,
    required this.unavailableSections,
  });

  static const availableSurfaces = ['train', 'recovery', 'nutrition', 'coach'];

  final String status;
  final String asOf;
  final TrainingTodayContext training;
  final RecoveryTodayContext recovery;
  final NutritionTodayContext nutrition;
  final CoachTodayContext coach;
  final List<String> unavailableSections;

  Map<String, Object?> toJson() => {
    'status': status,
    'asOf': asOf,
    'training': training.toJson(),
    'recovery': recovery.toJson(),
    'nutrition': nutrition.toJson(),
    'coach': coach.toJson(),
    'availableSurfaces': availableSurfaces,
    'unavailableSections': unavailableSections,
  };
}

class TrainingTodayContext {
  const TrainingTodayContext({
    required this.state,
    this.activeSessionId,
    this.activeSessionName,
    this.recommendedSessionId,
    this.recommendedSessionName,
  });

  final String state;
  final String? activeSessionId;
  final String? activeSessionName;
  final String? recommendedSessionId;
  final String? recommendedSessionName;

  Map<String, Object?> toJson() => {
    'state': state,
    'activeSessionId': activeSessionId,
    'activeSessionName': activeSessionName,
    'recommendedSessionId': recommendedSessionId,
    'recommendedSessionName': recommendedSessionName,
  };
}

class RecoveryTodayContext {
  const RecoveryTodayContext({
    required this.state,
    this.date,
    this.score,
    this.flowBand,
    this.confidence,
    this.sleepHours,
    this.providerState,
    this.missingSignals = const [],
    this.baselineCoverageDays,
  });

  final String state;
  final String? date;
  final double? score;
  final String? flowBand;
  final String? confidence;
  final double? sleepHours;
  final String? providerState;
  final List<String> missingSignals;
  final int? baselineCoverageDays;

  Map<String, Object?> toJson() => {
    'state': state,
    'date': date,
    'score': score,
    'flowBand': flowBand,
    'confidence': confidence,
    'sleepHours': sleepHours,
    'providerState': providerState,
    'missingSignals': missingSignals,
    'baselineCoverageDays': baselineCoverageDays,
  };
}

class NutritionTodayContext {
  const NutritionTodayContext({
    required this.state,
    required this.targetState,
    this.calories,
    this.proteinGrams,
    this.carbsGrams,
    this.fatGrams,
    this.caloriesTarget,
    this.proteinTarget,
    this.carbsTarget,
    this.fatTarget,
  });

  final String state;
  final String targetState;
  final double? calories;
  final double? proteinGrams;
  final double? carbsGrams;
  final double? fatGrams;
  final double? caloriesTarget;
  final double? proteinTarget;
  final double? carbsTarget;
  final double? fatTarget;

  Map<String, Object?> toJson() => {
    'state': state,
    'targetState': targetState,
    'calories': calories,
    'proteinGrams': proteinGrams,
    'carbsGrams': carbsGrams,
    'fatGrams': fatGrams,
    'caloriesTarget': caloriesTarget,
    'proteinTarget': proteinTarget,
    'carbsTarget': carbsTarget,
    'fatTarget': fatTarget,
  };
}

class CoachTodayContext {
  const CoachTodayContext({required this.state, this.pendingProposalCount});

  final String state;
  final int? pendingProposalCount;

  Map<String, Object?> toJson() => {
    'state': state,
    'pendingProposalCount': pendingProposalCount,
  };
}
