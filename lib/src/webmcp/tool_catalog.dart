import '../model/evaluator_state.dart';
import '../model/models.dart';
import 'context_payloads.dart';
import 'schemas.dart';
import 'tool.dart';
import 'validation.dart';

typedef CurrentRoute = String Function();
typedef CurrentGeneration = int Function();
typedef Navigate = void Function(String route);

class ToolCatalog {
  ToolCatalog({
    required this.state,
    required this.currentRoute,
    required this.currentGeneration,
    required this.navigate,
  });

  final EvaluatorState state;
  final CurrentRoute currentRoute;
  final CurrentGeneration currentGeneration;
  final Navigate navigate;

  String registrationScopeForRoute(String route) =>
      _isCoachRoute(route) ? 'coach' : route;

  List<ToolDefinition> forRoute(String route, int generation) {
    final tools = <ToolDefinition>[
      _tool(
        route,
        generation,
        name: 'hustl_get_today_context',
        title: 'Get today in Hustl',
        description:
            'Read a bounded synthetic summary across training, recovery, nutrition, and coaching.',
        schema: emptySchema,
        readOnly: true,
        action: (_) async => todayContext(state),
      ),
      _tool(
        route,
        generation,
        name: 'hustl_open_surface',
        title: 'Open a Hustl surface',
        description:
            'Navigate to Train, Recover, Nutrition, Coach, or Templates without writing product data.',
        schema: openSurfaceSchema,
        readOnly: true,
        recheckAfter: false,
        action: _openSurface,
      ),
    ];

    if (route == '/') {
      tools.addAll(_trainingTools(route, generation));
    } else if (route == '/health') {
      tools.add(
        _tool(
          route,
          generation,
          name: 'hustl_get_recovery_context',
          title: 'Get recovery context',
          description:
              'Read bounded synthetic readiness, sleep, HRV, resting heart rate, baselines, and missing signals.',
          schema: emptySchema,
          readOnly: true,
          action: (_) async => recoveryContext(state),
        ),
      );
    } else if (route == '/nutrition') {
      tools.addAll(_nutritionTools(route, generation));
    } else if (_isCoachRoute(route)) {
      tools.addAll(_coachTools(route, generation));
    } else if (route == '/templates') {
      tools.add(_templateProposalTool(route, generation));
    } else {
      final templateId = _detailId(route, '/templates/');
      if (templateId != null && state.templateById(templateId) != null) {
        tools.addAll(_templateDetailTools(route, generation, templateId));
      }
    }
    return tools;
  }

  List<ToolDefinition> _trainingTools(String route, int generation) => [
    _tool(
      route,
      generation,
      name: 'hustl_get_training_context',
      title: 'Get training context',
      description:
          'Read the bounded synthetic current training state and recovery-aware recommendation.',
      schema: emptySchema,
      readOnly: true,
      action: (_) async => trainingContext(state),
    ),
    _tool(
      route,
      generation,
      name: 'hustl_get_workout_history',
      title: 'Get workout history',
      description:
          'Read at most 20 synthetic completed-workout summaries. No notes, exercises, or sets are returned.',
      schema: workoutHistorySchema,
      readOnly: true,
      action: _workoutHistory,
    ),
    _tool(
      route,
      generation,
      name: 'hustl_get_exercise_history',
      title: 'Get exercise history',
      description:
          'Read at most 20 aggregate synthetic exercise-history rows without raw sets or identity data.',
      schema: exerciseHistorySchema,
      readOnly: true,
      action: _exerciseHistory,
    ),
  ];

  List<ToolDefinition> _nutritionTools(String route, int generation) => [
    _tool(
      route,
      generation,
      name: 'hustl_get_nutrition_context',
      title: 'Get nutrition context',
      description: 'Read bounded synthetic daily totals and current targets.',
      schema: emptySchema,
      readOnly: true,
      action: (_) async => nutritionContext(state),
    ),
    _tool(
      route,
      generation,
      name: 'hustl_get_food_log_entries',
      title: 'Get food log entries',
      description:
          'Read at most 50 synthetic diary entries for one explicit local date. Only revisable entry ids may be proposed for correction or removal.',
      schema: foodLogEntriesSchema,
      readOnly: true,
      action: _foodLogEntries,
    ),
    _nutritionProposalTool(route, generation),
    _foodProposalTool(route, generation),
    _foodEditProposalTool(route, generation),
    _foodDeleteProposalTool(route, generation),
  ];

