import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_evaluator/src/model/evaluator_state.dart';
import 'package:hustl_evaluator/src/model/models.dart';
import 'package:hustl_evaluator/src/webmcp/tool_catalog.dart';
import 'package:hustl_evaluator/src/webmcp/tool.dart';
import 'package:hustl_evaluator/src/webmcp/web_mcp_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EvaluatorState state;
  late String route;
  late int generation;
  late ToolCatalog catalog;

  setUp(() async {
    state = EvaluatorState(anchor: DateTime(2026, 8, 31));
    await state.loadFixtures();
    route = '/';
    generation = 1;
    catalog = ToolCatalog(
      state: state,
      currentRoute: () => route,
      currentGeneration: () => generation,
      navigate: (next) => route = next,
    );
  });

  test('publishes exact route-owned catalogs with truthful annotations', () {
    expect(_names(catalog.forRoute('/', generation)), [
      'hustl_get_today_context',
      'hustl_open_surface',
      'hustl_get_training_context',
      'hustl_get_workout_history',
      'hustl_get_exercise_history',
    ]);
    expect(_names(catalog.forRoute('/health', generation)), [
      'hustl_get_today_context',
      'hustl_open_surface',
      'hustl_get_recovery_context',
    ]);
    expect(_names(catalog.forRoute('/nutrition', generation)), [
      'hustl_get_today_context',
      'hustl_open_surface',
      'hustl_get_nutrition_context',
      'hustl_get_food_log_entries',
      'hustl_propose_nutrition_targets',
      'hustl_propose_food_log',
      'hustl_propose_food_log_edit',
      'hustl_propose_food_log_delete',
    ]);
    expect(_names(catalog.forRoute('/templates', generation)), [
      'hustl_get_today_context',
      'hustl_open_surface',
      'hustl_propose_template',
    ]);

    final train = catalog.forRoute('/', generation);
    for (final tool in train) {
      expect(tool.untrustedContentHint, isTrue);
      expect(tool.destructiveHint, isFalse);
      expect(tool.idempotentHint, isTrue);
      expect(tool.openWorldHint, isFalse);
      expect(
        tool.registrationJson()['annotations'],
        containsPair('untrustedContentHint', true),
      );
      expect(
        (tool.registrationJson()['annotations']! as Map<String, Object?>).keys,
        containsAll(<String>[
          'readOnlyHint',
          'destructiveHint',
          'idempotentHint',
          'openWorldHint',
          'untrustedContentHint',
        ]),
      );
    }
    expect(
      train
          .firstWhere((tool) => tool.name == 'hustl_open_surface')
          .readOnlyHint,
      isTrue,
    );
    expect(
      train
          .firstWhere((tool) => tool.name == 'hustl_get_training_context')
          .readOnlyHint,
      isTrue,
    );
    expect(
      catalog
          .forRoute('/nutrition', generation)
          .firstWhere((tool) => tool.name == 'hustl_propose_food_log')
          .readOnlyHint,
      isFalse,
    );
  });

  test(
    'proposal tools stay pending and preserve live state until Apply',
    () async {
      route = '/nutrition';
      final tools = catalog.forRoute(route, generation);
      final proposalTool = tools.firstWhere(
        (tool) => tool.name == 'hustl_propose_nutrition_targets',
      );
      final original = state.nutritionTargets;

      final result = await proposalTool.handler({
        'caloriesTarget': 2100,
        'proteinTarget': 180,
        'carbsTarget': 205,
        'fatTarget': 65,
        'rationale': 'Preserve strength during the 12-week cut.',
      });

      expect(result['status'], 'pending');
      expect(result['requiresHumanReview'], isTrue);
      expect(state.pending, hasLength(1));
      expect(state.nutritionTargets, same(original));

      final duplicate = await proposalTool.handler({
        'caloriesTarget': 2100,
        'proteinTarget': 180,
        'carbsTarget': 205,
        'fatTarget': 65,
        'rationale': 'Preserve strength during the 12-week cut.',
      });
      expect(duplicate['status'], 'duplicate');
      expect(duplicate['proposalId'], result['proposalId']);

      state.apply(result['proposalId']! as String);
      expect(state.nutritionTargets.calories, 2100);
      expect(state.pending, isEmpty);
      expect(state.recent.single.status, ProposalStatus.applied);

      final appliedReplay = await proposalTool.handler({
        'fatTarget': 65,
        'carbsTarget': 205,
        'proteinTarget': 180,
        'caloriesTarget': 2100,
        'rationale': 'Preserve strength during the 12-week cut.',
      });
      expect(appliedReplay['status'], 'applied');
      expect(appliedReplay['proposalId'], result['proposalId']);
      expect(appliedReplay['requiresHumanReview'], isFalse);
      expect(state.proposals, hasLength(1));

      final dismissed = await proposalTool.handler({
        'caloriesTarget': 2200,
        'proteinTarget': 175,
        'carbsTarget': 225,
        'fatTarget': 70,
      });
      state.dismiss(dismissed['proposalId']! as String);
      final dismissedReplay = await proposalTool.handler({
        'fatTarget': 70,
        'carbsTarget': 225,
        'proteinTarget': 175,
        'caloriesTarget': 2200,
      });
      expect(dismissedReplay['status'], 'rejected');
      expect(dismissedReplay['proposalId'], dismissed['proposalId']);
      expect(dismissedReplay['requiresHumanReview'], isFalse);
      expect(state.proposals, hasLength(2));
    },
  );

  test('retained tool fails stale before persistence', () async {
    route = '/templates';
    final tool = catalog
        .forRoute(route, generation)
        .firstWhere((item) => item.name == 'hustl_propose_template');
    route = '/health';
    generation += 1;

    final result = await tool.handler({
      'plan': {
        'name': 'Upper A',
        'exercises': [
          {
            'exerciseId': 'barbell-bench-press',
            'slug': 'barbell-bench-press',
            'sets': 4,
            'repsTarget': 6,
            'rpeTarget': 8,
            'restTimerSeconds': 180,
          },
        ],
      },
    });

    expect(result, {'status': 'unavailable', 'code': 'stale_route'});
    expect(state.proposals, isEmpty);
    expect(state.templates, hasLength(1));
  });

  test('Coach detail keeps review tools but exposes no decision tool', () {
    final proposal = state.propose(ProposalKind.foodLog, 'Lunch', const {
      'date': '2026-08-31',
      'items': <Map<String, Object?>>[],
    });
    final listNames = _names(catalog.forRoute('/proposals', generation));
    final detailNames = _names(
      catalog.forRoute('/proposals/${proposal.id}', generation),
    );
    expect(detailNames, listNames);
    expect(
      detailNames.where(
        (name) => RegExp(r'apply|approve|dismiss|reject|reset').hasMatch(name),
      ),
      isEmpty,
    );
    expect(_names(catalog.forRoute('/proposals/missing', generation)), [
      'hustl_get_today_context',
      'hustl_open_surface',
    ]);
    expect(
      _names(
        catalog.forRoute(
          '/proposals/${Uri.encodeComponent(' ${proposal.id} ')}',
          generation,
        ),
      ),
      ['hustl_get_today_context', 'hustl_open_surface'],
    );
    expect(
      _names(
        catalog.forRoute(
          '/templates/${Uri.encodeComponent(' ${state.templates.first.id} ')}',
          generation,
        ),
      ),
      ['hustl_get_today_context', 'hustl_open_surface'],
    );
  });

  test(
    'food proposal validates explicit real date and bounded items',
    () async {
      route = '/nutrition';
      final tool = catalog
          .forRoute(route, generation)
          .firstWhere((item) => item.name == 'hustl_propose_food_log');
      final invalid = await tool.handler({
        'payload': {'date': '2026-02-31', 'items': const <Object?>[]},
      });
      expect(invalid['status'], 'invalid_request');
      expect(state.proposals, isEmpty);

      final valid = await tool.handler({
        'payload': {
          'date': '2026-08-31',
          'items': [
            {
              'foodName': 'Apple',
              'servingGrams': 100,
              'calories': 52,
              'proteinGrams': 0.3,
              'carbsGrams': 14,
              'fatGrams': 0.2,
              'fiberGrams': 2.4,
            },
          ],
        },
      });
      expect(valid['status'], 'pending');
      expect(valid['requiresHumanReview'], isTrue);
    },
  );

  test('stores normalized bounded food and template strings', () async {
    route = '/nutrition';
    final foodTool = catalog
        .forRoute(route, generation)
        .firstWhere((item) => item.name == 'hustl_propose_food_log');
    final overlongFood = await foodTool.handler({
      'payload': {
        'date': '2026-08-31',
        'items': [
          {
            'foodName': '${_repeat(' ', 200)}A',
            'servingGrams': 100,
            'calories': 52,
            'proteinGrams': 0.3,
            'carbsGrams': 14,
            'fatGrams': 0.2,
          },
        ],
      },
    });
    expect(overlongFood['status'], 'invalid_request');
    final overlongNote = await foodTool.handler({
      'payload': {
        'date': '2026-08-31',
        'items': [
          {
            'foodName': 'Apple',
            'servingGrams': 100,
            'calories': 52,
            'proteinGrams': 0.3,
            'carbsGrams': 14,
            'fatGrams': 0.2,
          },
        ],
        'note': ' ${_repeat('n', 500)} ',
      },
    });
    expect(overlongNote['status'], 'invalid_request');
    final nullOptional = await foodTool.handler({
      'payload': {
        'date': '2026-08-31',
        'items': [
          {
            'foodName': 'Apple',
            'servingGrams': 100,
            'calories': 52,
            'proteinGrams': 0.3,
            'carbsGrams': 14,
            'fatGrams': 0.2,
            'fiberGrams': null,
          },
        ],
      },
    });
    expect(nullOptional['status'], 'invalid_request');
    expect(state.proposals, isEmpty);

    final food = await foodTool.handler({
      'payload': {
        'date': '2026-08-31',
        'items': [
          {
            'fatGrams': 0.2,
            'foodName': '  Apple  ',
            'carbsGrams': 14,
            'proteinGrams': 0.3,
            'calories': 52,
            'servingGrams': 100,
            'fiberGrams': 2,
          },
        ],
        'note': '  Afternoon snack  ',
      },
    });
    expect(food['status'], 'pending');
    final foodPayload = state
        .proposalById(food['proposalId']! as String)!
        .payload;
    final normalizedFood =
        (foodPayload['items']! as List<Object?>).single as Map<String, Object?>;
    expect(normalizedFood['foodName'], 'Apple');
    expect(normalizedFood['servingGrams'], isA<double>());
    expect(normalizedFood['fiberGrams'], isA<double>());
    expect(foodPayload['note'], 'Afternoon snack');

    final duplicateFood = await foodTool.handler({
      'payload': {
        'items': [
          {
            'servingGrams': 100,
            'calories': 52,
            'proteinGrams': 0.3,
            'carbsGrams': 14,
            'foodName': '  Apple  ',
            'fatGrams': 0.2,
            'fiberGrams': 2,
          },
        ],
        'note': '  Afternoon snack  ',
        'date': '2026-08-31',
      },
    });
    expect(duplicateFood['status'], 'duplicate');
    expect(duplicateFood['proposalId'], food['proposalId']);

    route = '/templates';
    generation += 1;
    final templateTool = catalog
        .forRoute(route, generation)
        .firstWhere((item) => item.name == 'hustl_propose_template');
    final overlongNested = await templateTool.handler({
      'plan': {
        'name': 'Upper A',
        'exercises': [
          {
            'exerciseId': 'barbell-bench-press',
            'sets': 4,
            'restTimerSeconds': 180,
            'notes': ' ${_repeat('n', 500)} ',
          },
        ],
      },
    });
    expect(overlongNested['status'], 'invalid_request');
    final noncanonicalSlug = await templateTool.handler({
      'plan': {
        'name': 'Upper A',
        'exercises': [
          {
            'exerciseId': 'barbell-bench-press',
            'slug': ' barbell-bench-press ',
            'sets': 4,
            'restTimerSeconds': 180,
          },
        ],
      },
    });
    expect(noncanonicalSlug['status'], 'invalid_request');
    final mismatchedSlug = await templateTool.handler({
      'plan': {
        'name': 'Upper A',
        'exercises': [
          {
            'exerciseId': 'barbell-bench-press',
            'slug': 'barbell-back-squat',
            'sets': 4,
            'restTimerSeconds': 180,
          },
        ],
      },
    });
    expect(mismatchedSlug['status'], 'invalid_request');

    final template = await templateTool.handler({
      'plan': {
        'name': '  Upper A  ',
        'description': '  Controlled strength session  ',
        'exercises': [
          {
            'exerciseId': '  barbell-bench-press  ',
            'slug': 'barbell-bench-press',
            'sets': 4,
            'repsTarget': 6,
            'weightTarget': 80,
            'rpeTarget': 8,
            'restTimerSeconds': 180,
            'notes': '  Pause on the chest  ',
          },
        ],
      },
    });
    expect(template['status'], 'pending');
    final templatePayload = state
        .proposalById(template['proposalId']! as String)!
        .payload;
    final plan = templatePayload['plan']! as Map<String, Object?>;
    final exercise =
        (plan['exercises']! as List<Object?>).single as Map<String, Object?>;
    expect(plan['name'], 'Upper A');
    expect(plan['description'], 'Controlled strength session');
    expect(exercise['exerciseId'], 'barbell-bench-press');
    expect(exercise['slug'], 'barbell-bench-press');
    expect(exercise['notes'], 'Pause on the chest');
    expect(exercise['weightTarget'], isA<double>());

    final omittedSlug = await templateTool.handler({
      'plan': {
        'name': 'Upper A',
        'description': 'Controlled strength session',
        'exercises': [
          {
            'exerciseId': 'barbell-bench-press',
            'sets': 4,
            'repsTarget': 6,
            'weightTarget': 80,
            'rpeTarget': 8,
            'restTimerSeconds': 180,
            'notes': 'Pause on the chest',
          },
        ],
      },
    });
    expect(omittedSlug['status'], 'duplicate');
    expect(omittedSlug['proposalId'], template['proposalId']);
    expect(state.proposals, hasLength(2));
  });

  test(
    'normalizes signed zero and accepts every positive serving size',
    () async {
      route = '/nutrition';
      final tools = catalog.forRoute(route, generation);
      final nutrition = tools.firstWhere(
        (item) => item.name == 'hustl_propose_nutrition_targets',
      );
      final food = tools.firstWhere(
        (item) => item.name == 'hustl_propose_food_log',
      );
      final edit = tools.firstWhere(
        (item) => item.name == 'hustl_propose_food_log_edit',
      );

      final signedZero = await nutrition.handler({
        'caloriesTarget': 2100,
        'proteinTarget': -0.0,
        'carbsTarget': -0,
        'fatTarget': 0.0,
      });
      final positiveZero = await nutrition.handler({
        'fatTarget': 0,
        'carbsTarget': 0.0,
        'proteinTarget': 0,
        'caloriesTarget': 2100,
      });
      expect(positiveZero['status'], 'duplicate');
      expect(positiveZero['proposalId'], signedZero['proposalId']);
      final nutritionPayload = state
          .proposalById(signedZero['proposalId']! as String)!
          .payload;
      for (final key in const ['proteinTarget', 'carbsTarget', 'fatTarget']) {
        final value = nutritionPayload[key]! as double;
        expect(value, 0.0);
        expect(value.isNegative, isFalse);
      }

      const tinyPositive = 5e-324;
      final tinyFood = await food.handler({
        'payload': {
          'date': '2026-08-31',
          'items': [
            {
              'foodName': 'Trace spice',
              'servingGrams': tinyPositive,
              'calories': -0.0,
              'proteinGrams': 0,
              'carbsGrams': 0.0,
              'fatGrams': -0,
            },
          ],
        },
      });
      expect(tinyFood['status'], 'pending');
      final item =
          ((state
                          .proposalById(tinyFood['proposalId']! as String)!
                          .payload['items']!
                      as List<Object?>)
                  .single
              as Map<String, Object?>);
      expect(item['servingGrams'], tinyPositive);
      expect((item['calories']! as double).isNegative, isFalse);

      final targetId = state.foodEntries.first.id;
      final tinyEdit = await edit.handler({
        'payload': {
          'targetEntryId': targetId,
          'changes': {'servingGrams': tinyPositive},
        },
      });
      expect(tinyEdit['status'], 'pending');
      final zeroEdit = await edit.handler({
        'payload': {
          'targetEntryId': targetId,
          'changes': {'servingGrams': 0},
        },
      });
      expect(zeroEdit['status'], 'invalid_request');
      final zeroFood = await food.handler({
        'payload': {
          'date': '2026-08-31',
          'items': [
            {
              'foodName': 'Nothing',
              'servingGrams': 0,
              'calories': 0,
              'proteinGrams': 0,
              'carbsGrams': 0,
              'fatGrams': 0,
            },
          ],
        },
      });
      expect(zeroFood['status'], 'invalid_request');
    },
  );

  test('food correction stays pending until visible Apply', () async {
    route = '/nutrition';
    final tools = catalog.forRoute(route, generation);
    final read = tools.firstWhere(
      (item) => item.name == 'hustl_get_food_log_entries',
    );
    final edit = tools.firstWhere(
      (item) => item.name == 'hustl_propose_food_log_edit',
    );
    final before = await read.handler({'date': '2026-08-31'});
    final entry =
        (before['entries']! as List<Object?>).first as Map<String, Object?>;

    final proposal = await edit.handler({
      'payload': {
        'targetEntryId': entry['id'],
        'changes': {'calories': 525},
      },
    });
    expect(proposal['status'], 'pending');
    expect(state.foodEntries.first.calories, 520);

    state.apply(proposal['proposalId']! as String);
    expect(state.foodEntries.first.calories, 525);
    final after = await read.handler({'date': '2026-08-31'});
    expect(
      ((after['entries']! as List<Object?>).first
          as Map<String, Object?>)['calories'],
      525,
    );
  });

  test('conflicting food proposals cannot report a no-op as applied', () async {
    route = '/nutrition';
    final tools = catalog.forRoute(route, generation);
    final edit = tools.firstWhere(
      (item) => item.name == 'hustl_propose_food_log_edit',
    );
    final remove = tools.firstWhere(
      (item) => item.name == 'hustl_propose_food_log_delete',
    );
    final targetId = state.foodEntries.first.id;

    final editProposal = await edit.handler({
      'payload': {
        'targetEntryId': targetId,
        'changes': {'calories': 525},
      },
    });
    final deleteProposal = await remove.handler({
      'payload': {'targetEntryId': targetId},
    });

    state.apply(deleteProposal['proposalId']! as String);
    state.apply(editProposal['proposalId']! as String);

    expect(state.foodEntries.any((entry) => entry.id == targetId), isFalse);
    expect(
      state.proposalById(deleteProposal['proposalId']! as String)!.status,
      ProposalStatus.applied,
    );
    expect(
      state.proposalById(editProposal['proposalId']! as String)!.status,
      ProposalStatus.conflicted,
    );

    final conflictReplay = await edit.handler({
      'payload': {
        'changes': {'calories': 525},
        'targetEntryId': targetId,
      },
    });
    expect(conflictReplay['status'], 'conflicted');
    expect(conflictReplay['proposalId'], editProposal['proposalId']);
    expect(conflictReplay['requiresHumanReview'], isFalse);
    expect(state.proposals, hasLength(2));
  });

  test(
    'applied food deletion replay does not require the removed row',
    () async {
      route = '/nutrition';
      final remove = catalog
          .forRoute(route, generation)
          .firstWhere((item) => item.name == 'hustl_propose_food_log_delete');
      final targetId = state.foodEntries.first.id;
      final arguments = {
        'payload': {'targetEntryId': targetId},
      };

      final proposal = await remove.handler(arguments);
      state.apply(proposal['proposalId']! as String);
      expect(state.foodEntries.any((entry) => entry.id == targetId), isFalse);

      final replay = await remove.handler(arguments);
      expect(replay['status'], 'applied');
      expect(replay['proposalId'], proposal['proposalId']);
      expect(replay['requiresHumanReview'], isFalse);
      expect(state.proposals, hasLength(1));
    },
  );

  test(
    'same-scope Coach refresh atomically rebinds within host quota',
    () async {
      final proposal = state.propose(ProposalKind.foodLog, 'Snack', const {
        'date': '2026-08-31',
        'items': <Map<String, Object?>>[
          {
            'foodName': 'Apple',
            'servingGrams': 100.0,
            'calories': 52.0,
            'proteinGrams': 0.3,
            'carbsGrams': 14.0,
            'fatGrams': 0.2,
          },
        ],
      });
      route = '/proposals';
      final host = _QuotaAwareHost(successfulRegistrationLimit: 9);
      final controller = WebMcpController(
        state: state,
        host: host,
        currentRoute: () => route,
        navigate: (next) => route = next,
      );
      await controller.refresh();
      expect(host.registrationAttempts, 7);
      expect(host.remainingSuccessfulRegistrations, 2);
      expect(host.activeNames, hasLength(7));
      final retainedCoach = host.activeDefinition('hustl_get_coach_activity');

      route = '/proposals/${proposal.id}';
      expect(await retainedCoach.handler(const {}), {
        'status': 'unavailable',
        'code': 'stale_route',
      });
      await controller.refresh();
      expect(host.registrationAttempts, 7);
      expect(host.activeNames, hasLength(7));
      expect((await retainedCoach.handler(const {}))['status'], 'ready');

      state.propose(ProposalKind.foodLog, 'Second snack', const {
        'date': '2026-08-31',
        'items': <Map<String, Object?>>[
          {
            'foodName': 'Pear',
            'servingGrams': 100.0,
            'calories': 57.0,
            'proteinGrams': 0.4,
            'carbsGrams': 15.0,
            'fatGrams': 0.1,
          },
        ],
      });
      await Future<void>.delayed(Duration.zero);
      await controller.refresh();
      expect(host.registrationAttempts, 7);
      expect(host.activeNames, hasLength(7));
      expect((await retainedCoach.handler(const {}))['pendingCount'], 2);

      route = '/health';
      await controller.refresh();
      // The legacy loop observed supported=false after attempt 10 and kept the
      // two provisional successes, producing the prior seven-to-two collapse.
      expect(host.registrationAttempts, 10);
      expect(host.successfulRegistrations, 9);
      expect(host.supported, isFalse);
      expect(host.activeNames, isEmpty);
      expect(await retainedCoach.handler(const {}), {
        'status': 'unavailable',
        'code': 'stale_route',
      });
      controller.dispose();
    },
  );

  test(
    'template detail replacement cannot retarget a retained handle',
    () async {
      final templateA = state.templates.first;
      final templateB = WorkoutTemplate(
        id: 'template-strength-b',
        name: 'Strength B',
        description: 'Second template',
        exercises: const [
          {
            'exerciseId': 'barbell-back-squat',
            'slug': 'barbell-back-squat',
            'sets': 3,
            'repsTarget': 5,
            'weightTarget': 90.0,
            'rpeTarget': 7,
            'restTimerSeconds': 180,
          },
        ],
        updatedAt: DateTime.utc(2026, 8, 30, 13),
      );
      state.templates.add(templateB);
      route = '/templates/${templateA.id}';
      final host = _RecordingHost();
      final controller = WebMcpController(
        state: state,
        host: host,
        currentRoute: () => route,
        navigate: (next) => route = next,
      );
      await controller.refresh();
      final retainedA = host.activeDefinition('hustl_propose_template_edit');

      route = '/templates/${templateB.id}';
      final bArguments = _templateEditArguments(
        templateB,
        'Strength B revised',
      );
      expect(await retainedA.handler(bArguments), {
        'status': 'unavailable',
        'code': 'stale_route',
      });
      await controller.refresh();
      expect(await retainedA.handler(bArguments), {
        'status': 'unavailable',
        'code': 'stale_route',
      });
      expect(state.proposals, isEmpty);

      final currentB = host.activeDefinition('hustl_propose_template_edit');
      final proposal = await currentB.handler(bArguments);
      expect(proposal['status'], 'pending');
      final stored = state.proposalById(proposal['proposalId']! as String)!;
      expect(stored.payload['targetTemplateId'], templateB.id);
      expect(stored.payload['targetTemplateId'], isNot(templateA.id));

      state.apply(stored.id);
      await Future<void>.delayed(Duration.zero);
      await controller.refresh();
      final reboundB = host.activeDefinition('hustl_propose_template_edit');
      final appliedReplay = await reboundB.handler(bArguments);
      expect(appliedReplay['status'], 'applied');
      expect(appliedReplay['proposalId'], stored.id);
      expect(state.proposals, hasLength(1));
      controller.dispose();
    },
  );

  test('terminal proposal details retain the Coach catalog', () async {
    for (final terminalStatus in const [
      ProposalStatus.applied,
      ProposalStatus.rejected,
      ProposalStatus.conflicted,
    ]) {
      final localState = EvaluatorState(anchor: DateTime(2026, 8, 31));
      await localState.loadFixtures();
      final targetId = localState.foodEntries.first.id;
      final proposal = localState.propose(
        ProposalKind.foodLogEdit,
        'Correct lunch',
        {
          'targetEntryId': targetId,
          'changes': {'calories': 525.0},
        },
      );
      var localRoute = '/proposals/${proposal.id}';
      final host = _RecordingHost(successfulRegistrationLimit: 9);
      final controller = WebMcpController(
        state: localState,
        host: host,
        currentRoute: () => localRoute,
        navigate: (next) => localRoute = next,
      );
      await controller.refresh();
      expect(host.activeNames, hasLength(7));
      expect(host.registrationAttempts, 7);

      switch (terminalStatus) {
        case ProposalStatus.applied:
          localState.apply(proposal.id);
        case ProposalStatus.rejected:
          localState.dismiss(proposal.id);
        case ProposalStatus.conflicted:
          localState.foodEntries.removeWhere((entry) => entry.id == targetId);
          localState.apply(proposal.id);
        case ProposalStatus.pending:
          fail('The test only covers terminal states.');
      }
      await Future<void>.delayed(Duration.zero);
      await controller.refresh();

      expect(localState.proposalById(proposal.id)!.status, terminalStatus);
      expect(host.activeNames, hasLength(7));
      expect(host.registrationAttempts, 7);
      expect(host.remainingSuccessfulRegistrations, 2);

      localRoute = '/proposals';
      await controller.refresh();
      expect(host.activeNames, hasLength(7));
      expect(host.registrationAttempts, 7);
      controller.dispose();
    }
  });

  test(
    'registered mutation reports success before state refresh invalidates it',
    () async {
      route = '/nutrition';
      final host = _RecordingHost();
      final controller = WebMcpController(
        state: state,
        host: host,
        currentRoute: () => route,
        navigate: (next) => route = next,
      );
      await controller.refresh();
      final mutationGeneration = controller.generation;
      final proposalTool = host.activeDefinition('hustl_propose_food_log');

      final result = await proposalTool.handler({
        'payload': {
          'date': '2026-08-31',
          'items': [
            {
              'foodName': 'Apple',
              'servingGrams': 100,
              'calories': 52,
              'proteinGrams': 0.3,
              'carbsGrams': 14,
              'fatGrams': 0.2,
            },
          ],
        },
      });

      expect(result['status'], 'pending');
      expect(controller.generation, mutationGeneration);
      expect(state.pending, hasLength(1));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(controller.generation, greaterThan(mutationGeneration));
      controller.dispose();
    },
  );

  test(
    'registered navigation returns success while stale non-navigation fails',
    () async {
      final host = _RecordingHost();
      late WebMcpController controller;
      Future<void>? routeRefresh;
      controller = WebMcpController(
        state: state,
        host: host,
        currentRoute: () => route,
        navigate: (next) {
          route = next;
          routeRefresh = controller.refresh();
        },
      );
      await controller.refresh();
      final openSurface = host.activeDefinition('hustl_open_surface');
      final retainedTraining = host.activeDefinition(
        'hustl_get_training_context',
      );

      expect(await openSurface.handler(const {'surface': 'nutrition'}), {
        'status': 'opened',
        'route': '/nutrition',
      });
      await routeRefresh;
      expect(route, '/nutrition');
      expect(host.activeNames, hasLength(8));
      expect(await retainedTraining.handler(const {}), {
        'status': 'unavailable',
        'code': 'stale_route',
      });
      expect(await openSurface.handler(const {'surface': 'coach'}), {
        'status': 'unavailable',
        'code': 'stale_route',
      });
      final currentNutrition = host.activeDefinition(
        'hustl_get_nutrition_context',
      );
      controller.dispose();
      expect(await currentNutrition.handler(const {}), {
        'status': 'unavailable',
        'code': 'stale_route',
      });
    },
  );
}

