import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/webmcp/active_workout_web_mcp_controller.dart';
import 'package:hustl_app/core/webmcp/coaching_trends_web_mcp_service.dart';
import 'package:hustl_app/core/webmcp/hustl_web_mcp_coordinator.dart';
import 'package:hustl_app/core/webmcp/today_context.dart';
import 'package:hustl_app/core/webmcp/today_context_service.dart';
import 'package:hustl_app/core/webmcp/template_web_mcp_service.dart';
import 'package:hustl_app/core/webmcp/web_mcp_access_gate.dart';
import 'package:hustl_app/core/webmcp/web_mcp_models.dart';
import 'package:hustl_app/core/webmcp/workout_history_web_mcp_service.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/nutrition_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/food_log_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/food_log_revision_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_detail.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_summary.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposed_nutrition_target.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/template_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/repositories/proposals_repository.dart';
import 'package:hustl_app/features/ai_proposals/domain/repositories/food_log_revision_proposal_repository.dart';
import 'package:hustl_app/features/ai_proposals/services/proposal_count_service.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/diary_refresh_signal.dart';
import 'package:mocktail/mocktail.dart';

class _MockTodayContextService extends Mock implements TodayContextService {}

class _MockActiveWorkoutController extends Mock
    implements ActiveWorkoutWebMcpController {}

class _MockProposalsRepository extends Mock implements ProposalsRepository {}

class _MockFoodLogRevisionRepository extends Mock
    implements FoodLogRevisionProposalRepository {}

class _MockFoodLogRepository extends Mock
    implements ReadOnlyFoodLogRepository {}

class _MockProposalCountService extends Mock implements ProposalCountService {}

class _MockTemplateWebMcpService extends Mock
    implements TemplateWebMcpService {}

class _MockWorkoutHistoryWebMcpService extends Mock
    implements WorkoutHistoryWebMcpService {}

class _MockCoachingTrendsWebMcpService extends Mock
    implements CoachingTrendsWebMcpService {}

class _FakeNutritionInput extends Fake implements NutritionProposalInput {}

class _FakeFoodLogInput extends Fake implements FoodLogProposalInput {}

class _FakeFoodLogEditInput extends Fake implements FoodLogEditProposalInput {}

class _FakeFoodLogDeleteInput extends Fake
    implements FoodLogDeleteProposalInput {}