  List<ToolDefinition> _coachTools(String route, int generation) => [
    _tool(
      route,
      generation,
      name: 'hustl_get_coach_activity',
      title: 'Get Coach activity',
      description:
          'Read up to 20 pending proposals and 10 recent terminal decisions from this evaluator run.',
      schema: emptySchema,
      readOnly: true,
      action: (_) async => {
        'status': 'ready',
        'pendingCount': state.pending.length,
        'pending': state.pending
            .take(20)
            .map((proposal) => proposal.toSummaryJson())
            .toList(growable: false),
        'recentDecisionCount': state.recent.length,
        'recentDecisions': state.recent
            .map((proposal) => proposal.toSummaryJson())
            .toList(growable: false),
      },
    ),
    _tool(
      route,
      generation,
      name: 'hustl_get_coaching_trends',
      title: 'Get coaching trends',
      description:
          'Compare bounded aggregate training, recovery, and nutrition trends over 7, 30, or 90 days.',
      schema: coachingTrendsSchema,
      readOnly: true,
      action: _coachingTrends,
    ),
    _tool(
      route,
      generation,
      name: 'hustl_open_proposal',
      title: 'Open a Coach proposal',
      description:
          'Open one visible pending proposal for human review. This does not apply or dismiss it.',
      schema: openProposalSchema,
      readOnly: true,
      recheckAfter: false,
      action: _openProposal,
    ),
    _nutritionProposalTool(route, generation),
    _foodProposalTool(route, generation),
  ];

  List<ToolDefinition> _templateDetailTools(
    String route,
    int generation,
    String templateId,
  ) => [
    _tool(
      route,
      generation,
      name: 'hustl_get_template_context',
      title: 'Get visible workout template',
      description:
          'Read the visible synthetic template as complete proposal-valid edit input.',
      schema: emptySchema,
      readOnly: true,
      action: (_) async {
        final template = state.templateById(templateId)!;
        return {
          'status': 'ready',
          'templateId': template.id,
          'updatedAt': template.updatedAt.toUtc().toIso8601String(),
          'editable': true,
          'lossyOnEdit': false,
          'plan': template.toPlanJson(),
        };
      },
    ),
    _tool(
      route,
      generation,
      name: 'hustl_propose_template_edit',
      title: 'Propose changes to this template',
      description:
          'Draft a full replacement for the visible template. It remains pending for human review.',
      schema: templateEditSchema,
      readOnly: false,
      action: (arguments) => _proposeTemplateEdit(templateId, arguments),
    ),
  ];

  ToolDefinition _nutritionProposalTool(String route, int generation) => _tool(
    route,
    generation,
    name: 'hustl_propose_nutrition_targets',
    title: 'Propose nutrition targets',
    description:
        'Create a pending nutrition-target proposal for visible human review. Current targets do not change.',
    schema: nutritionProposalSchema,
    readOnly: false,
    action: _proposeNutrition,
  );

  ToolDefinition _foodProposalTool(String route, int generation) => _tool(
    route,
    generation,
    name: 'hustl_propose_food_log',
    title: 'Propose a food log',
    description:
        'Create a dated food-log proposal. This evaluator always keeps it pending for visible human review.',
    schema: foodProposalSchema,
    readOnly: false,
    action: _proposeFood,
  );

  ToolDefinition _foodEditProposalTool(String route, int generation) => _tool(
    route,
    generation,
    name: 'hustl_propose_food_log_edit',
    title: 'Propose a food log correction',
    description:
        'Correct one synthetic entry returned by hustl_get_food_log_entries. Pass only changed fields. This remains pending for visible human review.',
    schema: foodLogEditProposalSchema,
    readOnly: false,
    action: _proposeFoodEdit,
  );

