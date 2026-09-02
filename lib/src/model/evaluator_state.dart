import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

class EvaluatorState extends ChangeNotifier {
  EvaluatorState({DateTime? anchor})
    : anchor = anchor ?? DateTime(2026, 8, 31),
      nutritionTargets = const NutritionTargets(
        calories: 2400,
        protein: 170,
        carbs: 260,
        fat: 75,
      ),
      foodEntries = [
        FoodLogEntry(
          id: '00000000-0000-4000-8000-000000000001',
          date: '2026-08-31',
          consumedAt: DateTime.utc(2026, 8, 31, 1, 15),
          foodName: 'Greek yogurt bowl',
          servingGrams: 420,
          calories: 520,
          proteinGrams: 45,
          carbsGrams: 62,
          fatGrams: 12,
          fiberGrams: 8,
          sugarGrams: 21,
          sodiumMg: 240,
        ),
        FoodLogEntry(
          id: '00000000-0000-4000-8000-000000000002',
          date: '2026-08-31',
          consumedAt: DateTime.utc(2026, 8, 31, 5, 30),
          foodName: 'Chicken rice',
          servingGrams: 610,
          calories: 910,
          proteinGrams: 73,
          carbsGrams: 80,
          fatGrams: 36,
          fiberGrams: 5,
          sugarGrams: 6,
          sodiumMg: 1320,
        ),
      ],
      templates = [
        WorkoutTemplate(
          id: 'template-strength-a',
          name: 'Strength foundation',
          description: 'Three-day strength baseline',
          exercises: const [
            {
              'exerciseId': 'barbell-back-squat',
              'slug': 'barbell-back-squat',
              'sets': 4,
              'repsTarget': 6,
              'weightTarget': 100,
              'rpeTarget': 8,
              'restTimerSeconds': 180,
            },
            {
              'exerciseId': 'barbell-bench-press',
              'slug': 'barbell-bench-press',
              'sets': 4,
              'repsTarget': 6,
              'weightTarget': 82.5,
              'rpeTarget': 8,
              'restTimerSeconds': 180,
            },
          ],
          updatedAt: DateTime.utc(2026, 8, 30, 12),
        ),
      ];

  final DateTime anchor;
  NutritionTargets nutritionTargets;
  final List<FoodLogEntry> foodEntries;
  final List<WorkoutTemplate> templates;
  final List<CoachProposal> proposals = [];
  List<ExerciseFixture> exercises = const [];
  int _nextProposal = 1;
  int _nextFoodEntry = 3;
  int _nextTemplate = 1;

  Future<void> loadFixtures() async {
    final raw = await rootBundle.loadString('assets/data/exercises.json');
    final decoded = jsonDecode(raw) as List<Object?>;
    exercises = decoded
        .map((item) {
          final map = item! as Map<String, Object?>;
          return ExerciseFixture(
            id: map['id']! as String,
            slug: map['slug']! as String,
            name: map['name']! as String,
            muscles: (map['muscles']! as List<Object?>).cast<String>(),
            loggingMode: map['loggingMode']! as String,
          );
        })
        .toList(growable: false);
    notifyListeners();
  }

  List<CoachProposal> get pending => proposals
      .where((proposal) => proposal.status == ProposalStatus.pending)
      .toList(growable: false);

  List<CoachProposal> get recent => proposals
      .where((proposal) => proposal.status != ProposalStatus.pending)
      .toList(growable: false)
      .reversed
      .take(10)
      .toList(growable: false);

  Iterable<FoodLogEntry> get todayFoodEntries {
    final date =
        '${anchor.year.toString().padLeft(4, '0')}-'
        '${anchor.month.toString().padLeft(2, '0')}-'
        '${anchor.day.toString().padLeft(2, '0')}';
    return foodEntries.where((entry) => entry.date == date);
  }

  double get todayCalories =>
      todayFoodEntries.fold(0, (sum, entry) => sum + entry.calories);

  double get todayProtein =>
      todayFoodEntries.fold(0, (sum, entry) => sum + entry.proteinGrams);

  double get todayCarbs =>
      todayFoodEntries.fold(0, (sum, entry) => sum + entry.carbsGrams);

  double get todayFat =>
      todayFoodEntries.fold(0, (sum, entry) => sum + entry.fatGrams);