void main() {
  late _MockTodayContextService service;
  late _MockActiveWorkoutController activeWorkout;
  late _MockProposalsRepository proposals;
  late _MockFoodLogRevisionRepository foodLogRevisions;
  late _MockFoodLogRepository foodLogs;
  late _MockProposalCountService proposalCount;
  late _MockTemplateWebMcpService templateService;
  late _MockWorkoutHistoryWebMcpService workoutHistoryService;
  late _MockCoachingTrendsWebMcpService coachingTrendsService;
  late List<Map<String, Object?>> telemetry;
  late HustlWebMcpCoordinator coordinator;
  late WebMcpAccessGate gate;
  late String currentRoute;
  late DiaryRefreshSignal diaryRefreshSignal;
  late int diaryRefreshCount;

  setUpAll(() {
    registerFallbackValue(_FakeNutritionInput());
    registerFallbackValue(_FakeFoodLogInput());
    registerFallbackValue(_FakeFoodLogEditInput());
    registerFallbackValue(_FakeFoodLogDeleteInput());
    registerFallbackValue(_templatePlan);
  });

  setUp(() {
    service = _MockTodayContextService();
    activeWorkout = _MockActiveWorkoutController();
    proposals = _MockProposalsRepository();
    foodLogRevisions = _MockFoodLogRevisionRepository();
    foodLogs = _MockFoodLogRepository();
    proposalCount = _MockProposalCountService();
    templateService = _MockTemplateWebMcpService();
    workoutHistoryService = _MockWorkoutHistoryWebMcpService();
    coachingTrendsService = _MockCoachingTrendsWebMcpService();
    gate = WebMcpAccessGate()..setReady(true);
    currentRoute = '/';
    telemetry = [];
    diaryRefreshCount = 0;
    diaryRefreshSignal = DiaryRefreshSignal()
      ..addListener(() => diaryRefreshCount++);
    coordinator = HustlWebMcpCoordinator(
      todayContextService: service,
      accessGate: gate,
      activeWorkoutController: activeWorkout,
      proposalsRepository: proposals,
      foodLogRevisionRepository: foodLogRevisions,
      foodLogRepository: foodLogs,
      templateService: templateService,
      workoutHistoryService: workoutHistoryService,
      coachingTrendsService: coachingTrendsService,
      proposalCountService: proposalCount,
      diaryRefreshSignal: diaryRefreshSignal,
      telemetry: (name, properties) =>
          telemetry.add({'event': name, ...properties}),
    );
    when(() => service.load()).thenAnswer((_) async => _context());
    when(
      () => proposals.listPending(limit: any(named: 'limit')),
    ).thenAnswer((_) async => <ProposalSummary>[]);
    when(
      () => proposals.listDecided(
        statuses: any(named: 'statuses'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => <ProposalSummary>[]);
    when(
      () => foodLogs.getLogsForDateReadOnly(any()),
    ).thenAnswer((_) async => <FoodLogEntry>[]);
    when(
      () => activeWorkout.getActiveWorkout(),
    ).thenReturn(const {'status': 'unavailable', 'code': 'no_active_workout'});
    when(() => proposalCount.refreshNow()).thenAnswer((_) async {});
    when(() => templateService.load(any())).thenAnswer((_) async => null);
    when(
      () => workoutHistoryService.loadWorkoutHistory(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
      ),
    ).thenAnswer(
      (_) async => const {
        'status': 'ready',
        'workoutCount': 0,
        'hasMore': false,
        'nextCursor': null,
        'workouts': <Object?>[],
      },
    );
    when(
      () => workoutHistoryService.loadExerciseHistory(
        limit: any(named: 'limit'),
        sinceDays: any(named: 'sinceDays'),
      ),
    ).thenAnswer(
      (_) async => const {
        'status': 'ready',
        'range': {'sinceDays': 365, 'since': '2025-08-29'},
        'exerciseCount': 0,
        'exercises': <Object?>[],
      },
    );
    when(
      () => coachingTrendsService.load(windowDays: any(named: 'windowDays')),
    ).thenAnswer(
      (_) async => const {
        'status': 'ready',
        'range': {'windowDays': 30},
      },
    );
  });

  List<WebMcpToolDefinition> tools(String route, {WebMcpNavigate? navigate}) {
    currentRoute = route;
    return coordinator.toolsForRoute(
      route: route,
      currentRoute: () => currentRoute,
      navigate: navigate ?? (_) {},
    );
  }

  test('publishes exact shell and route-scoped tool names', () {
    expect(_names(tools('/')), [
      'hustl_get_today_context',
      'hustl_open_surface',
      'hustl_get_training_context',
      'hustl_get_workout_history',
      'hustl_get_exercise_history',
    ]);
    expect(_names(tools('/health')), [
      'hustl_get_today_context',
      'hustl_open_surface',
      'hustl_get_recovery_context',
    ]);
    expect(_names(tools('/nutrition')), [
      'hustl_get_today_context',
      'hustl_open_surface',
      'hustl_get_nutrition_context',
      'hustl_get_food_log_entries',
      'hustl_propose_nutrition_targets',
      'hustl_propose_food_log',
      'hustl_propose_food_log_edit',
      'hustl_propose_food_log_delete',
    ]);
    expect(_names(tools('/workout_session')), [
      'hustl_get_today_context',
      'hustl_open_surface',
      'hustl_get_active_workout',
      'hustl_stage_workout_adjustment',
    ]);
    expect(_names(tools('/proposals')), [
      'hustl_get_today_context',
      'hustl_open_surface',
      'hustl_get_coach_activity',
      'hustl_get_coaching_trends',
      'hustl_open_proposal',
      'hustl_propose_nutrition_targets',
      'hustl_propose_food_log',
    ]);
    expect(_names(tools('/proposals/proposal-1')), [
      'hustl_get_today_context',
      'hustl_open_surface',
      'hustl_get_coach_activity',
      'hustl_get_coaching_trends',
      'hustl_open_proposal',
      'hustl_propose_nutrition_targets',
      'hustl_propose_food_log',
    ]);
    expect(_names(tools('/templates')), [
      'hustl_get_today_context',
      'hustl_open_surface',
      'hustl_propose_template',
    ]);
    expect(_names(tools('/templates/template-a')), [
      'hustl_get_today_context',
      'hustl_open_surface',
      'hustl_get_template_context',
      'hustl_propose_template_edit',
    ]);
    expect(_names(tools('/account')), [
      'hustl_get_today_context',
      'hustl_open_surface',
    ]);
  });

  test('publishes complete truthful annotations for every tool', () {
    const readOrOpen = <String, Object?>{
      'readOnlyHint': true,
      'destructiveHint': false,
      'idempotentHint': true,
      'openWorldHint': false,
    };
    const propose = <String, Object?>{
      'readOnlyHint': false,
      'destructiveHint': false,
      'idempotentHint': true,
      'openWorldHint': false,
    };
    const stage = <String, Object?>{
      'readOnlyHint': false,
      'destructiveHint': true,
      'idempotentHint': false,
      'openWorldHint': false,
    };
    final expected = <String, Map<String, Object?>>{
      for (final name in const [
        'hustl_get_today_context',
        'hustl_get_training_context',
        'hustl_get_workout_history',
        'hustl_get_exercise_history',
        'hustl_get_recovery_context',
        'hustl_get_nutrition_context',
        'hustl_get_food_log_entries',
        'hustl_get_active_workout',
        'hustl_get_coach_activity',
        'hustl_get_coaching_trends',
        'hustl_get_template_context',
        'hustl_open_surface',
        'hustl_open_proposal',
      ])
        name: readOrOpen,
      for (final name in const [
        'hustl_propose_nutrition_targets',
        'hustl_propose_food_log',
        'hustl_propose_food_log_edit',
        'hustl_propose_food_log_delete',
        'hustl_propose_template',
        'hustl_propose_template_edit',
      ])
        name: propose,
      'hustl_stage_workout_adjustment': stage,
    };
    final inventory = <String, WebMcpToolDefinition>{};

    for (final route in const [
      '/',
      '/health',
      '/nutrition',
      '/workout_session',
      '/proposals',
      '/templates',
      '/templates/template-a',
    ]) {
      for (final tool in tools(route)) {
        final prior = inventory[tool.name];
        if (prior != null) {
          expect(
            _annotations(tool),
            _annotations(prior),
            reason: '${tool.name} changed annotations on $route',
          );
        }
        inventory[tool.name] = tool;
      }
    }

    expect(inventory.keys.toSet(), expected.keys.toSet());
    for (final entry in expected.entries) {
      final annotations = _annotations(inventory[entry.key]!);
      expect(annotations, {
        ...entry.value,
        'untrustedContentHint': entry.key != 'hustl_open_surface',
      }, reason: entry.key);
    }
  });

  test(
    'Coach inbox and valid detail routes publish identical ordered descriptors',
    () {
      final inboxSnapshot = _registrationSnapshot(tools('/proposals'));

      expect(
        _registrationSnapshot(tools('/proposals/proposal-1')),
        inboxSnapshot,
      );
      expect(
        _registrationSnapshot(tools('/proposals/proposal%20two')),
        inboxSnapshot,
      );

      for (final invalidRoute in [
        '/proposals/',
        '/proposals/%20',
        '/proposals/%ZZ',
        '/proposals/one/two',
        '/proposals/${'a' * 129}',
        '/proposals/${'a' * 385}',
      ]) {
        expect(_names(tools(invalidRoute)), [
          'hustl_get_today_context',
          'hustl_open_surface',
        ], reason: invalidRoute);
      }
    },
  );

  test('only valid Coach review routes share a stable registration scope', () {
    for (final route in [
      '/proposals',
      '/proposals/proposal-1',
      '/proposals/proposal%20two',
    ]) {
      expect(
        coordinator.stableRegistrationScopeForRoute(route),
        '/proposals',
        reason: route,
      );
    }

    for (final route in [
      '/',
      '/account',
      '/proposals/',
      '/proposals/%20',
      '/proposals/%ZZ',
      '/proposals/one/two',
      '/templates/template-a',
      '/templates/template-b',
    ]) {
      expect(
        coordinator.stableRegistrationScopeForRoute(route),
        isNull,
        reason: route,
      );
    }
  });

  test('canonical five-review flow stays within the descriptor budget', () {
    final snapshots = <String>[
      '/',
      '/health',
      '/nutrition',
      '/proposals',
      '/nutrition',
      '/templates',
      '/proposals',
      '/proposals/nutrition-target-1',
      '/proposals',
      '/proposals/upper-a-1',
      '/proposals',
      '/proposals/lower-a-1',
      '/proposals',
      '/proposals/upper-b-1',
      '/proposals',
      '/proposals/lower-b-1',
      '/proposals',
    ].map((route) => _registrationSnapshot(tools(route))).toList();
    var descriptorChanges = 0;
    for (var index = 1; index < snapshots.length; index++) {
      if (snapshots[index] != snapshots[index - 1]) descriptorChanges++;
    }

    expect(descriptorChanges, 6);
    expect(descriptorChanges, lessThanOrEqualTo(10));
  });

  test(
    'route reads retain missing-versus-zero values and annotations',
    () async {
      final tool = _tool(tools('/nutrition'), 'hustl_get_nutrition_context');

      final result = await tool.handler(const {});

      expect(tool.readOnlyHint, isTrue);
      expect(tool.untrustedContentHint, isTrue);
      expect(result, containsPair('calories', 0));
      expect(result, containsPair('caloriesTarget', null));
      expect(result, containsPair('targetState', 'not_configured'));
    },
  );

  test('returns context and logs only static tool/status metadata', () async {
    final tool = _tool(tools('/'), 'hustl_get_today_context');

    final result = await tool.handler(const {});

    expect(result['status'], 'ready');
    expect(telemetry, [
      {
        'event': 'webmcp_tool_invoked',
        'tool': 'hustl_get_today_context',
        'status': 'started',
      },
      {
        'event': 'webmcp_tool_completed',
        'tool': 'hustl_get_today_context',
        'status': 'ready',
      },
    ]);
  });

  test('opens only the canonical route for an allowed surface', () async {
    String? openedRoute;
    final tool = _tool(
      tools('/', navigate: (route) => openedRoute = route),
      'hustl_open_surface',
    );

    final result = await tool.handler(const {'surface': 'recovery'});

    expect(result, {'status': 'opened', 'surface': 'recovery'});
    expect(openedRoute, '/health');

    expect(await tool.handler(const {'surface': 'templates'}), {
      'status': 'opened',
      'surface': 'templates',
    });
    expect(openedRoute, '/templates');
  });

  test('retained route callback fails closed after navigation', () async {
    final tool = _tool(tools('/health'), 'hustl_get_recovery_context');
    currentRoute = '/nutrition';

    expect(await tool.handler(const {}), {
      'status': 'unavailable',
      'code': 'stale_route',
    });
    verifyNever(() => service.load());
  });

  test('route read fails closed when navigation occurs mid-flight', () async {
    final completed = Completer<HustlTodayContext>();
    when(() => service.load()).thenAnswer((_) => completed.future);
    final tool = _tool(tools('/health'), 'hustl_get_recovery_context');

    final resultFuture = tool.handler(const {});
    currentRoute = '/nutrition';
    completed.complete(_context());

    expect(await resultFuture, {
      'status': 'unavailable',
      'code': 'stale_route',
    });
  });

  test('Train history tools publish strict bounded read schemas', () {
    final routeTools = tools('/');
    final workouts = _tool(routeTools, 'hustl_get_workout_history');
    final exercises = _tool(routeTools, 'hustl_get_exercise_history');
    final workoutProperties =
        workouts.inputSchema['properties'] as Map<String, Object?>;
    final exerciseProperties =
        exercises.inputSchema['properties'] as Map<String, Object?>;

    expect(workouts.readOnlyHint, isTrue);
    expect(workouts.untrustedContentHint, isTrue);
    expect(workouts.inputSchema['additionalProperties'], isFalse);
    expect(workoutProperties['limit'], containsPair('maximum', 20));
    expect(workoutProperties['cursor'], containsPair('maxLength', 1024));
    expect(exercises.readOnlyHint, isTrue);
    expect(exercises.untrustedContentHint, isTrue);
    expect(exercises.inputSchema['additionalProperties'], isFalse);
    expect(exerciseProperties['limit'], containsPair('maximum', 20));
    expect(exerciseProperties['sinceDays'], containsPair('maximum', 3650));
  });

  test('Train history tools apply defaults and pass explicit bounds', () async {
    final routeTools = tools('/');
    final workouts = _tool(routeTools, 'hustl_get_workout_history');
    final exercises = _tool(routeTools, 'hustl_get_exercise_history');

    expect(await workouts.handler(const {}), containsPair('status', 'ready'));
    expect(
      await workouts.handler(const {'limit': 20, 'cursor': 'page-2'}),
      containsPair('status', 'ready'),
    );
    expect(await exercises.handler(const {}), containsPair('status', 'ready'));
    expect(
      await exercises.handler(const {'limit': 7, 'sinceDays': 730}),
      containsPair('status', 'ready'),
    );

    verify(
      () => workoutHistoryService.loadWorkoutHistory(limit: 10, cursor: null),
    ).called(1);
    verify(
      () =>
          workoutHistoryService.loadWorkoutHistory(limit: 20, cursor: 'page-2'),
    ).called(1);
    verify(
      () =>
          workoutHistoryService.loadExerciseHistory(limit: 10, sinceDays: 365),
    ).called(1);
    verify(
      () => workoutHistoryService.loadExerciseHistory(limit: 7, sinceDays: 730),
    ).called(1);
  });

  test(
    'Train history tools reject invalid arguments before personal I/O',
    () async {
      final routeTools = tools('/');
      final workouts = _tool(routeTools, 'hustl_get_workout_history');
      final exercises = _tool(routeTools, 'hustl_get_exercise_history');

      for (final arguments in <Map<String, Object?>>[
        const {'limit': 0},
        const {'limit': 21},
        const {'limit': 1.5},
        const {'cursor': ''},
        const {'cursor': 'ok', 'unknown': true},
      ]) {
        expect(await workouts.handler(arguments), {
          'status': 'invalid_request',
          'code': 'invalid_arguments',
        });
      }
      for (final arguments in <Map<String, Object?>>[
        const {'limit': 0},
        const {'sinceDays': 0},
        const {'sinceDays': 3651},
        const {'sinceDays': 1.5},
        const {'unknown': true},
      ]) {
        expect(await exercises.handler(arguments), {
          'status': 'invalid_request',
          'code': 'invalid_arguments',
        });
      }

      verifyNever(
        () => workoutHistoryService.loadWorkoutHistory(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
        ),
      );
      verifyNever(
        () => workoutHistoryService.loadExerciseHistory(
          limit: any(named: 'limit'),
          sinceDays: any(named: 'sinceDays'),
        ),
      );
    },
  );

  test('retained Train history tools fail closed after navigation', () async {
    final routeTools = tools('/');
    final workouts = _tool(routeTools, 'hustl_get_workout_history');
    final exercises = _tool(routeTools, 'hustl_get_exercise_history');
    currentRoute = '/health';

    expect(await workouts.handler(const {}), {
      'status': 'unavailable',
      'code': 'stale_route',
    });
    expect(await exercises.handler(const {}), {
      'status': 'unavailable',
      'code': 'stale_route',
    });
    verifyNever(
      () => workoutHistoryService.loadWorkoutHistory(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
      ),
    );
    verifyNever(
      () => workoutHistoryService.loadExerciseHistory(
        limit: any(named: 'limit'),
        sinceDays: any(named: 'sinceDays'),
      ),
    );
  });

  test(
    'in-flight workout history is suppressed after an auth transition',
    () async {
      final completed = Completer<Map<String, Object?>>();
      when(
        () => workoutHistoryService.loadWorkoutHistory(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
        ),
      ).thenAnswer((_) => completed.future);
      final tool = _tool(tools('/'), 'hustl_get_workout_history');

      final resultFuture = tool.handler(const {});
      gate.closeForTransition();
      completed.complete(const {
        'status': 'ready',
        'workoutCount': 1,
        'workouts': <Object?>[
          {'name': 'private workout'},
        ],
      });

      expect(await resultFuture, {
        'status': 'unavailable',
        'code': 'auth_transition',
      });
    },
  );

  test(
    'in-flight exercise history is suppressed after route departure',
    () async {
      final completed = Completer<Map<String, Object?>>();
      when(
        () => workoutHistoryService.loadExerciseHistory(
          limit: any(named: 'limit'),
          sinceDays: any(named: 'sinceDays'),
        ),
      ).thenAnswer((_) => completed.future);
      final tool = _tool(tools('/'), 'hustl_get_exercise_history');

      final resultFuture = tool.handler(const {});
      currentRoute = '/nutrition';
      completed.complete(const {
        'status': 'ready',
        'exerciseCount': 1,
        'exercises': <Object?>[
          {'name': 'private exercise'},
        ],
      });

      expect(await resultFuture, {
        'status': 'unavailable',
        'code': 'stale_route',
      });
    },
  );

  test('history service exceptions are redacted', () async {
    when(
      () => workoutHistoryService.loadExerciseHistory(
        limit: any(named: 'limit'),
        sinceDays: any(named: 'sinceDays'),
      ),
    ).thenThrow(Exception('secret backend response'));
    final tool = _tool(tools('/'), 'hustl_get_exercise_history');

    expect(await tool.handler(const {}), {
      'status': 'error',
      'code': 'operation_unavailable',
    });
  });

  test('Coach trends publishes a strict bounded read schema', () {
    final tool = _tool(tools('/proposals'), 'hustl_get_coaching_trends');
    final properties = tool.inputSchema['properties'] as Map<String, Object?>;

    expect(tool.readOnlyHint, isTrue);
    expect(tool.untrustedContentHint, isTrue);
    expect(tool.inputSchema['additionalProperties'], isFalse);
    expect(properties['windowDays'], {
      'type': 'integer',
      'enum': [7, 30, 90],
      'default': 30,
    });
  });

  test('Coach trends applies its default and exact windows', () async {
    final tool = _tool(tools('/proposals'), 'hustl_get_coaching_trends');

    expect(await tool.handler(const {}), containsPair('status', 'ready'));
    for (final windowDays in [7, 30, 90]) {
      expect(
        await tool.handler({'windowDays': windowDays}),
        containsPair('status', 'ready'),
      );
    }

    verify(() => coachingTrendsService.load(windowDays: 30)).called(2);
    verify(() => coachingTrendsService.load(windowDays: 7)).called(1);
    verify(() => coachingTrendsService.load(windowDays: 90)).called(1);
  });

  test('Coach trends rejects invalid input before personal I/O', () async {
    final tool = _tool(tools('/proposals'), 'hustl_get_coaching_trends');

    for (final arguments in <Map<String, Object?>>[
      const {'windowDays': 8},
      const {'windowDays': 30.5},
      const {'windowDays': 30, 'unknown': true},
    ]) {
      expect(await tool.handler(arguments), {
        'status': 'invalid_request',
        'code': 'invalid_arguments',
      });
    }

    verifyNever(
      () => coachingTrendsService.load(windowDays: any(named: 'windowDays')),
    );
  });

  test(
    'retained Coach trends callback fails closed after navigation',
    () async {
      final tool = _tool(tools('/proposals'), 'hustl_get_coaching_trends');
      currentRoute = '/health';

      expect(await tool.handler(const {}), {
        'status': 'unavailable',
        'code': 'stale_route',
      });
      verifyNever(
        () => coachingTrendsService.load(windowDays: any(named: 'windowDays')),
      );
    },
  );

  test('in-flight Coach trends is suppressed after auth transition', () async {
    final completed = Completer<Map<String, Object?>>();
    when(
      () => coachingTrendsService.load(windowDays: any(named: 'windowDays')),
    ).thenAnswer((_) => completed.future);
    final tool = _tool(tools('/proposals'), 'hustl_get_coaching_trends');

    final resultFuture = tool.handler(const {'windowDays': 7});
    gate.closeForTransition();
    completed.complete(const {
      'status': 'ready',
      'privateTrend': 'must-not-escape',
    });

    expect(await resultFuture, {
      'status': 'unavailable',
      'code': 'auth_transition',
    });
  });

  test('Coach trends service exceptions are redacted', () async {
    when(
      () => coachingTrendsService.load(windowDays: any(named: 'windowDays')),
    ).thenThrow(Exception('secret backend response'));
    final tool = _tool(tools('/proposals'), 'hustl_get_coaching_trends');

    expect(await tool.handler(const {}), {
      'status': 'error',
      'code': 'operation_unavailable',
    });
  });

  test('Coach opens only an id from a fresh pending result', () async {
    when(
      () => proposals.listPending(limit: 50),
    ).thenAnswer((_) async => [_proposal]);
    String? openedRoute;
    final tool = _tool(
      tools(
        '/proposals',
        navigate: (route) {
          openedRoute = route;
          currentRoute = route;
        },
      ),
      'hustl_open_proposal',
    );

    expect(await tool.handler(const {'proposalId': 'not-mine'}), {
      'status': 'invalid_request',
      'code': 'proposal_not_pending',
    });
    expect(openedRoute, isNull);

    expect(await tool.handler(const {'proposalId': 'proposal-1'}), {
      'status': 'opened',
      'proposalId': 'proposal-1',
    });
    expect(openedRoute, '/proposals/proposal-1');
  });

  test(
    'Coach detail callbacks stay bound to the exact proposal route',
    () async {
      when(
        () => proposals.listPending(limit: 20),
      ).thenAnswer((_) async => [_proposal]);
      final tool = _tool(
        tools('/proposals/proposal-1'),
        'hustl_get_coach_activity',
      );

      expect(await tool.handler(const {}), containsPair('pendingCount', 1));

      currentRoute = '/proposals/proposal-2';
      expect(await tool.handler(const {}), {
        'status': 'unavailable',
        'code': 'stale_route',
      });
      verify(() => proposals.listPending(limit: 20)).called(1);
    },
  );

  test(
    'Coach returns bounded pending proposals and recent decisions',
    () async {
      when(
        () => proposals.listPending(limit: 20),
      ).thenAnswer((_) async => [_proposal]);
      when(
        () => proposals.listDecided(
          statuses: const ['applied', 'reverted', 'rejected'],
          limit: 10,
        ),
      ).thenAnswer((_) async => [_decisionProposal]);
      final tool = _tool(tools('/proposals'), 'hustl_get_coach_activity');

      final result = await tool.handler(const {});

      expect(result, {
        'status': 'ready',
        'pendingCount': 1,
        'proposals': [
          {
            'id': 'proposal-1',
            'kind': 'nutritionTargets',
            'title': 'Nutrition update',
            'summary': 'Adjust targets',
            'createdAt': '2026-08-26T00:00:00.000',
            'expiresAt': null,
            'conflictReason': null,
          },
        ],
        'recentDecisionsState': 'ready',
        'recentDecisionCount': 1,
        'recentDecisions': [
          {
            'id': 'decision-1',
            'kind': 'foodLog',
            'title': 'Food log',
            'summary': 'Logged breakfast',
            'createdAt': '2026-08-28T01:00:00.000Z',
            'expiresAt': null,
            'conflictReason': null,
            'status': 'applied',
            'decidedAt': '2026-08-28T01:05:00.000Z',
            'autoApplied': true,
          },
        ],
      });
      verify(() => proposals.listPending(limit: 20)).called(1);
      verify(
        () => proposals.listDecided(
          statuses: const ['applied', 'reverted', 'rejected'],
          limit: 10,
        ),
      ).called(1);
    },
  );

  test(
    'Coach preserves pending activity when decision history fails',
    () async {
      when(
        () => proposals.listPending(limit: 20),
      ).thenAnswer((_) async => [_proposal]);
      when(
        () => proposals.listDecided(
          statuses: const ['applied', 'reverted', 'rejected'],
          limit: 10,
        ),
      ).thenThrow(Exception('secret backend detail'));
      final tool = _tool(tools('/proposals'), 'hustl_get_coach_activity');

      final result = await tool.handler(const {});

      expect(result['status'], 'ready');
      expect(result['pendingCount'], 1);
      expect(result['recentDecisionsState'], 'unavailable');
      expect(result['recentDecisionCount'], 0);
      expect(result['recentDecisions'], isEmpty);
      expect(result.toString(), isNot(contains('secret backend detail')));
    },
  );

  test(
    'Coach caps repository results before returning personal data',
    () async {
      when(
        () => proposals.listPending(limit: 20),
      ).thenAnswer((_) async => List.filled(21, _proposal));
      when(
        () => proposals.listDecided(
          statuses: const ['applied', 'reverted', 'rejected'],
          limit: 10,
        ),
      ).thenAnswer((_) async => List.filled(11, _decisionProposal));
      final tool = _tool(tools('/proposals'), 'hustl_get_coach_activity');

      final result = await tool.handler(const {});

      expect(result['pendingCount'], 20);
      expect(result['proposals'], hasLength(20));
      expect(result['recentDecisionCount'], 10);
      expect(result['recentDecisions'], hasLength(10));
    },
  );

  test(
    'nutrition proposal returns without waiting for badge refresh',
    () async {
      when(() => proposals.proposeNutritionTargets(any())).thenAnswer(
        (_) async => NutritionProposalResult(
          status: 'pending',
          proposalId: _proposal.id,
          proposal: _proposalDetail,
        ),
      );
      final tool = _tool(
        tools('/nutrition'),
        'hustl_propose_nutrition_targets',
      );
      final badgeRefresh = Completer<void>();
      when(
        () => proposalCount.refreshNow(),
      ).thenAnswer((_) => badgeRefresh.future);

      final result = await tool
          .handler(const {
            'caloriesTarget': 2350,
            'proteinTarget': 180,
            'carbsTarget': 250,
            'fatTarget': 70,
            'rationale': 'Fuel training.',
          })
          .timeout(const Duration(milliseconds: 200));

      expect(result, {
        'status': 'pending',
        'proposalId': 'proposal-1',
        'requiresHumanReview': true,
        'message': 'Nothing changed yet. Review this proposal in Hustl.',
      });
      verify(() => proposalCount.refreshNow()).called(1);
      badgeRefresh.complete();
    },
  );

  test('nutrition proposal truthfully surfaces the shared rate limit', () async {
    when(
      () => proposals.proposeNutritionTargets(any()),
    ).thenThrow(const ProposalUnavailable('proposal_rate_limited'));
    final tool = _tool(tools('/nutrition'), 'hustl_propose_nutrition_targets');

    expect(
      await tool.handler(const {
        'caloriesTarget': 2350,
        'proteinTarget': 180,
        'carbsTarget': 250,
        'fatTarget': 70,
      }),
      const {
        'status': 'unavailable',
        'code': 'proposal_rate_limited',
        'message':
            'Proposal creation is temporarily rate limited. Try again shortly.',
      },
    );
  });

  test('food-log schema requires a bounded explicitly dated payload', () {
    final tool = _tool(tools('/nutrition'), 'hustl_propose_food_log');
    final payload = tool.inputSchema['properties'] as Map<String, Object?>;
    final payloadSchema = payload['payload'] as Map<String, Object?>;
    final payloadProperties =
        payloadSchema['properties'] as Map<String, Object?>;
    final items = payloadProperties['items'] as Map<String, Object?>;

    expect(tool.inputSchema['required'], ['payload']);
    expect(payloadSchema['required'], ['date', 'items']);
    expect(payloadSchema['additionalProperties'], isFalse);
    expect(items['minItems'], 1);
    expect(items['maxItems'], 20);
  });

  test(
    'food-log proposal creates a pending review without waiting for badge',
    () async {
      when(() => proposals.proposeFoodLog(any())).thenAnswer(
        (_) async => FoodLogProposalResult(
          status: 'pending',
          proposalId: _foodProposal.id,
          proposal: _foodProposalDetail,
        ),
      );
      final tool = _tool(tools('/nutrition'), 'hustl_propose_food_log');
      final badgeRefresh = Completer<void>();
      when(
        () => proposalCount.refreshNow(),
      ).thenAnswer((_) => badgeRefresh.future);

      final result = await tool
          .handler(_appleArguments)
          .timeout(const Duration(milliseconds: 200));

      expect(result, {
        'status': 'pending',
        'proposalId': 'food-proposal-1',
        'requiresHumanReview': true,
        'message': 'Nothing is logged yet. Review this proposal in Hustl.',
      });
      final captured =
          verify(() => proposals.proposeFoodLog(captureAny())).captured.single
              as FoodLogProposalInput;
      expect(captured.date, '2026-08-28');
      expect(captured.items.single.foodName, 'Apple');
      expect(captured.items.single.calories, 95);
      verify(() => proposalCount.refreshNow()).called(1);
      badgeRefresh.complete();
    },
  );

  test('food-log proposal truthfully surfaces the shared rate limit', () async {
    when(
      () => proposals.proposeFoodLog(any()),
    ).thenThrow(const ProposalUnavailable('proposal_rate_limited'));
    final tool = _tool(tools('/nutrition'), 'hustl_propose_food_log');

    expect(await tool.handler(_appleArguments), const {
      'status': 'unavailable',
      'code': 'proposal_rate_limited',
      'message':
          'Proposal creation is temporarily rate limited. Try again shortly.',
    });
    expect(diaryRefreshCount, 0);
  });

  test(
    'food-log applied result is truthful, refreshes diary, and is undoable',
    () async {
      when(() => proposals.proposeFoodLog(any())).thenAnswer(
        (_) async => FoodLogProposalResult(
          status: 'applied',
          proposalId: _foodProposal.id,
          proposal: _foodProposalDetail,
          humanMessage:
              'Logged this food automatically. You can review it in AI Activity and Undo it there.',
        ),
      );
      final tool = _tool(tools('/proposals'), 'hustl_propose_food_log');

      expect(await tool.handler(_appleArguments), {
        'status': 'applied',
        'proposalId': 'food-proposal-1',
        'requiresHumanReview': false,
        'message':
            'Logged this food automatically. You can review it in AI Activity and Undo it there.',
      });
      expect(diaryRefreshCount, 1);
    },
  );

  test('food-log proposal rejects invalid input without persistence', () async {
    final tool = _tool(tools('/nutrition'), 'hustl_propose_food_log');
    final invalidArguments = <Map<String, Object?>>[
      const {},
      const {
        'payload': {'items': []},
      },
      const {
        'payload': {'date': '2026-02-31', 'items': []},
      },
      const {
        'payload': {
          'date': '2026-08-28',
          'items': [
            {
              'foodName': 'Apple',
              'servingGrams': 0,
              'calories': 95,
              'proteinGrams': 0.5,
              'carbsGrams': 25,
              'fatGrams': 0.3,
            },
          ],
        },
      },
      {
        'payload': {
          ...(_appleArguments['payload']! as Map<String, Object?>),
          'approve': true,
        },
      },
      {
        'payload': {
          ...(_appleArguments['payload']! as Map<String, Object?>),
          'date': '0099-12-31',
        },
      },
      {
        'payload': {
          'date': '2026-08-28',
          'items': List<Object?>.filled(
            21,
            ((_appleArguments['payload']! as Map)['items']! as List).single,
          ),
        },
      },
      {
        'payload': {
          'date': '2026-08-28',
          'items': [
            {
              ...((((_appleArguments['payload']! as Map)['items']! as List)
                      .single)
                  as Map<String, Object?>),
              'sodiumMg': 100001,
            },
          ],
        },
      },
    ];

    for (final arguments in invalidArguments) {
      expect(await tool.handler(arguments), {
        'status': 'invalid_request',
        'code': 'invalid_arguments',
      });
    }
    verifyNever(() => proposals.proposeFoodLog(any()));
  });

  test('retained food-log tool fails before repository invocation', () async {
    final tool = _tool(tools('/nutrition'), 'hustl_propose_food_log');
    currentRoute = '/health';

    expect(await tool.handler(_appleArguments), {
      'status': 'unavailable',
      'code': 'stale_route',
    });
    verifyNever(() => proposals.proposeFoodLog(any()));
  });

  test(
    'food-log tool fails before repository invocation during auth',
    () async {
      final tool = _tool(tools('/nutrition'), 'hustl_propose_food_log');
      gate.closeForTransition();

      expect(await tool.handler(_appleArguments), {
        'status': 'unavailable',
        'code': 'auth_transition',
      });
      verifyNever(() => proposals.proposeFoodLog(any()));
    },
  );

  test('food-log result is discarded if route changes mid-flight', () async {
    final completed = Completer<FoodLogProposalResult>();
    when(
      () => proposals.proposeFoodLog(any()),
    ).thenAnswer((_) => completed.future);
    final tool = _tool(tools('/nutrition'), 'hustl_propose_food_log');

    final resultFuture = tool.handler(_appleArguments);
    currentRoute = '/health';
    completed.complete(
      FoodLogProposalResult(
        status: 'pending',
        proposalId: _foodProposal.id,
        proposal: _foodProposalDetail,
      ),
    );

    expect(await resultFuture, {
      'status': 'unavailable',
      'code': 'stale_route',
    });
    verify(() => proposals.proposeFoodLog(any())).called(1);
  });

  test('food-log result is discarded if auth changes mid-flight', () async {
    final completed = Completer<FoodLogProposalResult>();
    when(
      () => proposals.proposeFoodLog(any()),
    ).thenAnswer((_) => completed.future);
    final tool = _tool(tools('/nutrition'), 'hustl_propose_food_log');

    final resultFuture = tool.handler(_appleArguments);
    gate.closeForTransition();
    completed.complete(
      FoodLogProposalResult(
        status: 'pending',
        proposalId: _foodProposal.id,
        proposal: _foodProposalDetail,
      ),
    );

    expect(await resultFuture, {
      'status': 'unavailable',
      'code': 'auth_transition',
    });
  });

  test('itemized food-log read is explicit, bounded, and lossless', () async {
    when(() => foodLogs.getLogsForDateReadOnly(any())).thenAnswer(
      (_) async => List.generate(
        51,
        (index) => _foodEntry(
          id: '11111111-1111-4111-8111-${index.toString().padLeft(12, '0')}',
          fiberGrams: index == 0 ? null : 3,
        ),
      ),
    );
    final tool = _tool(tools('/nutrition'), 'hustl_get_food_log_entries');

    final result = await tool.handler(const {'date': '2026-08-28'});
    final entries = result['entries']! as List<Object?>;

    expect(result['status'], 'ready');
    expect(result['date'], '2026-08-28');
    expect(result['entryCount'], 50);
    expect(result['truncated'], isTrue);
    expect(entries, hasLength(50));
    expect(entries.first, {
      'id': '11111111-1111-4111-8111-000000000000',
      'revisable': true,
      'date': '2026-08-28',
      'consumedAt': '2026-08-28T04:00:00.000Z',
      'foodName': 'Chicken rice',
      'servingGrams': 350.0,
      'calories': 520.0,
      'proteinGrams': 42.0,
      'carbsGrams': 58.0,
      'fatGrams': 14.0,
      'fiberGrams': null,
      'sugarGrams': null,
      'sodiumMg': 640.0,
      'source': 'self',
    });
    final captured =
        verify(
              () => foodLogs.getLogsForDateReadOnly(captureAny()),
            ).captured.single
            as DateTime;
    expect(captured, DateTime(2026, 8, 28));
  });

  test('itemized read marks queued offline entries non-revisable', () async {
    when(
      () => foodLogs.getLogsForDateReadOnly(any()),
    ).thenAnswer((_) async => [_foodEntry(id: 'temp-offline-1')]);
    final tool = _tool(tools('/nutrition'), 'hustl_get_food_log_entries');

    final result = await tool.handler(const {'date': '2026-08-28'});
    final entries = result['entries']! as List<Object?>;
    final entry = entries.single! as Map<String, Object?>;

    expect(entry['id'], 'temp-offline-1');
    expect(entry['revisable'], isFalse);
  });

  test('itemized read rejects invalid dates and retained routes', () async {
    final tool = _tool(tools('/nutrition'), 'hustl_get_food_log_entries');

    expect(await tool.handler(const {'date': '2026-02-31'}), {
      'status': 'invalid_request',
      'code': 'invalid_arguments',
    });
    currentRoute = '/health';
    expect(await tool.handler(const {'date': '2026-08-28'}), {
      'status': 'unavailable',
      'code': 'stale_route',
    });
    verifyNever(() => foodLogs.getLogsForDateReadOnly(any()));
  });

  test('food revision schemas mirror strict backend caps', () {
    final edit = _tool(tools('/nutrition'), 'hustl_propose_food_log_edit');
    final remove = _tool(tools('/nutrition'), 'hustl_propose_food_log_delete');
    final editProperties =
        edit.inputSchema['properties'] as Map<String, Object?>;
    final editPayload = editProperties['payload'] as Map<String, Object?>;
    final payloadProperties = editPayload['properties'] as Map<String, Object?>;
    final changes = payloadProperties['changes'] as Map<String, Object?>;

    expect(edit.inputSchema['additionalProperties'], isFalse);
    expect(editPayload['additionalProperties'], isFalse);
    expect(changes['minProperties'], 1);
    expect(changes['additionalProperties'], isFalse);
    expect(remove.inputSchema['additionalProperties'], isFalse);
  });

  test('food edit creates a review-only proposal', () async {
    when(() => foodLogRevisions.proposeFoodLogEdit(any())).thenAnswer(
      (_) async => FoodLogRevisionProposalResult(
        status: 'pending',
        proposalId: _revisionProposal.id,
        proposal: _revisionProposalDetail,
      ),
    );
    final tool = _tool(tools('/nutrition'), 'hustl_propose_food_log_edit');

    expect(await tool.handler(_foodEditArguments), {
      'status': 'pending',
      'proposalId': 'revision-proposal-1',
      'requiresHumanReview': true,
      'message': 'Nothing changed yet. Review this correction in Hustl.',
    });
    final input =
        verify(
              () => foodLogRevisions.proposeFoodLogEdit(captureAny()),
            ).captured.single
            as FoodLogEditProposalInput;
    expect(input.targetEntryId, _entryId);
    expect(input.changes.servingGrams, 200);
    expect(input.changes.calories, 330);
    verify(() => proposalCount.refreshNow()).called(1);
    expect(diaryRefreshCount, 0);
  });

  test('food delete creates a review-only proposal', () async {
    when(() => foodLogRevisions.proposeFoodLogDelete(any())).thenAnswer(
      (_) async => FoodLogRevisionProposalResult(
        status: 'pending',
        proposalId: _revisionProposal.id,
        proposal: _revisionProposalDetail,
      ),
    );
    final tool = _tool(tools('/nutrition'), 'hustl_propose_food_log_delete');

    expect(await tool.handler(_foodDeleteArguments), {
      'status': 'pending',
      'proposalId': 'revision-proposal-1',
      'requiresHumanReview': true,
      'message': 'Nothing changed yet. Review this removal in Hustl.',
    });
    final input =
        verify(
              () => foodLogRevisions.proposeFoodLogDelete(captureAny()),
            ).captured.single
            as FoodLogDeleteProposalInput;
    expect(input.targetEntryId, _entryId);
    expect(diaryRefreshCount, 0);
  });

  test('food revisions reject invalid input before persistence', () async {
    final edit = _tool(tools('/nutrition'), 'hustl_propose_food_log_edit');
    final remove = _tool(tools('/nutrition'), 'hustl_propose_food_log_delete');
    final invalidEdits = <Map<String, Object?>>[
      const {},
      const {
        'payload': {
          'targetEntryId': 'bad',
          'changes': {'calories': 10},
        },
      },
      const {
        'payload': {'targetEntryId': _entryId, 'changes': {}},
      },
      const {
        'payload': {
          'targetEntryId': _entryId,
          'changes': {'servingGrams': 0},
        },
      },
      const {
        'payload': {
          'targetEntryId': _entryId,
          'changes': {'calories': 5001},
        },
      },
      const {
        'payload': {
          'targetEntryId': _entryId,
          'changes': {'date': '2026-08-28'},
        },
      },
    ];
    for (final arguments in invalidEdits) {
      expect(await edit.handler(arguments), {
        'status': 'invalid_request',
        'code': 'invalid_arguments',
      });
    }
    expect(
      await remove.handler(const {
        'payload': {'targetEntryId': _entryId, 'approve': true},
      }),
      {'status': 'invalid_request', 'code': 'invalid_arguments'},
    );
    verifyNever(() => foodLogRevisions.proposeFoodLogEdit(any()));
    verifyNever(() => foodLogRevisions.proposeFoodLogDelete(any()));
  });

  test('food revision surfaces missing targets and proposal limits', () async {
    when(
      () => foodLogRevisions.proposeFoodLogEdit(any()),
    ).thenThrow(const FoodLogRevisionTargetUnavailable());
    when(
      () => foodLogRevisions.proposeFoodLogDelete(any()),
    ).thenThrow(const ProposalUnavailable('pending_cap_exceeded'));
    final routeTools = tools('/nutrition');

    expect(
      await _tool(
        routeTools,
        'hustl_propose_food_log_edit',
      ).handler(_foodEditArguments),
      {'status': 'unavailable', 'code': 'food_entry_not_found'},
    );
    expect(
      await _tool(
        routeTools,
        'hustl_propose_food_log_delete',
      ).handler(_foodDeleteArguments),
      {
        'status': 'unavailable',
        'code': 'pending_cap_exceeded',
        'message':
            'Too many proposals are waiting for review. Review or dismiss one in Hustl before trying again.',
      },
    );
  });

  test('retained food revision tools fail before persistence', () async {
    final edit = _tool(tools('/nutrition'), 'hustl_propose_food_log_edit');
    final remove = _tool(tools('/nutrition'), 'hustl_propose_food_log_delete');
    currentRoute = '/health';

    expect(await edit.handler(_foodEditArguments), {
      'status': 'unavailable',
      'code': 'stale_route',
    });
    expect(await remove.handler(_foodDeleteArguments), {
      'status': 'unavailable',
      'code': 'stale_route',
    });
    verifyNever(() => foodLogRevisions.proposeFoodLogEdit(any()));
    verifyNever(() => foodLogRevisions.proposeFoodLogDelete(any()));
  });

  test('food revision result is discarded on auth transition', () async {
    final completed = Completer<FoodLogRevisionProposalResult>();
    when(
      () => foodLogRevisions.proposeFoodLogEdit(any()),
    ).thenAnswer((_) => completed.future);
    final tool = _tool(tools('/nutrition'), 'hustl_propose_food_log_edit');

    final resultFuture = tool.handler(_foodEditArguments);
    gate.closeForTransition();
    completed.complete(
      FoodLogRevisionProposalResult(
        status: 'pending',
        proposalId: _revisionProposal.id,
        proposal: _revisionProposalDetail,
      ),
    );

    expect(await resultFuture, {
      'status': 'unavailable',
      'code': 'auth_transition',
    });
  });

  test('template schemas are strict and edit target is not agent supplied', () {
    final create = _tool(tools('/templates'), 'hustl_propose_template');
    final edit = _tool(
      tools('/templates/template-a'),
      'hustl_propose_template_edit',
    );
    final createProperties =
        create.inputSchema['properties'] as Map<String, Object?>;
    final editProperties =
        edit.inputSchema['properties'] as Map<String, Object?>;
    final plan = createProperties['plan'] as Map<String, Object?>;
    final planProperties = plan['properties'] as Map<String, Object?>;
    final exercises = planProperties['exercises'] as Map<String, Object?>;
    final exerciseSchema = exercises['items'] as Map<String, Object?>;
    final exerciseProperties =
        exerciseSchema['properties'] as Map<String, Object?>;
    final rpeSchema = exerciseProperties['rpeTarget'] as Map<String, Object?>;

    expect(create.inputSchema['additionalProperties'], isFalse);
    expect(edit.inputSchema['additionalProperties'], isFalse);
    expect(editProperties, isNot(contains('targetTemplateId')));
    expect(editProperties, contains('baseUpdatedAt'));
    expect(
      edit.inputSchema['required'],
      containsAll(<String>['plan', 'baseUpdatedAt']),
    );
    expect(exercises['minItems'], 1);
    expect(exercises['maxItems'], 30);
    expect(rpeSchema['type'], 'integer');
  });

  test(
    'Templates creates a pending template proposal with strict input',
    () async {
      when(() => proposals.proposeTemplate(any())).thenAnswer(
        (_) async => TemplateProposalResult(
          status: 'pending',
          proposalId: _templateProposal.id,
          proposal: _templateProposalDetail,
        ),
      );
      final tool = _tool(tools('/templates'), 'hustl_propose_template');

      expect(await tool.handler(const {'plan': _templatePlanArguments}), {
        'status': 'pending',
        'proposalId': 'template-proposal-1',
        'requiresHumanReview': true,
        'message':
            'Nothing changed yet. Review this workout template in Hustl.',
      });
      final captured =
          verify(() => proposals.proposeTemplate(captureAny())).captured.single
              as TemplateProposalPlan;
      expect(captured, _templatePlan);
    },
  );

  test(
    'template create surfaces proposal limits instead of a generic error',
    () async {
      when(
        () => proposals.proposeTemplate(any()),
      ).thenThrow(const TemplateProposalUnavailable('pending_cap_exceeded'));
      final tool = _tool(tools('/templates'), 'hustl_propose_template');

      expect(await tool.handler(const {'plan': _templatePlanArguments}), {
        'status': 'unavailable',
        'code': 'pending_cap_exceeded',
        'message':
            'Too many proposals are waiting for review. Review or dismiss one in Hustl before trying again.',
      });
    },
  );

  test('template context returns bounded route-owned edit input', () async {
    when(
      () => templateService.load('template-a'),
    ).thenAnswer((_) async => _templateContext);
    final tool = _tool(
      tools('/templates/template-a'),
      'hustl_get_template_context',
    );

    final result = await tool.handler(const {});

    expect(result['templateId'], 'template-a');
    expect(result['plan'], _templatePlan.toJson());
    expect(result['lossyOnEdit'], isFalse);
  });

  test(
    'lossy template edit requires explicit normalization acknowledgement',
    () async {
      when(() => templateService.load('template-a')).thenAnswer(
        (_) async => TemplateWebMcpContext(
          templateId: 'template-a',
          updatedAt: DateTime.utc(2026, 8, 28),
          plan: _templatePlan,
          lossyOnEdit: true,
          syncedForEdit: true,
        ),
      );
      final tool = _tool(
        tools('/templates/template-a'),
        'hustl_propose_template_edit',
      );

      expect(
        await tool.handler(const {
          'plan': _templatePlanArguments,
          'baseUpdatedAt': _templateUpdatedAt,
        }),
        {
          'status': 'confirmation_required',
          'code': 'lossy_template_edit',
          'requiresAcknowledgement': true,
          'warning': templateNormalizationWarning,
        },
      );
      verifyNever(() => proposals.proposeTemplateEdit(any(), any(), any()));
    },
  );

  test(
    'acknowledged edit proposes only for the visible route target',
    () async {
      when(
        () => templateService.load('template-a'),
      ).thenAnswer((_) async => _templateContext);
      when(() => proposals.proposeTemplateEdit(any(), any(), any())).thenAnswer(
        (_) async => TemplateProposalResult(
          status: 'pending',
          proposalId: _templateProposal.id,
          proposal: _templateProposalDetail,
        ),
      );
      final tool = _tool(
        tools('/templates/template-a'),
        'hustl_propose_template_edit',
      );

      expect(
        await tool.handler(const {
          'plan': _templatePlanArguments,
          'baseUpdatedAt': _templateUpdatedAt,
          'acknowledgeNormalization': true,
        }),
        {
          'status': 'pending',
          'proposalId': 'template-proposal-1',
          'targetTemplateId': 'template-a',
          'requiresHumanReview': true,
          'message': 'Nothing changed yet. Review this template edit in Hustl.',
        },
      );
      verify(
        () => proposals.proposeTemplateEdit(
          'template-a',
          DateTime.utc(2026, 8, 28),
          _templatePlan,
        ),
      ).called(1);
    },
  );

  test(
    'template edit fails closed when the visible template is not synced',
    () async {
      when(() => templateService.load('template-a')).thenAnswer(
        (_) async => TemplateWebMcpContext(
          templateId: 'template-a',
          updatedAt: DateTime.utc(2026, 8, 28),
          plan: _templatePlan,
          lossyOnEdit: false,
          syncedForEdit: false,
        ),
      );
      final tool = _tool(
        tools('/templates/template-a'),
        'hustl_propose_template_edit',
      );

      expect(
        await tool.handler(const {
          'plan': _templatePlanArguments,
          'baseUpdatedAt': _templateUpdatedAt,
        }),
        {'status': 'unavailable', 'code': 'template_not_synced'},
      );
      verifyNever(() => proposals.proposeTemplateEdit(any(), any(), any()));
    },
  );

  test('template edit is bound to the exact context read version', () async {
    when(
      () => templateService.load('template-a'),
    ).thenAnswer((_) async => _templateContext);
    final tool = _tool(
      tools('/templates/template-a'),
      'hustl_propose_template_edit',
    );

    expect(
      await tool.handler(const {
        'plan': _templatePlanArguments,
        'baseUpdatedAt': '2026-08-27T00:00:00.000Z',
      }),
      {'status': 'conflict', 'code': 'template_changed'},
    );
    verifyNever(() => proposals.proposeTemplateEdit(any(), any(), any()));
  });

  test('template edit surfaces a server-side version conflict', () async {
    when(
      () => templateService.load('template-a'),
    ).thenAnswer((_) async => _templateContext);
    when(
      () => proposals.proposeTemplateEdit(any(), any(), any()),
    ).thenThrow(const TemplateProposalConflict());
    final tool = _tool(
      tools('/templates/template-a'),
      'hustl_propose_template_edit',
    );

    expect(
      await tool.handler(const {
        'plan': _templatePlanArguments,
        'baseUpdatedAt': _templateUpdatedAt,
      }),
      {'status': 'conflict', 'code': 'template_changed'},
    );
  });

  test(
    'template edit surfaces proposal limits instead of a generic error',
    () async {
      when(
        () => templateService.load('template-a'),
      ).thenAnswer((_) async => _templateContext);
      when(
        () => proposals.proposeTemplateEdit(any(), any(), any()),
      ).thenThrow(const TemplateProposalUnavailable('proposal_rate_limited'));
      final tool = _tool(
        tools('/templates/template-a'),
        'hustl_propose_template_edit',
      );

      expect(
        await tool.handler(const {
          'plan': _templatePlanArguments,
          'baseUpdatedAt': _templateUpdatedAt,
        }),
        {
          'status': 'unavailable',
          'code': 'proposal_rate_limited',
          'message':
              'Proposal creation is temporarily rate limited. Try again shortly.',
        },
      );
    },
  );

  test(
    'template proposal rejects unknown fields and stale routes before writes',
    () async {
      final create = _tool(tools('/templates'), 'hustl_propose_template');
      expect(
        await create.handler({
          'plan': <String, Object?>{
            'name': _templatePlanArguments['name'],
            'description': _templatePlanArguments['description'],
            'exercises': [
              {'exerciseId': 'Hack Squat', 'sets': 21, 'restTimerSeconds': 150},
            ],
          },
        }),
        {'status': 'invalid_request', 'code': 'invalid_arguments'},
      );
      expect(
        await create.handler({
          'plan': <String, Object?>{
            'name': _templatePlanArguments['name'],
            'description': _templatePlanArguments['description'],
            'exercises': [
              {
                'exerciseId': 'Hack Squat',
                'sets': 4,
                'restTimerSeconds': 150,
                'rpeTarget': 7.5,
              },
            ],
          },
        }),
        {'status': 'invalid_request', 'code': 'invalid_arguments'},
      );
      expect(
        await create.handler(const {
          'plan': _templatePlanArguments,
          'targetTemplateId': 'other',
        }),
        {'status': 'invalid_request', 'code': 'invalid_arguments'},
      );
      currentRoute = '/health';
      expect(await create.handler(const {'plan': _templatePlanArguments}), {
        'status': 'unavailable',
        'code': 'stale_route',
      });
      verifyNever(() => proposals.proposeTemplate(any()));
    },
  );

  test('template edit rechecks route after its prerequisite read', () async {
    final completed = Completer<TemplateWebMcpContext?>();
    when(
      () => templateService.load('template-a'),
    ).thenAnswer((_) => completed.future);
    final tool = _tool(
      tools('/templates/template-a'),
      'hustl_propose_template_edit',
    );

    final resultFuture = tool.handler(const {
      'plan': _templatePlanArguments,
      'baseUpdatedAt': _templateUpdatedAt,
    });
    currentRoute = '/health';
    completed.complete(_templateContext);

    expect(await resultFuture, {
      'status': 'unavailable',
      'code': 'stale_route',
    });
    verifyNever(() => proposals.proposeTemplateEdit(any(), any(), any()));
  });

  test(
    'template edit rechecks auth generation after its prerequisite read',
    () async {
      final completed = Completer<TemplateWebMcpContext?>();
      when(
        () => templateService.load('template-a'),
      ).thenAnswer((_) => completed.future);
      final tool = _tool(
        tools('/templates/template-a'),
        'hustl_propose_template_edit',
      );

      final resultFuture = tool.handler(const {
        'plan': _templatePlanArguments,
        'baseUpdatedAt': _templateUpdatedAt,
      });
      gate.closeForTransition();
      gate.setReady(true);
      completed.complete(_templateContext);

      expect(await resultFuture, {
        'status': 'unavailable',
        'code': 'auth_transition',
      });
      verifyNever(() => proposals.proposeTemplateEdit(any(), any(), any()));
    },
  );

  test('rejects unknown and over-specified navigation arguments', () async {
    var navigationCount = 0;
    final tool = _tool(
      tools('/', navigate: (_) => navigationCount++),
      'hustl_open_surface',
    );

    final unknown = await tool.handler(const {'surface': '/admin'});
    final extra = await tool.handler(const {
      'surface': 'train',
      'route': '/admin',
    });

    expect(unknown['code'], 'unknown_surface');
    expect(extra['code'], 'invalid_arguments');
    expect(navigationCount, 0);
  });

  test('converts unexpected context failure to a generic error', () async {
    when(() => service.load()).thenThrow(StateError('secret backend detail'));
    final tool = _tool(tools('/'), 'hustl_get_today_context');

    final result = await tool.handler(const {});

    expect(result, {'status': 'error', 'code': 'context_unavailable'});
    expect(result.toString(), isNot(contains('secret backend detail')));
  });

  test('fails closed during an auth or account migration transition', () async {
    gate.setReady(false);
    var navigationCount = 0;
    final routeTools = tools('/', navigate: (_) => navigationCount++);

    expect(await routeTools.first.handler(const {}), {
      'status': 'unavailable',
      'code': 'auth_transition',
    });
    expect(
      await _tool(
        routeTools,
        'hustl_open_surface',
      ).handler(const {'surface': 'train'}),
      {'status': 'unavailable', 'code': 'auth_transition'},
    );
    verifyNever(() => service.load());
    expect(navigationCount, 0);
  });

  test('discards a context read if auth transitions mid-flight', () async {
    final completed = Completer<HustlTodayContext>();
    when(() => service.load()).thenAnswer((_) => completed.future);
    final tool = _tool(tools('/'), 'hustl_get_today_context');

    final resultFuture = tool.handler(const {});
    gate.closeForTransition();
    completed.complete(_context());

    expect(await resultFuture, {
      'status': 'unavailable',
      'code': 'auth_transition',
    });
  });
}

List<String> _names(List<WebMcpToolDefinition> tools) =>
    tools.map((tool) => tool.name).toList();

String _registrationSnapshot(List<WebMcpToolDefinition> tools) => jsonEncode(
  tools.map((tool) => tool.toRegistrationJson()).toList(growable: false),
);

Map<String, Object?> _annotations(WebMcpToolDefinition tool) =>
    Map<String, Object?>.from(tool.toRegistrationJson()['annotations']! as Map);

WebMcpToolDefinition _tool(List<WebMcpToolDefinition> tools, String name) =>
    tools.singleWhere((tool) => tool.name == name);

final _proposal = ProposalSummary(
  id: 'proposal-1',
  kind: ProposalKind.nutritionTargets,
  status: 'pending',
  templateName: 'Nutrition update',
  exerciseCount: 0,
  summary: 'Adjust targets',
  createdAt: DateTime(2026, 8, 26),
);

final _proposalDetail = ProposalDetail(
  summary: _proposal,
  proposedExercises: const [],
  resolvedExercises: const [],
  proposedNutrition: const ProposedNutritionTarget(
    caloriesTarget: 2350,
    proteinTarget: 180,
    carbsTarget: 250,
    fatTarget: 70,
  ),
);

final _foodProposal = ProposalSummary(
  id: 'food-proposal-1',
  kind: ProposalKind.foodLog,
  status: 'pending',
  templateName: 'Food log',
  exerciseCount: 0,
  summary: 'One apple',
  createdAt: DateTime(2026, 8, 28),
);

final _decisionProposal = ProposalSummary(
  id: 'decision-1',
  kind: ProposalKind.foodLog,
  status: 'applied',
  templateName: 'Food log',
  exerciseCount: 0,
  summary: 'Logged breakfast',
  createdAt: DateTime.utc(2026, 8, 28, 1),
  decidedAt: DateTime.utc(2026, 8, 28, 1, 5),
  autoApplied: true,
  autoSource: 'first_party_webmcp',
);

final _foodProposalDetail = ProposalDetail(
  summary: _foodProposal,
  proposedExercises: const [],
  resolvedExercises: const [],
);

const _entryId = '11111111-2222-4333-8444-555555555555';

const _foodEditArguments = <String, Object?>{
  'payload': <String, Object?>{
    'targetEntryId': _entryId,
    'changes': <String, Object?>{'servingGrams': 200, 'calories': 330},
  },
};

const _foodDeleteArguments = <String, Object?>{
  'payload': <String, Object?>{'targetEntryId': _entryId},
};

final _revisionProposal = ProposalSummary(
  id: 'revision-proposal-1',
  kind: ProposalKind.foodLogEdit,
  status: 'pending',
  templateName: 'Food correction',
  exerciseCount: 0,
  summary: 'Correct one food entry',
  createdAt: DateTime(2026, 8, 28),
);

final _revisionProposalDetail = ProposalDetail(
  summary: _revisionProposal,
  proposedExercises: const [],
  resolvedExercises: const [],
);

FoodLogEntry _foodEntry({required String id, double? fiberGrams}) =>
    FoodLogEntry(
      id: id,
      date: DateTime(2026, 8, 28),
      loggedAt: DateTime.utc(2026, 8, 28, 4),
      servingGrams: 350,
      calories: 520,
      proteinGrams: 42,
      carbsGrams: 58,
      fatGrams: 14,
      fiberGrams: fiberGrams,
      sodiumMg: 640,
      foodName: 'Chicken rice',
    );

const _appleArguments = <String, Object?>{
  'payload': <String, Object?>{
    'date': '2026-08-28',
    'items': <Object?>[
      <String, Object?>{
        'foodName': 'Apple',
        'servingGrams': 182,
        'calories': 95,
        'proteinGrams': 0.5,
        'carbsGrams': 25,
        'fatGrams': 0.3,
        'fiberGrams': 4.4,
        'sugarGrams': 19,
        'sodiumMg': 2,
      },
    ],
    'note': 'One medium apple.',
  },
};

const _templatePlan = TemplateProposalPlan(
  name: 'Lower strength',
  description: 'A compact lower-body session.',
  exercises: [
    TemplateProposalExercise(
      exerciseId: 'Hack Squat',
      slug: 'hack-squat',
      sets: 4,
      repsTarget: 8,
      restTimerSeconds: 150,
      weightTarget: 120,
      rpeTarget: 8,
      notes: 'Controlled eccentric.',
    ),
  ],
);

const _templatePlanArguments = <String, Object?>{
  'name': 'Lower strength',
  'description': 'A compact lower-body session.',
  'exercises': <Object?>[
    <String, Object?>{
      'exerciseId': 'Hack Squat',
      'slug': 'hack-squat',
      'sets': 4,
      'repsTarget': 8,
      'restTimerSeconds': 150,
      'weightTarget': 120,
      'rpeTarget': 8,
      'notes': 'Controlled eccentric.',
    },
  ],
};

final _templateContext = TemplateWebMcpContext(
  templateId: 'template-a',
  updatedAt: DateTime.utc(2026, 8, 28),
  plan: _templatePlan,
  lossyOnEdit: false,
  syncedForEdit: true,
);

const _templateUpdatedAt = '2026-08-28T00:00:00.000Z';

final _templateProposal = ProposalSummary(
  id: 'template-proposal-1',
  kind: ProposalKind.templateEdit,
  status: 'pending',
  templateName: _templatePlan.name,
  exerciseCount: 1,
  targetTemplateId: 'template-a',
  createdAt: DateTime.utc(2026, 8, 28),
);

final _templateProposalDetail = ProposalDetail(
  summary: _templateProposal,
  proposedExercises: const [],
  resolvedExercises: const [],
);

HustlTodayContext _context() => const HustlTodayContext(
  status: 'ready',
  asOf: '2026-08-26T09:30:00.000+08:00',
  training: TrainingTodayContext(state: 'ready_to_start'),
  recovery: RecoveryTodayContext(state: 'no_data'),
  nutrition: NutritionTodayContext(
    state: 'empty',
    targetState: 'not_configured',
    calories: 0,
    proteinGrams: 0,
    carbsGrams: 0,
    fatGrams: 0,
  ),
  coach: CoachTodayContext(state: 'available', pendingProposalCount: 0),
  unavailableSections: [],
);