  ToolDefinition _foodDeleteProposalTool(String route, int generation) => _tool(
    route,
    generation,
    name: 'hustl_propose_food_log_delete',
    title: 'Propose removing a food log entry',
    description:
        'Remove one synthetic entry returned by hustl_get_food_log_entries. This remains pending for visible human review.',
    schema: foodLogDeleteProposalSchema,
    readOnly: false,
    action: _proposeFoodDelete,
  );

  ToolDefinition _templateProposalTool(String route, int generation) => _tool(
    route,
    generation,
    name: 'hustl_propose_template',
    title: 'Propose a workout template',
    description:
        'Create a pending workout-template proposal. This invocation never creates a live template.',
    schema: templateProposalSchema,
    readOnly: false,
    action: _proposeTemplate,
  );

  ToolDefinition _tool(
    String route,
    int generation, {
    required String name,
    required String title,
    required String description,
    required Map<String, Object?> schema,
    required bool readOnly,
    required ToolHandler action,
    bool recheckAfter = true,
  }) => ToolDefinition(
    name: name,
    title: title,
    description: description,
    inputSchema: schema,
    readOnlyHint: readOnly,
    handler: (arguments) async {
      await Future<void>.delayed(Duration.zero);
      if (currentGeneration() != generation || currentRoute() != route) {
        return const {'status': 'unavailable', 'code': 'stale_route'};
      }
      final result = await action(arguments);
      if (recheckAfter &&
          (currentGeneration() != generation || currentRoute() != route)) {
        return const {'status': 'unavailable', 'code': 'stale_route'};
      }
      return result;
    },
  );

  Future<Map<String, Object?>> _openSurface(
    Map<String, Object?> arguments,
  ) async {
    if (!InputValidation.exactKeys(
          arguments,
          allowed: const {'surface'},
          required: const {'surface'},
        ) ||
        arguments['surface'] is! String) {
      return _invalid;
    }
    const routes = {
      'train': '/',
      'recovery': '/health',
      'nutrition': '/nutrition',
      'coach': '/proposals',
      'templates': '/templates',
    };
    final route = routes[arguments['surface']];
    if (route == null) return _invalid;
    navigate(route);
    return {'status': 'opened', 'route': route};
  }

  Future<Map<String, Object?>> _openProposal(
    Map<String, Object?> arguments,
  ) async {
    if (!InputValidation.exactKeys(
          arguments,
          allowed: const {'proposalId'},
          required: const {'proposalId'},
        ) ||
        arguments['proposalId'] is! String) {
      return _invalid;
    }
    final id = arguments['proposalId']! as String;
    final proposal = state.proposalById(id);
    if (id.length > 128 ||
        proposal == null ||
        proposal.status != ProposalStatus.pending) {
      return const {'status': 'unavailable', 'code': 'proposal_not_found'};
    }
    final route = '/proposals/${Uri.encodeComponent(id)}';
    navigate(route);
    return {'status': 'opened', 'proposalId': id, 'route': route};
  }

  Future<Map<String, Object?>> _workoutHistory(
    Map<String, Object?> arguments,
  ) async {
    if (!InputValidation.exactKeys(
      arguments,
      allowed: const {'limit', 'cursor'},
    )) {
      return _invalid;
    }
    final limit = arguments.containsKey('limit')
        ? InputValidation.integer(arguments['limit'], 1, 20)
        : 10;
    if (limit == null) return _invalid;
    var offset = 0;
    if (arguments.containsKey('cursor')) {
      final cursor = InputValidation.text(arguments['cursor'], 1, 128);
      if (cursor == null || !cursor.startsWith('demo:')) return _invalid;
      offset = int.tryParse(cursor.substring(5)) ?? -1;
      if (offset < 0) return _invalid;
    }
    final rows = List.generate(24, (index) {
      final start = state.anchor.subtract(Duration(days: index * 2, hours: 2));
      return {
        'id': 'workout-${24 - index}',
        'name': index.isEven ? 'Upper strength' : 'Lower strength',
        'startAt': start.toUtc().toIso8601String(),
        'endAt': start
            .add(const Duration(minutes: 62))
            .toUtc()
            .toIso8601String(),
        'durationSeconds': 3720,
        'status': 'completed',
      };
    });
    final page = rows.skip(offset).take(limit).toList(growable: false);
    final next = offset + page.length;
    return {
      'status': 'ready',
      'workoutCount': page.length,
      'hasMore': next < rows.length,
      'nextCursor': next < rows.length ? 'demo:$next' : null,
      'workouts': page,
    };
  }