List<String> _names(List<ToolDefinition> tools) => [
  for (final tool in tools) tool.name,
];

String _repeat(String value, int count) => List.filled(count, value).join();

Map<String, Object?> _templateEditArguments(
  WorkoutTemplate template,
  String name,
) => {
  'baseUpdatedAt': template.updatedAt.toUtc().toIso8601String(),
  'plan': {
    'name': name,
    'description': template.description,
    'exercises': template.exercises,
  },
};

class _RecordingHost implements ToolHost {
  _RecordingHost({this.successfulRegistrationLimit});

  final int? successfulRegistrationLimit;
  final List<_RecordingRegistration> _active = [];
  int registrationAttempts = 0;
  int successfulRegistrations = 0;
  bool _supported = true;

  @override
  bool get supported => _supported;

  int? get remainingSuccessfulRegistrations =>
      successfulRegistrationLimit == null
      ? null
      : successfulRegistrationLimit! - successfulRegistrations;

  List<String> get activeNames => [
    for (final registration in _active)
      if (!registration.disposed) registration.definition.name,
  ];

  ToolDefinition activeDefinition(String name) => _active
      .where(
        (registration) =>
            !registration.disposed && registration.definition.name == name,
      )
      .single
      .definition;

  @override
  Future<ToolRegistration?> register(ToolDefinition definition) async {
    registrationAttempts += 1;
    if (successfulRegistrationLimit != null &&
        successfulRegistrations >= successfulRegistrationLimit!) {
      _supported = false;
      return null;
    }
    final registration = _RecordingRegistration(definition);
    _active.add(registration);
    successfulRegistrations += 1;
    return registration;
  }
}

class _QuotaAwareHost extends _RecordingHost {
  _QuotaAwareHost({required super.successfulRegistrationLimit});
}

class _RecordingRegistration implements ToolRegistration {
  _RecordingRegistration(this.definition);

  final ToolDefinition definition;
  bool disposed = false;

  @override
  void dispose() => disposed = true;
}
