enum ProposalKind {
  nutritionTargets,
  foodLog,
  foodLogEdit,
  foodLogDelete,
  templateCreate,
  templateEdit,
}

enum ProposalStatus { pending, applied, rejected, conflicted }

class ExerciseFixture {
  const ExerciseFixture({
    required this.id,
    required this.slug,
    required this.name,
    required this.muscles,
    required this.loggingMode,
  });

  final String id;
  final String slug;
  final String name;
  final List<String> muscles;
  final String loggingMode;
}

class NutritionTargets {
  const NutritionTargets({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final int calories;
  final double protein;
  final double carbs;
  final double fat;

  Map<String, Object?> toJson() => {
    'calories': calories,
    'proteinGrams': protein,
    'carbsGrams': carbs,
    'fatGrams': fat,
  };
}

class FoodLogEntry {
  const FoodLogEntry({
    required this.id,
    required this.date,
    required this.consumedAt,
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

  final String id;
  final String date;
  final DateTime consumedAt;
  final String foodName;
  final double servingGrams;
  final double calories;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;
  final double? fiberGrams;
  final double? sugarGrams;
  final double? sodiumMg;

  FoodLogEntry copyWith(Map<String, Object?> changes) => FoodLogEntry(
    id: id,
    date: date,
    consumedAt: consumedAt,
    foodName: changes['foodName'] as String? ?? foodName,
    servingGrams: (changes['servingGrams'] as num?)?.toDouble() ?? servingGrams,
    calories: (changes['calories'] as num?)?.toDouble() ?? calories,
    proteinGrams: (changes['proteinGrams'] as num?)?.toDouble() ?? proteinGrams,
    carbsGrams: (changes['carbsGrams'] as num?)?.toDouble() ?? carbsGrams,
    fatGrams: (changes['fatGrams'] as num?)?.toDouble() ?? fatGrams,
    fiberGrams: (changes['fiberGrams'] as num?)?.toDouble() ?? fiberGrams,
    sugarGrams: (changes['sugarGrams'] as num?)?.toDouble() ?? sugarGrams,
    sodiumMg: (changes['sodiumMg'] as num?)?.toDouble() ?? sodiumMg,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'revisable': true,
    'date': date,
    'consumedAt': consumedAt.toUtc().toIso8601String(),
    'foodName': foodName,
    'servingGrams': servingGrams,
    'calories': calories,
    'proteinGrams': proteinGrams,
    'carbsGrams': carbsGrams,
    'fatGrams': fatGrams,
    'fiberGrams': fiberGrams,
    'sugarGrams': sugarGrams,
    'sodiumMg': sodiumMg,
    'source': 'evaluator_fixture',
  };
}

class WorkoutTemplate {
  const WorkoutTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.exercises,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? description;
  final List<Map<String, Object?>> exercises;
  final DateTime updatedAt;

  Map<String, Object?> toPlanJson() => {
    'name': name,
    if (description != null) 'description': description,
    'exercises': exercises,
  };
}

class CoachProposal {
  const CoachProposal({
    required this.id,
    required this.kind,
    required this.title,
    required this.payload,
    required this.createdAt,
    this.status = ProposalStatus.pending,
    this.decidedAt,
  });

  final String id;
  final ProposalKind kind;
  final String title;
  final Map<String, Object?> payload;
  final DateTime createdAt;
  final ProposalStatus status;
  final DateTime? decidedAt;

  CoachProposal decide(ProposalStatus next, DateTime at) => CoachProposal(
    id: id,
    kind: kind,
    title: title,
    payload: payload,
    createdAt: createdAt,
    status: next,
    decidedAt: at,
  );

  Map<String, Object?> toSummaryJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'status': status.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (decidedAt != null) 'decidedAt': decidedAt!.toUtc().toIso8601String(),
    'autoApplied': false,
  };
}