  Future<Map<String, Object?>> _exerciseHistory(
    Map<String, Object?> arguments,
  ) async {
    if (!InputValidation.exactKeys(
      arguments,
      allowed: const {'limit', 'sinceDays'},
    )) {
      return _invalid;
    }
    final limit = arguments.containsKey('limit')
        ? InputValidation.integer(arguments['limit'], 1, 20)
        : 10;
    final sinceDays = arguments.containsKey('sinceDays')
        ? InputValidation.integer(arguments['sinceDays'], 1, 3650)
        : 365;
    if (limit == null || sinceDays == null) return _invalid;
    final items = state.exercises
        .take(limit)
        .map(
          (exercise) => {
            'name': exercise.name,
            'slug': exercise.slug,
            'kind': exercise.loggingMode == 'distance_duration'
                ? 'cardio'
                : 'strength',
            'loggingMode': exercise.loggingMode,
            'source': 'catalog',
            'primaryMuscles': exercise.muscles,
            'frequency': 12,
            'lastUsedAt': state.anchor
                .subtract(const Duration(days: 2))
                .toUtc()
                .toIso8601String(),
            'typicalSets': exercise.loggingMode == 'distance_duration' ? 1 : 4,
            if (exercise.loggingMode == 'distance_duration') ...{
              'typicalDistance': 5.0,
              'typicalDurationSeconds': 1800,
            } else ...{
              'typicalReps': 8,
              'typicalWeight': exercise.slug == 'weighted-pull-up'
                  ? 10.0
                  : 72.5,
            },
          },
        )
        .toList(growable: false);
    return {
      'status': 'ready',
      'range': {'sinceDays': sinceDays},
      'exerciseCount': items.length,
      'exercises': items,
    };
  }

  Future<Map<String, Object?>> _coachingTrends(
    Map<String, Object?> arguments,
  ) async {
    if (!InputValidation.exactKeys(arguments, allowed: const {'windowDays'})) {
      return _invalid;
    }
    final window = arguments.containsKey('windowDays')
        ? arguments['windowDays']
        : 30;
    if (window is! int || !const {7, 30, 90}.contains(window)) return _invalid;
    return coachingTrends(window, state);
  }

  Future<Map<String, Object?>> _foodLogEntries(
    Map<String, Object?> arguments,
  ) async {
    if (!InputValidation.exactKeys(
          arguments,
          allowed: const {'date'},
          required: const {'date'},
        ) ||
        arguments['date'] is! String ||
        !InputValidation.realDate(arguments['date']! as String)) {
      return _invalid;
    }
    final date = arguments['date']! as String;
    final matching = state.foodEntries
        .where((entry) => entry.date == date)
        .take(51)
        .toList(growable: false);
    final bounded = matching.take(50).toList(growable: false);
    return {
      'status': 'ready',
      'date': date,
      'entryCount': bounded.length,
      'truncated': matching.length > bounded.length,
      'entries': bounded.map((entry) => entry.toJson()).toList(growable: false),
    };
  }