  CoachProposal? proposalById(String id) {
    for (final proposal in proposals) {
      if (proposal.id == id) return proposal;
    }
    return null;
  }

  WorkoutTemplate? templateById(String id) {
    for (final template in templates) {
      if (template.id == id) return template;
    }
    return null;
  }

  CoachProposal propose(
    ProposalKind kind,
    String title,
    Map<String, Object?> payload,
  ) {
    final existing = matchingProposal(kind, payload);
    if (existing != null) return existing;
    if (pending.length >= 20) {
      throw StateError('pending_cap_exceeded');
    }
    final proposal = CoachProposal(
      id: 'proposal-${_nextProposal++}',
      kind: kind,
      title: title,
      payload: Map.unmodifiable(_proposalPayload(kind, payload)),
      createdAt: anchor.add(Duration(minutes: proposals.length + 1)),
    );
    proposals.add(proposal);
    notifyListeners();
    return proposal;
  }

  CoachProposal? matchingProposal(
    ProposalKind kind,
    Map<String, Object?> payload,
  ) {
    final signature = _proposalSignature(kind, payload);
    for (final existing in proposals) {
      if (_proposalSignature(existing.kind, existing.payload) == signature) {
        return existing;
      }
    }
    return null;
  }

  Map<String, Object?> _proposalPayload(
    ProposalKind kind,
    Map<String, Object?> payload,
  ) {
    final stored = Map<String, Object?>.from(payload);
    switch (kind) {
      case ProposalKind.nutritionTargets:
        stored['baseTargets'] = nutritionTargets.toJson();
      case ProposalKind.foodLogEdit || ProposalKind.foodLogDelete:
        final targetId = stored['targetEntryId'];
        if (targetId is String) {
          final target = foodEntries
              .where((entry) => entry.id == targetId)
              .firstOrNull;
          if (target != null) stored['targetEntrySnapshot'] = target.toJson();
        }
      case ProposalKind.templateEdit:
        final templateId = stored['targetTemplateId'];
        if (templateId is String) {
          final target = templateById(templateId);
          if (target != null) {
            stored['baseUpdatedAt'] = target.updatedAt
                .toUtc()
                .toIso8601String();
          }
        }
      case ProposalKind.foodLog || ProposalKind.templateCreate:
        break;
    }
    return stored;
  }

  String _proposalSignature(ProposalKind kind, Map<String, Object?> payload) {
    final publicPayload = Map<String, Object?>.from(payload)
      ..remove('baseTargets')
      ..remove('targetEntrySnapshot')
      ..remove('baseUpdatedAt');
    return jsonEncode(
      _canonicalJson({'kind': kind.name, 'payload': publicPayload}),
    );
  }