  Future<Map<String, Object?>> _proposeNutrition(
    Map<String, Object?> arguments,
  ) async {
    const keys = {
      'caloriesTarget',
      'proteinTarget',
      'carbsTarget',
      'fatTarget',
      'rationale',
    };
    if (!InputValidation.exactKeys(
      arguments,
      allowed: keys,
      required: const {
        'caloriesTarget',
        'proteinTarget',
        'carbsTarget',
        'fatTarget',
      },
    )) {
      return _invalid;
    }
    final calories = InputValidation.integer(
      arguments['caloriesTarget'],
      800,
      6000,
    );
    final protein = InputValidation.number(arguments['proteinTarget'], 0, 500);
    final carbs = InputValidation.number(arguments['carbsTarget'], 0, 1500);
    final fat = InputValidation.number(arguments['fatTarget'], 0, 400);
    final rationale = arguments['rationale'] == null
        ? null
        : InputValidation.text(arguments['rationale'], 1, 500);
    if (calories == null ||
        protein == null ||
        carbs == null ||
        fat == null ||
        (arguments.containsKey('rationale') && rationale == null)) {
      return _invalid;
    }
    return _pendingResult(
      ProposalKind.nutritionTargets,
      'Nutrition target update',
      {
        'caloriesTarget': calories,
        'proteinTarget': protein,
        'carbsTarget': carbs,
        'fatTarget': fat,
        if (rationale != null) 'rationale': rationale,
      },
    );
  }

  Future<Map<String, Object?>> _proposeFood(
    Map<String, Object?> arguments,
  ) async {
    if (!InputValidation.exactKeys(
          arguments,
          allowed: const {'payload'},
          required: const {'payload'},
        ) ||
        arguments['payload'] is! Map) {
      return _invalid;
    }
    final payload = Map<String, Object?>.from(arguments['payload']! as Map);
    if (!InputValidation.exactKeys(
          payload,
          allowed: const {'date', 'items', 'note'},
          required: const {'date', 'items'},
        ) ||
        payload['date'] is! String ||
        !InputValidation.realDate(payload['date']! as String) ||
        payload['items'] is! List) {
      return _invalid;
    }
    final rawItems = payload['items']! as List<Object?>;
    if (rawItems.isEmpty || rawItems.length > 20) return _invalid;
    final items = <Map<String, Object?>>[];
    for (final raw in rawItems) {
      if (raw is! Map) return _invalid;
      final item = Map<String, Object?>.from(raw);
      const allowed = {
        'foodName',
        'servingGrams',
        'calories',
        'proteinGrams',
        'carbsGrams',
        'fatGrams',
        'fiberGrams',
        'sugarGrams',
        'sodiumMg',
      };
      if (!InputValidation.exactKeys(
        item,
        allowed: allowed,
        required: const {
          'foodName',
          'servingGrams',
          'calories',
          'proteinGrams',
          'carbsGrams',
          'fatGrams',
        },
      )) {
        return _invalid;
      }
      final foodName = InputValidation.text(item['foodName'], 1, 200);
      final servingGrams = InputValidation.number(
        item['servingGrams'],
        0,
        5000,
      );
      final calories = InputValidation.number(item['calories'], 0, 5000);
      final proteinGrams = InputValidation.number(
        item['proteinGrams'],
        0,
        1000,
      );
      final carbsGrams = InputValidation.number(item['carbsGrams'], 0, 1000);
      final fatGrams = InputValidation.number(item['fatGrams'], 0, 1000);
      if (foodName == null ||
          servingGrams == null ||
          servingGrams <= 0 ||
          calories == null ||
          proteinGrams == null ||
          carbsGrams == null ||
          fatGrams == null) {
        return _invalid;
      }
      final normalized = <String, Object?>{
        'foodName': foodName,
        'servingGrams': servingGrams,
        'calories': calories,
        'proteinGrams': proteinGrams,
        'carbsGrams': carbsGrams,
        'fatGrams': fatGrams,
      };
      for (final key in const ['fiberGrams', 'sugarGrams']) {
        if (item.containsKey(key)) {
          final value = InputValidation.number(item[key], 0, 1000);
          if (value == null) return _invalid;
          normalized[key] = value;
        }
      }
      if (item.containsKey('sodiumMg')) {
        final sodium = InputValidation.number(item['sodiumMg'], 0, 100000);
        if (sodium == null) return _invalid;
        normalized['sodiumMg'] = sodium;
      }
      items.add(normalized);
    }
    final note = payload.containsKey('note')
        ? InputValidation.text(payload['note'], 1, 500)
        : null;
    if (payload.containsKey('note') && note == null) return _invalid;
    return _pendingResult(ProposalKind.foodLog, 'Food log', {
      'date': payload['date'],
      'items': items,
      if (note != null) 'note': note,
    });
  }

  Future<Map<String, Object?>> _proposeFoodEdit(
    Map<String, Object?> arguments,
  ) async {
    final payload = _revisionPayload(arguments);
    if (payload == null || payload['changes'] is! Map) return _invalid;
    final targetId = payload['targetEntryId']! as String;
    final changes = Map<String, Object?>.from(payload['changes']! as Map);
    const allowed = {
      'foodName',
      'servingGrams',
      'calories',
      'proteinGrams',
      'carbsGrams',
      'fatGrams',
      'fiberGrams',
      'sugarGrams',
      'sodiumMg',
    };
    if (changes.isEmpty ||
        !InputValidation.exactKeys(changes, allowed: allowed)) {
      return _invalid;
    }
    final normalizedChanges = <String, Object?>{};
    if (changes.containsKey('foodName')) {
      final foodName = InputValidation.text(changes['foodName'], 1, 200);
      if (foodName == null) return _invalid;
      normalizedChanges['foodName'] = foodName;
    }
    for (final entry in const {
      'calories': (0.0, 5000.0),
      'proteinGrams': (0.0, 1000.0),
      'carbsGrams': (0.0, 1000.0),
      'fatGrams': (0.0, 1000.0),
      'fiberGrams': (0.0, 1000.0),
      'sugarGrams': (0.0, 1000.0),
      'sodiumMg': (0.0, 100000.0),
    }.entries) {
      if (changes.containsKey(entry.key)) {
        final value = InputValidation.number(
          changes[entry.key],
          entry.value.$1,
          entry.value.$2,
        );
        if (value == null) return _invalid;
        normalizedChanges[entry.key] = value;
      }
    }
    if (changes.containsKey('servingGrams')) {
      final servingGrams = InputValidation.number(
        changes['servingGrams'],
        0,
        5000,
      );
      if (servingGrams == null || servingGrams <= 0) return _invalid;
      normalizedChanges['servingGrams'] = servingGrams;
    }
    final proposalPayload = <String, Object?>{
      'targetEntryId': targetId,
      'changes': normalizedChanges,
    };
    final replay = _replayResult(ProposalKind.foodLogEdit, proposalPayload);
    if (replay != null) return replay;
    if (!state.foodEntries.any((entry) => entry.id == targetId)) {
      return const {'status': 'unavailable', 'code': 'food_entry_not_found'};
    }
    return _pendingResult(
      ProposalKind.foodLogEdit,
      'Correct food log entry',
      proposalPayload,
    );
  }

  Future<Map<String, Object?>> _proposeFoodDelete(
    Map<String, Object?> arguments,
  ) async {
    final payload = _revisionPayload(arguments);
    if (payload == null || payload.length != 1) return _invalid;
    final targetId = payload['targetEntryId']! as String;
    final proposalPayload = <String, Object?>{'targetEntryId': targetId};
    final replay = _replayResult(ProposalKind.foodLogDelete, proposalPayload);
    if (replay != null) return replay;
    if (!state.foodEntries.any((entry) => entry.id == targetId)) {
      return const {'status': 'unavailable', 'code': 'food_entry_not_found'};
    }
    return _pendingResult(
      ProposalKind.foodLogDelete,
      'Remove food log entry',
      proposalPayload,
    );
  }

  Map<String, Object?>? _revisionPayload(Map<String, Object?> arguments) {
    if (!InputValidation.exactKeys(
          arguments,
          allowed: const {'payload'},
          required: const {'payload'},
        ) ||
        arguments['payload'] is! Map) {
      return null;
    }
    final payload = Map<String, Object?>.from(arguments['payload']! as Map);
    if (!InputValidation.exactKeys(
          payload,
          allowed: const {'targetEntryId', 'changes'},
          required: const {'targetEntryId'},
        ) ||
        payload['targetEntryId'] is! String ||
        !_uuidPattern.hasMatch(payload['targetEntryId']! as String)) {
      return null;
    }
    return payload;
  }