  Object? _canonicalJson(Object? value) {
    if (value is List) {
      return value.map(_canonicalJson).toList(growable: false);
    }
    if (value is Map) {
      final map = Map<String, Object?>.from(value);
      final keys = map.keys.toList(growable: false)..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalJson(map[key]),
      };
    }
    return value;
  }

  void apply(String id) {
    final index = proposals.indexWhere((proposal) => proposal.id == id);
    if (index < 0 || proposals[index].status != ProposalStatus.pending) return;
    final proposal = proposals[index];
    switch (proposal.kind) {
      case ProposalKind.nutritionTargets:
        if (!_sameSnapshot(
          nutritionTargets.toJson(),
          proposal.payload['baseTargets'],
        )) {
          _markConflicted(index, proposal);
          return;
        }
        nutritionTargets = NutritionTargets(
          calories: proposal.payload['caloriesTarget']! as int,
          protein: (proposal.payload['proteinTarget']! as num).toDouble(),
          carbs: (proposal.payload['carbsTarget']! as num).toDouble(),
          fat: (proposal.payload['fatTarget']! as num).toDouble(),
        );
        break;
      case ProposalKind.foodLog:
        final date = proposal.payload['date']! as String;
        final items = (proposal.payload['items']! as List<Object?>)
            .cast<Map<String, Object?>>();
        for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
          final item = items[itemIndex];
          final serial = _nextFoodEntry++;
          foodEntries.add(
            FoodLogEntry(
              id: '00000000-0000-4000-8000-${serial.toString().padLeft(12, '0')}',
              date: date,
              consumedAt: DateTime.parse(
                '${date}T12:00:00.000Z',
              ).add(Duration(minutes: itemIndex)),
              foodName: item['foodName']! as String,
              servingGrams: (item['servingGrams']! as num).toDouble(),
              calories: (item['calories']! as num).toDouble(),
              proteinGrams: (item['proteinGrams']! as num).toDouble(),
              carbsGrams: (item['carbsGrams']! as num).toDouble(),
              fatGrams: (item['fatGrams']! as num).toDouble(),
              fiberGrams: (item['fiberGrams'] as num?)?.toDouble(),
              sugarGrams: (item['sugarGrams'] as num?)?.toDouble(),
              sodiumMg: (item['sodiumMg'] as num?)?.toDouble(),
            ),
          );
        }
        break;
      case ProposalKind.foodLogEdit:
        final targetId = proposal.payload['targetEntryId']! as String;
        final targetIndex = foodEntries.indexWhere(
          (entry) => entry.id == targetId,
        );
        if (targetIndex < 0 ||
            !_sameSnapshot(
              foodEntries[targetIndex].toJson(),
              proposal.payload['targetEntrySnapshot'],
            )) {
          _markConflicted(index, proposal);
          return;
        }
        foodEntries[targetIndex] = foodEntries[targetIndex].copyWith(
          (proposal.payload['changes']! as Map).cast<String, Object?>(),
        );
        break;
      case ProposalKind.foodLogDelete:
        final targetId = proposal.payload['targetEntryId']! as String;
        final targetIndex = foodEntries.indexWhere(
          (entry) => entry.id == targetId,
        );
        if (targetIndex < 0 ||
            !_sameSnapshot(
              foodEntries[targetIndex].toJson(),
              proposal.payload['targetEntrySnapshot'],
            )) {
          _markConflicted(index, proposal);
          return;
        }
        foodEntries.removeAt(targetIndex);
        break;
      case ProposalKind.templateCreate:
        final plan = proposal.payload['plan']! as Map<String, Object?>;
        templates.add(
          WorkoutTemplate(
            id: 'template-created-${_nextTemplate++}',
            name: plan['name']! as String,
            description: plan['description'] as String?,
            exercises: (plan['exercises']! as List<Object?>)
                .cast<Map<String, Object?>>(),
            updatedAt: anchor.add(Duration(minutes: 30 + templates.length)),
          ),
        );
        break;
      case ProposalKind.templateEdit:
        final templateId = proposal.payload['targetTemplateId']! as String;
        final templateIndex = templates.indexWhere(
          (template) => template.id == templateId,
        );
        final expectedVersion = proposal.payload['baseUpdatedAt'];
        if (templateIndex < 0 ||
            expectedVersion is! String ||
            templates[templateIndex].updatedAt.toUtc().toIso8601String() !=
                expectedVersion) {
          _markConflicted(index, proposal);
          return;
        }
        final plan = proposal.payload['plan']! as Map<String, Object?>;
        templates[templateIndex] = WorkoutTemplate(
          id: templateId,
          name: plan['name']! as String,
          description: plan['description'] as String?,
          exercises: (plan['exercises']! as List<Object?>)
              .cast<Map<String, Object?>>(),
          updatedAt: anchor.add(Duration(minutes: 60 + proposals.length)),
        );
        break;
    }
    proposals[index] = proposal.decide(
      ProposalStatus.applied,
      anchor.add(Duration(hours: 1, minutes: proposals.length)),
    );
    notifyListeners();
  }

  bool _sameSnapshot(Map<String, Object?> current, Object? expected) =>
      expected is Map &&
      jsonEncode(current) == jsonEncode(Map<String, Object?>.from(expected));

  void _markConflicted(int index, CoachProposal proposal) {
    proposals[index] = proposal.decide(
      ProposalStatus.conflicted,
      anchor.add(Duration(hours: 1, minutes: proposals.length)),
    );
    notifyListeners();
  }

  void dismiss(String id) {
    final index = proposals.indexWhere((proposal) => proposal.id == id);
    if (index < 0 || proposals[index].status != ProposalStatus.pending) return;
    proposals[index] = proposals[index].decide(
      ProposalStatus.rejected,
      anchor.add(Duration(hours: 1, minutes: proposals.length)),
    );
    notifyListeners();
  }
}