  Future<Map<String, Object?>> _proposeTemplate(
    Map<String, Object?> arguments,
  ) async {
    final plan = _templatePlan(arguments);
    if (plan == null) return _invalid;
    return _pendingResult(
      ProposalKind.templateCreate,
      plan['name']! as String,
      {'plan': plan},
    );
  }

  Future<Map<String, Object?>> _proposeTemplateEdit(
    String templateId,
    Map<String, Object?> arguments,
  ) async {
    if (!InputValidation.exactKeys(
      arguments,
      allowed: const {'plan', 'baseUpdatedAt'},
      required: const {'plan', 'baseUpdatedAt'},
    )) {
      return _invalid;
    }
    final base = InputValidation.text(arguments['baseUpdatedAt'], 20, 40);
    if (base == null || arguments['baseUpdatedAt'] != base) return _invalid;
    final plan = _templatePlan({'plan': arguments['plan']});
    if (plan == null) return _invalid;
    final proposalPayload = <String, Object?>{
      'targetTemplateId': templateId,
      'requestedBaseUpdatedAt': base,
      'plan': plan,
    };
    final replay = _replayResult(ProposalKind.templateEdit, proposalPayload);
    if (replay != null) return replay;
    final template = state.templateById(templateId);
    if (template == null ||
        base != template.updatedAt.toUtc().toIso8601String()) {
      return const {'status': 'conflict', 'code': 'template_changed'};
    }
    return _pendingResult(
      ProposalKind.templateEdit,
      'Edit ${template.name}',
      proposalPayload,
    );
  }

  Map<String, Object?>? _templatePlan(Map<String, Object?> arguments) {
    if (!InputValidation.exactKeys(
          arguments,
          allowed: const {'plan'},
          required: const {'plan'},
        ) ||
        arguments['plan'] is! Map) {
      return null;
    }
    final plan = Map<String, Object?>.from(arguments['plan']! as Map);
    if (!InputValidation.exactKeys(
          plan,
          allowed: const {'name', 'description', 'exercises'},
          required: const {'name', 'exercises'},
        ) ||
        plan['exercises'] is! List) {
      return null;
    }
    final name = InputValidation.text(plan['name'], 1, 120);
    if (name == null) return null;
    final description = plan.containsKey('description')
        ? InputValidation.text(plan['description'], 1, 2000)
        : null;
    if (plan.containsKey('description') && description == null) return null;
    final rawExercises = plan['exercises']! as List<Object?>;
    if (rawExercises.isEmpty || rawExercises.length > 30) return null;
    final exercises = <Map<String, Object?>>[];
    for (final raw in rawExercises) {
      if (raw is! Map) return null;
      final exercise = Map<String, Object?>.from(raw);
      const allowed = {
        'exerciseId',
        'slug',
        'sets',
        'repsTarget',
        'restTimerSeconds',
        'weightTarget',
        'rpeTarget',
        'notes',
      };
      if (!InputValidation.exactKeys(
        exercise,
        allowed: allowed,
        required: const {'exerciseId', 'sets', 'restTimerSeconds'},
      )) {
        return null;
      }
      final id = InputValidation.text(exercise['exerciseId'], 1, 120);
      final fixture = id == null
          ? null
          : state.exercises
                .where((candidate) => candidate.id == id)
                .firstOrNull;
      if (fixture == null) return null;
      final slug = exercise.containsKey('slug')
          ? InputValidation.text(exercise['slug'], 1, 120)
          : null;
      if (exercise.containsKey('slug') &&
          (slug == null || exercise['slug'] != slug || slug != fixture.slug)) {
        return null;
      }
      final sets = InputValidation.integer(exercise['sets'], 1, 20);
      final restTimerSeconds = InputValidation.integer(
        exercise['restTimerSeconds'],
        0,
        600,
      );
      final repsTarget = exercise.containsKey('repsTarget')
          ? InputValidation.integer(exercise['repsTarget'], 1, 100)
          : null;
      final weightTarget = exercise.containsKey('weightTarget')
          ? InputValidation.number(exercise['weightTarget'], 0, 2000)
          : null;
      final rpeTarget = exercise.containsKey('rpeTarget')
          ? InputValidation.integer(exercise['rpeTarget'], 1, 10)
          : null;
      final notes = exercise.containsKey('notes')
          ? InputValidation.text(exercise['notes'], 1, 500)
          : null;
      if (sets == null ||
          restTimerSeconds == null ||
          (exercise.containsKey('repsTarget') && repsTarget == null) ||
          (exercise.containsKey('weightTarget') && weightTarget == null) ||
          (exercise.containsKey('rpeTarget') && rpeTarget == null) ||
          (exercise.containsKey('notes') && notes == null)) {
        return null;
      }
      exercises.add({
        'exerciseId': fixture.id,
        'slug': fixture.slug,
        'sets': sets,
        if (repsTarget != null) 'repsTarget': repsTarget,
        'restTimerSeconds': restTimerSeconds,
        if (weightTarget != null) 'weightTarget': weightTarget,
        if (rpeTarget != null) 'rpeTarget': rpeTarget,
        if (notes != null) 'notes': notes,
      });
    }
    return {
      'name': name,
      if (description != null) 'description': description,
      'exercises': exercises,
    };
  }

  Map<String, Object?> _pendingResult(
    ProposalKind kind,
    String title,
    Map<String, Object?> payload,
  ) {
    final before = state.proposals.length;
    try {
      final proposal = state.propose(kind, title, payload);
      return _proposalResult(
        proposal,
        created: state.proposals.length > before,
      );
    } on StateError {
      return const {'status': 'unavailable', 'code': 'pending_cap_exceeded'};
    }
  }

  Map<String, Object?>? _replayResult(
    ProposalKind kind,
    Map<String, Object?> payload,
  ) {
    final proposal = state.matchingProposal(kind, payload);
    return proposal == null ? null : _proposalResult(proposal, created: false);
  }

  Map<String, Object?> _proposalResult(
    CoachProposal proposal, {
    required bool created,
  }) {
    final status = switch (proposal.status) {
      ProposalStatus.pending => created ? 'pending' : 'duplicate',
      ProposalStatus.applied => 'applied',
      ProposalStatus.rejected => 'rejected',
      ProposalStatus.conflicted => 'conflicted',
    };
    final requiresHumanReview = proposal.status == ProposalStatus.pending;
    final message = switch (proposal.status) {
      ProposalStatus.pending =>
        'Nothing changed yet. Review this proposal in Hustl.',
      ProposalStatus.applied =>
        'This exact proposal was already applied. Nothing changed on replay.',
      ProposalStatus.rejected =>
        'This exact proposal was already dismissed. Nothing changed on replay.',
      ProposalStatus.conflicted =>
        'This exact proposal already conflicted. Nothing changed on replay.',
    };
    return {
      'status': status,
      'proposalId': proposal.id,
      'requiresHumanReview': requiresHumanReview,
      'message': message,
    };
  }

  bool _isCoachRoute(String route) {
    if (route == '/proposals') return true;
    final id = _detailId(route, '/proposals/');
    return id != null && state.proposalById(id) != null;
  }

  static String? _detailId(String route, String prefix) {
    if (!route.startsWith(prefix)) return null;
    final encoded = route.substring(prefix.length);
    if (encoded.isEmpty || encoded.contains('/') || encoded.length > 384) {
      return null;
    }
    try {
      final decoded = Uri.decodeComponent(encoded);
      return decoded.isEmpty || decoded.length > 128 ? null : decoded;
    } on FormatException {
      return null;
    }
  }

  static const _invalid = {
    'status': 'invalid_request',
    'code': 'invalid_arguments',
  };

  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
}
