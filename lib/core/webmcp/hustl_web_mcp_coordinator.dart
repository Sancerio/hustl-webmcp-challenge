import 'dart:async';

import '../../features/ai_proposals/domain/models/nutrition_proposal_result.dart';
import '../../features/ai_proposals/domain/models/food_log_proposal_result.dart';
import '../../features/ai_proposals/domain/models/food_log_revision_proposal_result.dart';
import '../../features/ai_proposals/domain/models/proposal_summary.dart';
import '../../features/ai_proposals/domain/models/template_proposal_result.dart';
import '../../features/ai_proposals/domain/repositories/food_log_revision_proposal_repository.dart';
import '../../features/ai_proposals/domain/repositories/proposals_repository.dart';
import '../../features/ai_proposals/services/proposal_count_service.dart';
import '../../features/nutrition_tracker/domain/models/food_log_entry.dart';
import '../../features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import '../../features/nutrition_tracker/presentation/diary_refresh_signal.dart';
import 'active_workout_web_mcp_controller.dart';
import 'coaching_trends_web_mcp_service.dart';
import 'today_context_service.dart';
import 'template_web_mcp_service.dart';
import 'web_mcp_access_gate.dart';
import 'web_mcp_models.dart';
import 'workout_history_web_mcp_service.dart';

typedef WebMcpNavigate = void Function(String route);
typedef WebMcpCurrentRoute = String Function();
typedef WebMcpTelemetry =
    void Function(String name, Map<String, Object?> properties);

class HustlWebMcpCoordinator {
  const HustlWebMcpCoordinator({
    required TodayContextService todayContextService,
    required WebMcpAccessGate accessGate,
    required ActiveWorkoutWebMcpController activeWorkoutController,
    required ProposalsRepository proposalsRepository,
    required FoodLogRevisionProposalRepository foodLogRevisionRepository,
    required ReadOnlyFoodLogRepository foodLogRepository,
    required TemplateWebMcpService templateService,
    required WorkoutHistoryWebMcpReader workoutHistoryService,
    required CoachingTrendsWebMcpService coachingTrendsService,
    ProposalCountService? proposalCountService,
    DiaryRefreshSignal? diaryRefreshSignal,
    WebMcpTelemetry? telemetry,
  }) : _todayContextService = todayContextService,
       _accessGate = accessGate,
       _activeWorkoutController = activeWorkoutController,
       _proposalsRepository = proposalsRepository,
       _foodLogRevisionRepository = foodLogRevisionRepository,
       _foodLogRepository = foodLogRepository,
       _templateService = templateService,
       _workoutHistoryService = workoutHistoryService,
       _coachingTrendsService = coachingTrendsService,
       _proposalCountService = proposalCountService,
       _diaryRefreshSignal = diaryRefreshSignal,
       _telemetry = telemetry;

  static const surfaceRoutes = <String, String>{
    'train': '/',
    'recovery': '/health',
    'nutrition': '/nutrition',
    'coach': '/proposals',
    'templates': '/templates',
  };

  final TodayContextService _todayContextService;
  final WebMcpAccessGate _accessGate;
  final ActiveWorkoutWebMcpController _activeWorkoutController;
  final ProposalsRepository _proposalsRepository;
  final FoodLogRevisionProposalRepository _foodLogRevisionRepository;
  final ReadOnlyFoodLogRepository _foodLogRepository;
  final TemplateWebMcpService _templateService;
  final WorkoutHistoryWebMcpReader _workoutHistoryService;
  final CoachingTrendsWebMcpService _coachingTrendsService;
  final ProposalCountService? _proposalCountService;
  final DiaryRefreshSignal? _diaryRefreshSignal;
  final WebMcpTelemetry? _telemetry;

  /// Returns the only routed surface whose registrations may keep their
  /// browser identity while route-bound handlers are refreshed.
  ///
  /// The Coach inbox and its valid detail routes intentionally publish one
  /// identical catalog. Other routes, including template details, remain
  /// exact-resource registration scopes even when their descriptors happen to
  /// match.
  String? stableRegistrationScopeForRoute(String route) =>
      route == '/proposals' || _proposalIdFromRoute(route) != null
      ? '/proposals'
      : null;

  List<WebMcpToolDefinition> toolsForRoute({
    required String route,
    required WebMcpCurrentRoute currentRoute,
    required WebMcpNavigate navigate,
  }) {
    final tools = <WebMcpToolDefinition>[
      WebMcpToolDefinition(
        name: 'hustl_get_today_context',
        title: 'Get today in Hustl',
        description:
            'Read a bounded summary of today across training, recovery, '
            'nutrition, and coaching. Missing data is reported explicitly.',
        inputSchema: _emptySchema,
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
        untrustedContentHint: true,
        handler: (_) => _getTodayContext(),
      ),
      WebMcpToolDefinition(
        name: 'hustl_open_surface',
        title: 'Open a Hustl surface',
        description:
            'Navigate the visible Hustl app to Train, Recover, Nutrition, '
            'Coach, or Templates. This changes navigation only and writes no '
            'product data.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'surface': {
              'type': 'string',
              'enum': ['train', 'recovery', 'nutrition', 'coach', 'templates'],
            },
          },
          'required': ['surface'],
          'additionalProperties': false,
        },
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
        handler: (arguments) => _openSurface(arguments, navigate),
      ),
    ];
    final catalogRoute = _proposalIdFromRoute(route) == null
        ? route
        : '/proposals';
    switch (catalogRoute) {
      case '/':
        tools
          ..add(
            _contextTool(
              name: 'hustl_get_training_context',
              title: 'Get training context',
              description:
                  'Read the bounded current training state shown by Hustl.',
              route: route,
              currentRoute: currentRoute,
              select: (context) => context['training'] as Map<String, Object?>,
            ),
          )
          ..add(_workoutHistoryTool(route, currentRoute))
          ..add(_exerciseHistoryTool(route, currentRoute));
        break;
      case '/health':
        tools.add(
          _contextTool(
            name: 'hustl_get_recovery_context',
            title: 'Get recovery context',
            description:
                'Read the bounded current recovery state shown by Hustl.',
            route: route,
            currentRoute: currentRoute,
            select: (context) => context['recovery'] as Map<String, Object?>,
          ),
        );
        break;
      case '/nutrition':
        tools
          ..add(
            _contextTool(
              name: 'hustl_get_nutrition_context',
              title: 'Get nutrition context',
              description:
                  'Read today\'s bounded nutrition totals and current targets.',
              route: route,
              currentRoute: currentRoute,
              select: (context) => context['nutrition'] as Map<String, Object?>,
            ),
          )
          ..add(_foodLogEntriesTool(route, currentRoute))
          ..add(_nutritionProposalTool(route, currentRoute))
          ..add(_foodLogProposalTool(route, currentRoute))
          ..add(_foodLogEditProposalTool(route, currentRoute))
          ..add(_foodLogDeleteProposalTool(route, currentRoute));
        break;
      case '/workout_session':
        tools
          ..add(
            WebMcpToolDefinition(
              name: 'hustl_get_active_workout',
              title: 'Get active workout',
              description:
                  'Read the visible active workout and bounded set values.',
              inputSchema: _emptySchema,
              readOnlyHint: true,
              destructiveHint: false,
              idempotentHint: true,
              openWorldHint: false,
              untrustedContentHint: true,
              handler: (_) => _routeAction(
                tool: 'hustl_get_active_workout',
                expectedRoute: route,
                currentRoute: currentRoute,
                action: () async => _activeWorkoutController.getActiveWorkout(),
              ),
            ),
          )
          ..add(
            WebMcpToolDefinition(
              name: 'hustl_stage_workout_adjustment',
              title: 'Stage a workout adjustment',
              description:
                  'Stage bounded changes to unfinished sets for visible human '
                  'review. This does not apply the changes.',
              inputSchema: _workoutAdjustmentSchema,
              readOnlyHint: false,
              destructiveHint: true,
              idempotentHint: false,
              openWorldHint: false,
              untrustedContentHint: true,
              handler: (arguments) => _routeAction(
                tool: 'hustl_stage_workout_adjustment',
                expectedRoute: route,
                currentRoute: currentRoute,
                action: () async => _activeWorkoutController.stage(arguments),
              ),
            ),
          );
        break;
      case '/proposals':
        tools
          ..add(_coachActivityTool(route, currentRoute))
          ..add(_coachingTrendsTool(route, currentRoute))
          ..add(_openProposalTool(route, currentRoute, navigate))
          ..add(_nutritionProposalTool(route, currentRoute))
          ..add(_foodLogProposalTool(route, currentRoute));
        break;
      case '/templates':
        tools.add(_templateProposalTool(route, currentRoute));
        break;
      default:
        final templateId = _templateIdFromRoute(route);
        if (templateId != null) {
          tools
            ..add(_templateContextTool(route, templateId, currentRoute))
            ..add(_templateEditProposalTool(route, templateId, currentRoute));
        }
    }
    return tools;
  }

  WebMcpToolDefinition _contextTool({
    required String name,
    required String title,
    required String description,
    required String route,
    required WebMcpCurrentRoute currentRoute,
    required Map<String, Object?> Function(Map<String, Object?> context) select,
  }) => WebMcpToolDefinition(
    name: name,
    title: title,
    description: description,
    inputSchema: _emptySchema,
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    untrustedContentHint: true,
    handler: (_) => _routeAction(
      tool: name,
      expectedRoute: route,
      currentRoute: currentRoute,
      action: () async {
        final context = (await _todayContextService.load()).toJson();
        return {
          'status': context['status'],
          'asOf': context['asOf'],
          ...select(context),
        };
      },
    ),
  );

  WebMcpToolDefinition _coachActivityTool(
    String route,
    WebMcpCurrentRoute currentRoute,
  ) => WebMcpToolDefinition(
    name: 'hustl_get_coach_activity',
    title: 'Get Coach activity',
    description:
        'Read up to 20 pending proposals and 10 recent decisions shown in '
        'Hustl Coach.',
    inputSchema: _emptySchema,
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    untrustedContentHint: true,
    handler: (_) => _routeAction(
      tool: 'hustl_get_coach_activity',
      expectedRoute: route,
      currentRoute: currentRoute,
      action: () async {
        final proposals = (await _proposalsRepository.listPending(
          limit: 20,
        )).take(20).toList(growable: false);
        var recentDecisions = const <ProposalSummary>[];
        var recentDecisionsState = 'ready';
        try {
          recentDecisions = (await _proposalsRepository.listDecided(
            statuses: const ['applied', 'reverted', 'rejected'],
            limit: 10,
          )).take(10).toList(growable: false);
        } catch (_) {
          recentDecisionsState = 'unavailable';
        }
        return {
          'status': 'ready',
          'pendingCount': proposals.length,
          'proposals': proposals.map(_proposalJson).toList(growable: false),
          'recentDecisionsState': recentDecisionsState,
          'recentDecisionCount': recentDecisions.length,
          'recentDecisions': recentDecisions
              .map(_proposalDecisionJson)
              .toList(growable: false),
        };
      },
    ),
  );

  WebMcpToolDefinition _workoutHistoryTool(
    String route,
    WebMcpCurrentRoute currentRoute,
  ) => WebMcpToolDefinition(
    name: 'hustl_get_workout_history',
    title: 'Get recent workout history',
    description:
        'Read a bounded page of completed workout summaries. Returns at most '
        '20 rows and an opaque cursor for deliberately requesting older pages; '
        'it does not return notes or raw exercise sets.',
    inputSchema: _workoutHistorySchema,
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    untrustedContentHint: true,
    handler: (arguments) => _routeAction(
      tool: 'hustl_get_workout_history',
      expectedRoute: route,
      currentRoute: currentRoute,
      action: () async {
        final input = _parseWorkoutHistoryInput(arguments);
        if (input == null) {
          return const {
            'status': 'invalid_request',
            'code': 'invalid_arguments',
          };
        }
        return _workoutHistoryService.loadWorkoutHistory(
          limit: input.limit,
          cursor: input.cursor,
        );
      },
    ),
  );

  WebMcpToolDefinition _coachingTrendsTool(
    String route,
    WebMcpCurrentRoute currentRoute,
  ) => WebMcpToolDefinition(
    name: 'hustl_get_coaching_trends',
    title: 'Compare coaching trends',
    description:
        'Compare bounded training, recovery, and nutrition aggregates for the '
        'selected trailing window against the immediately preceding equal '
        'window. Returns coverage and averages, never raw daily timelines, '
        'meals, workout notes, exercises, or sets.',
    inputSchema: _coachingTrendsSchema,
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    untrustedContentHint: true,
    handler: (arguments) => _routeAction(
      tool: 'hustl_get_coaching_trends',
      expectedRoute: route,
      currentRoute: currentRoute,
      action: () async {
        final windowDays = _parseCoachingTrendsInput(arguments);
        if (windowDays == null) {
          return const {
            'status': 'invalid_request',
            'code': 'invalid_arguments',
          };
        }
        return _coachingTrendsService.load(windowDays: windowDays);
      },
    ),
  );

  WebMcpToolDefinition _exerciseHistoryTool(
    String route,
    WebMcpCurrentRoute currentRoute,
  ) => WebMcpToolDefinition(
    name: 'hustl_get_exercise_history',
    title: 'Get exercise history',
    description:
        'Read up to 20 exercises ranked by the user\'s completed training '
        'frequency and recency, with nullable typical sets and strength or '
        'cardio prescription. This aggregate contains no raw set timeline.',
    inputSchema: _exerciseHistorySchema,
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    untrustedContentHint: true,
    handler: (arguments) => _routeAction(
      tool: 'hustl_get_exercise_history',
      expectedRoute: route,
      currentRoute: currentRoute,
      action: () async {
        final input = _parseExerciseHistoryInput(arguments);
        if (input == null) {
          return const {
            'status': 'invalid_request',
            'code': 'invalid_arguments',
          };
        }
        return _workoutHistoryService.loadExerciseHistory(
          limit: input.limit,
          sinceDays: input.sinceDays,
        );
      },
    ),
  );

  WebMcpToolDefinition _openProposalTool(
    String route,
    WebMcpCurrentRoute currentRoute,
    WebMcpNavigate navigate,
  ) => WebMcpToolDefinition(
    name: 'hustl_open_proposal',
    title: 'Open a pending proposal',
    description:
        'Open one pending proposal returned by the current Hustl Coach inbox.',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'proposalId': {'type': 'string', 'minLength': 1, 'maxLength': 128},
      },
      'required': ['proposalId'],
      'additionalProperties': false,
    },
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    untrustedContentHint: true,
    handler: (arguments) => _routeAction(
      tool: 'hustl_open_proposal',
      expectedRoute: route,
      currentRoute: currentRoute,
      allowRouteChange: true,
      action: () async {
        if (arguments.length != 1 || arguments['proposalId'] is! String) {
          return const {
            'status': 'invalid_request',
            'code': 'invalid_arguments',
          };
        }
        final id = (arguments['proposalId']! as String).trim();
        if (id.isEmpty || id.length > 128) {
          return const {
            'status': 'invalid_request',
            'code': 'invalid_proposal_id',
          };
        }
        final pending = await _proposalsRepository.listPending(limit: 50);
        if (!pending.any((proposal) => proposal.id == id)) {
          return const {
            'status': 'invalid_request',
            'code': 'proposal_not_pending',
          };
        }
        if (currentRoute() != route) {
          return const {'status': 'unavailable', 'code': 'stale_route'};
        }
        navigate('/proposals/${Uri.encodeComponent(id)}');
        return {'status': 'opened', 'proposalId': id};
      },
    ),
  );

  WebMcpToolDefinition _foodLogEntriesTool(
    String route,
    WebMcpCurrentRoute currentRoute,
  ) => WebMcpToolDefinition(
    name: 'hustl_get_food_log_entries',
    title: 'Get food log entries',
    description:
        'Read up to 50 individual diary entries for one explicit user local '
        'date. Only use an entry id whose revisable field is true when '
        'proposing a correction or removal; queued offline entries are '
        'readable but cannot be revised until they sync.',
    inputSchema: _foodLogEntriesSchema,
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    untrustedContentHint: true,
    handler: (arguments) => _routeAction(
      tool: 'hustl_get_food_log_entries',
      expectedRoute: route,
      currentRoute: currentRoute,
      action: () async {
        if (arguments.length != 1 ||
            arguments['date'] is! String ||
            !_isRealDate(arguments['date']! as String)) {
          return const {
            'status': 'invalid_request',
            'code': 'invalid_arguments',
          };
        }
        final date = arguments['date']! as String;
        final entries = await _foodLogRepository.getLogsForDateReadOnly(
          DateTime.parse(date),
        );
        final bounded = entries.take(50).toList(growable: false);
        return {
          'status': 'ready',
          'date': date,
          'entryCount': bounded.length,
          'truncated': entries.length > bounded.length,
          'entries': bounded.map(_foodLogEntryJson).toList(growable: false),
        };
      },
    ),
  );

  WebMcpToolDefinition _nutritionProposalTool(
    String route,
    WebMcpCurrentRoute currentRoute,
  ) => WebMcpToolDefinition(
    name: 'hustl_propose_nutrition_targets',
    title: 'Propose nutrition targets',
    description:
        'Create a pending nutrition-target proposal for visible human review. '
        'This does not change current targets.',
    inputSchema: _nutritionProposalSchema,
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    untrustedContentHint: true,
    handler: (arguments) => _routeAction(
      tool: 'hustl_propose_nutrition_targets',
      expectedRoute: route,
      currentRoute: currentRoute,
      action: () async {
        final input = _parseNutritionInput(arguments);
        if (input == null) {
          return const {
            'status': 'invalid_request',
            'code': 'invalid_arguments',
          };
        }
        final NutritionProposalResult result;
        try {
          result = await _proposalsRepository.proposeNutritionTargets(input);
        } on ProposalUnavailable catch (error) {
          return _proposalUnavailableResponse(error);
        }
        _refreshProposalBadge();
        return {
          'status': result.status,
          'proposalId': result.proposalId,
          'requiresHumanReview': true,
          'message': 'Nothing changed yet. Review this proposal in Hustl.',
        };
      },
    ),
  );

  WebMcpToolDefinition _foodLogProposalTool(
    String route,
    WebMcpCurrentRoute currentRoute,
  ) => WebMcpToolDefinition(
    name: 'hustl_propose_food_log',
    title: 'Propose a food log',
    description:
        'Create a food-log proposal using the explicit user local date. It '
        'waits for human review unless the user enabled Hustl Web auto-log in '
        'settings; that account choice may apply a fresh proposal immediately.',
    inputSchema: _foodLogProposalSchema,
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    untrustedContentHint: true,
    handler: (arguments) => _routeAction(
      tool: 'hustl_propose_food_log',
      expectedRoute: route,
      currentRoute: currentRoute,
      action: () async {
        final input = _parseFoodLogInput(arguments);
        if (input == null) {
          return const {
            'status': 'invalid_request',
            'code': 'invalid_arguments',
          };
        }
        final FoodLogProposalResult result;
        try {
          result = await _proposalsRepository.proposeFoodLog(input);
        } on ProposalUnavailable catch (error) {
          return _proposalUnavailableResponse(error);
        }
        _refreshProposalBadge();
        final applied = result.status == 'applied';
        if (applied) _diaryRefreshSignal?.ping();
        return {
          'status': result.status,
          'proposalId': result.proposalId,
          'requiresHumanReview': !applied,
          'message':
              result.humanMessage ??
              (applied
                  ? 'This food log is applied. Review it in AI Activity, where Undo remains available.'
                  : 'Nothing is logged yet. Review this proposal in Hustl.'),
        };
      },
    ),
  );

  WebMcpToolDefinition _foodLogEditProposalTool(
    String route,
    WebMcpCurrentRoute currentRoute,
  ) => WebMcpToolDefinition(
    name: 'hustl_propose_food_log_edit',
    title: 'Propose a food log correction',
    description:
        'Correct one existing entry returned by hustl_get_food_log_entries. '
        'Pass only changed fields. This always waits for visible review and '
        'never uses Web auto-log.',
    inputSchema: _foodLogEditProposalSchema,
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    untrustedContentHint: true,
    handler: (arguments) => _routeAction(
      tool: 'hustl_propose_food_log_edit',
      expectedRoute: route,
      currentRoute: currentRoute,
      action: () async {
        final input = _parseFoodLogEditInput(arguments);
        if (input == null) {
          return const {
            'status': 'invalid_request',
            'code': 'invalid_arguments',
          };
        }
        final FoodLogRevisionProposalResult result;
        try {
          result = await _foodLogRevisionRepository.proposeFoodLogEdit(input);
        } on FoodLogRevisionTargetUnavailable {
          return const {
            'status': 'unavailable',
            'code': 'food_entry_not_found',
          };
        } on ProposalUnavailable catch (error) {
          return _proposalUnavailableResponse(error);
        }
        _refreshProposalBadge();
        final applied = result.status == 'applied';
        return {
          'status': result.status,
          'proposalId': result.proposalId,
          'requiresHumanReview': !applied,
          'message':
              result.humanMessage ??
              (applied
                  ? 'This correction was already applied. Undo remains available in AI Activity.'
                  : 'Nothing changed yet. Review this correction in Hustl.'),
        };
      },
    ),
  );

  WebMcpToolDefinition _foodLogDeleteProposalTool(
    String route,
    WebMcpCurrentRoute currentRoute,
  ) => WebMcpToolDefinition(
    name: 'hustl_propose_food_log_delete',
    title: 'Propose removing a food log entry',
    description:
        'Remove one existing entry returned by hustl_get_food_log_entries. '
        'This always waits for visible review, never uses Web auto-log, and '
        'remains undoable after approval.',
    inputSchema: _foodLogDeleteProposalSchema,
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    untrustedContentHint: true,
    handler: (arguments) => _routeAction(
      tool: 'hustl_propose_food_log_delete',
      expectedRoute: route,
      currentRoute: currentRoute,
      action: () async {
        final input = _parseFoodLogDeleteInput(arguments);
        if (input == null) {
          return const {
            'status': 'invalid_request',
            'code': 'invalid_arguments',
          };
        }
        final FoodLogRevisionProposalResult result;
        try {
          result = await _foodLogRevisionRepository.proposeFoodLogDelete(input);
        } on FoodLogRevisionTargetUnavailable {
          return const {
            'status': 'unavailable',
            'code': 'food_entry_not_found',
          };
        } on ProposalUnavailable catch (error) {
          return _proposalUnavailableResponse(error);
        }
        _refreshProposalBadge();
        final applied = result.status == 'applied';
        return {
          'status': result.status,
          'proposalId': result.proposalId,
          'requiresHumanReview': !applied,
          'message':
              result.humanMessage ??
              (applied
                  ? 'This removal was already applied. Undo remains available in AI Activity.'
                  : 'Nothing changed yet. Review this removal in Hustl.'),
        };
      },
    ),
  );

  WebMcpToolDefinition _templateProposalTool(
    String route,
    WebMcpCurrentRoute currentRoute,
  ) => WebMcpToolDefinition(
    name: 'hustl_propose_template',
    title: 'Propose a workout template',
    description:
        'Create a pending workout-template proposal for visible human review. '
        'This invocation never creates a live template.',
    inputSchema: _templateCreateProposalSchema,
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    untrustedContentHint: true,
    handler: (arguments) => _routeAction(
      tool: 'hustl_propose_template',
      expectedRoute: route,
      currentRoute: currentRoute,
      action: () async {
        final plan = _parseTemplatePlan(arguments);
        if (plan == null) {
          return const {
            'status': 'invalid_request',
            'code': 'invalid_arguments',
          };
        }
        final TemplateProposalResult result;
        try {
          result = await _proposalsRepository.proposeTemplate(plan);
        } on ProposalUnavailable catch (error) {
          return _proposalUnavailableResponse(error);
        }
        _refreshProposalBadge();
        return {
          'status': result.status,
          'proposalId': result.proposalId,
          'requiresHumanReview': true,
          'message':
              'Nothing changed yet. Review this workout template in Hustl.',
        };
      },
    ),
  );

  WebMcpToolDefinition _templateContextTool(
    String route,
    String templateId,
    WebMcpCurrentRoute currentRoute,
  ) => WebMcpToolDefinition(
    name: 'hustl_get_template_context',
    title: 'Get visible workout template',
    description:
        'Read the visible template as bounded, complete input for a proposed '
        'edit. Check lossyOnEdit before proposing changes.',
    inputSchema: _emptySchema,
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    untrustedContentHint: true,
    handler: (_) => _routeAction(
      tool: 'hustl_get_template_context',
      expectedRoute: route,
      currentRoute: currentRoute,
      action: () async {
        final context = await _templateService.load(templateId);
        if (context == null) {
          return const {'status': 'unavailable', 'code': 'template_not_found'};
        }
        return context.toJson();
      },
    ),
  );

  WebMcpToolDefinition _templateEditProposalTool(
    String route,
    String templateId,
    WebMcpCurrentRoute currentRoute,
  ) => WebMcpToolDefinition(
    name: 'hustl_propose_template_edit',
    title: 'Propose changes to this template',
    description:
        'Draft a full replacement for the visible workout template. Read it '
        'first and preserve every exercise not being changed. Nothing is '
        'applied until human review in Hustl.',
    inputSchema: _templateEditProposalSchema,
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    untrustedContentHint: true,
    handler: (arguments) => _routeAction(
      tool: 'hustl_propose_template_edit',
      expectedRoute: route,
      currentRoute: currentRoute,
      action: () async {
        final generation = _accessGate.generation;
        const allowed = {'plan', 'baseUpdatedAt', 'acknowledgeNormalization'};
        final baseUpdatedAtRaw = arguments['baseUpdatedAt'];
        final baseUpdatedAt = baseUpdatedAtRaw is String
            ? DateTime.tryParse(baseUpdatedAtRaw)
            : null;
        if (arguments.keys.any((key) => !allowed.contains(key)) ||
            baseUpdatedAt == null ||
            (arguments['acknowledgeNormalization'] != null &&
                arguments['acknowledgeNormalization'] is! bool)) {
          return const {
            'status': 'invalid_request',
            'code': 'invalid_arguments',
          };
        }
        final plan = _parseTemplatePlan({'plan': arguments['plan']});
        if (plan == null) {
          return const {
            'status': 'invalid_request',
            'code': 'invalid_arguments',
          };
        }
        final context = await _templateService.load(templateId);
        if (!_accessGate.isReadyFor(generation)) {
          return const {'status': 'unavailable', 'code': 'auth_transition'};
        }
        if (currentRoute() != route) {
          return const {'status': 'unavailable', 'code': 'stale_route'};
        }
        if (context == null) {
          return const {'status': 'unavailable', 'code': 'template_not_found'};
        }
        if (!context.syncedForEdit) {
          return const {'status': 'unavailable', 'code': 'template_not_synced'};
        }
        if (!context.editable) {
          return const {
            'status': 'unavailable',
            'code': 'template_not_editable',
          };
        }
        if (!baseUpdatedAt.isAtSameMomentAs(context.updatedAt)) {
          return const {'status': 'conflict', 'code': 'template_changed'};
        }
        if (context.lossyOnEdit &&
            arguments['acknowledgeNormalization'] != true) {
          return const {
            'status': 'confirmation_required',
            'code': 'lossy_template_edit',
            'requiresAcknowledgement': true,
            'warning': templateNormalizationWarning,
          };
        }
        final TemplateProposalResult result;
        try {
          result = await _proposalsRepository.proposeTemplateEdit(
            templateId,
            baseUpdatedAt,
            plan,
          );
        } on TemplateProposalConflict {
          return const {'status': 'conflict', 'code': 'template_changed'};
        } on ProposalUnavailable catch (error) {
          return _proposalUnavailableResponse(error);
        }
        _refreshProposalBadge();
        return {
          'status': result.status,
          'proposalId': result.proposalId,
          'targetTemplateId': templateId,
          'requiresHumanReview': true,
          'message': 'Nothing changed yet. Review this template edit in Hustl.',
        };
      },
    ),
  );

  void _refreshProposalBadge() {
    final refresh = _proposalCountService?.refreshNow();
    if (refresh == null) return;
    unawaited(
      refresh.catchError((_) {
        // Badge refresh is best-effort; the proposal already exists.
      }),
    );
  }

  Map<String, Object?> _proposalUnavailableResponse(
    ProposalUnavailable error,
  ) => {
    'status': 'unavailable',
    'code': error.code,
    'message': error.code == 'proposal_rate_limited'
        ? 'Proposal creation is temporarily rate limited. Try again shortly.'
        : 'Too many proposals are waiting for review. Review or dismiss one in Hustl before trying again.',
  };

  Future<Map<String, Object?>> _routeAction({
    required String tool,
    required String expectedRoute,
    required WebMcpCurrentRoute currentRoute,
    required Future<Map<String, Object?>> Function() action,
    bool allowRouteChange = false,
  }) async {
    if (!_accessGate.ready.value) {
      _log('webmcp_tool_completed', tool: tool, status: 'unavailable');
      return const {'status': 'unavailable', 'code': 'auth_transition'};
    }
    if (currentRoute() != expectedRoute) {
      _log('webmcp_tool_completed', tool: tool, status: 'unavailable');
      return const {'status': 'unavailable', 'code': 'stale_route'};
    }
    final generation = _accessGate.generation;
    _log('webmcp_tool_invoked', tool: tool, status: 'started');
    try {
      final result = await action();
      if (!_accessGate.isReadyFor(generation)) {
        _log('webmcp_tool_completed', tool: tool, status: 'unavailable');
        return const {'status': 'unavailable', 'code': 'auth_transition'};
      }
      final actionOpenedRoute =
          allowRouteChange && result['status'] == 'opened';
      if (!actionOpenedRoute && currentRoute() != expectedRoute) {
        _log('webmcp_tool_completed', tool: tool, status: 'unavailable');
        return const {'status': 'unavailable', 'code': 'stale_route'};
      }
      final status = result['status'] as String? ?? 'ready';
      _log('webmcp_tool_completed', tool: tool, status: status);
      return result;
    } catch (_) {
      if (!_accessGate.isReadyFor(generation)) {
        _log('webmcp_tool_completed', tool: tool, status: 'unavailable');
        return const {'status': 'unavailable', 'code': 'auth_transition'};
      }
      if (currentRoute() != expectedRoute) {
        _log('webmcp_tool_completed', tool: tool, status: 'unavailable');
        return const {'status': 'unavailable', 'code': 'stale_route'};
      }
      _log('webmcp_tool_completed', tool: tool, status: 'error');
      return const {'status': 'error', 'code': 'operation_unavailable'};
    }
  }

  Future<Map<String, Object?>> _getTodayContext() async {
    const tool = 'hustl_get_today_context';
    if (!_accessGate.ready.value) {
      _log('webmcp_tool_completed', tool: tool, status: 'unavailable');
      return const {'status': 'unavailable', 'code': 'auth_transition'};
    }
    final gateGeneration = _accessGate.generation;
    _log('webmcp_tool_invoked', tool: tool, status: 'started');
    try {
      final result = (await _todayContextService.load()).toJson();
      if (!_accessGate.isReadyFor(gateGeneration)) {
        _log('webmcp_tool_completed', tool: tool, status: 'unavailable');
        return const {'status': 'unavailable', 'code': 'auth_transition'};
      }
      _log(
        'webmcp_tool_completed',
        tool: tool,
        status: result['status'] as String? ?? 'ready',
      );
      return result;
    } catch (_) {
      if (!_accessGate.isReadyFor(gateGeneration)) {
        _log('webmcp_tool_completed', tool: tool, status: 'unavailable');
        return const {'status': 'unavailable', 'code': 'auth_transition'};
      }
      _log('webmcp_tool_completed', tool: tool, status: 'error');
      return const {'status': 'error', 'code': 'context_unavailable'};
    }
  }

  Future<Map<String, Object?>> _openSurface(
    Map<String, Object?> arguments,
    WebMcpNavigate navigate,
  ) async {
    const tool = 'hustl_open_surface';
    if (!_accessGate.ready.value) {
      _log('webmcp_tool_completed', tool: tool, status: 'unavailable');
      return const {'status': 'unavailable', 'code': 'auth_transition'};
    }
    _log('webmcp_tool_invoked', tool: tool, status: 'started');
    final surface = arguments['surface'];
    if (arguments.length != 1 || surface is! String) {
      _log('webmcp_tool_completed', tool: tool, status: 'invalid_request');
      return const {
        'status': 'invalid_request',
        'code': 'invalid_arguments',
        'allowedSurfaces': [
          'train',
          'recovery',
          'nutrition',
          'coach',
          'templates',
        ],
      };
    }
    final route = surfaceRoutes[surface];
    if (route == null) {
      _log('webmcp_tool_completed', tool: tool, status: 'invalid_request');
      return const {
        'status': 'invalid_request',
        'code': 'unknown_surface',
        'allowedSurfaces': [
          'train',
          'recovery',
          'nutrition',
          'coach',
          'templates',
        ],
      };
    }
    try {
      navigate(route);
      _log('webmcp_tool_completed', tool: tool, status: 'opened');
      return {'status': 'opened', 'surface': surface};
    } catch (_) {
      _log('webmcp_tool_completed', tool: tool, status: 'unavailable');
      return const {'status': 'unavailable', 'code': 'navigation_failed'};
    }
  }

  static Map<String, Object?> _proposalJson(ProposalSummary proposal) => {
    'id': proposal.id,
    'kind': proposal.kind.name,
    'title': proposal.templateName,
    'summary': proposal.summary,
    'createdAt': proposal.createdAt.toIso8601String(),
    'expiresAt': proposal.expiresAt?.toIso8601String(),
    'conflictReason': proposal.conflictReason,
  };

  static Map<String, Object?> _proposalDecisionJson(ProposalSummary proposal) =>
      {
        ..._proposalJson(proposal),
        'status': proposal.status,
        'decidedAt': proposal.decidedAt?.toIso8601String(),
        'autoApplied': proposal.autoApplied,
      };

  static Map<String, Object?> _foodLogEntryJson(FoodLogEntry entry) => {
    'id': entry.id,
    'revisable': _uuidPattern.hasMatch(entry.id),
    'date': entry.date.toIso8601String().substring(0, 10),
    'consumedAt': entry.consumedAt.toUtc().toIso8601String(),
    'foodName': entry.foodName ?? entry.food?.name,
    'servingGrams': entry.servingGrams,
    'calories': entry.calories,
    'proteinGrams': entry.proteinGrams,
    'carbsGrams': entry.carbsGrams,
    'fatGrams': entry.fatGrams,
    'fiberGrams': entry.fiberGrams,
    'sugarGrams': entry.sugarGrams,
    'sodiumMg': entry.sodiumMg,
    'source': entry.source,
  };

  static NutritionProposalInput? _parseNutritionInput(
    Map<String, Object?> arguments,
  ) {
    const allowed = {
      'caloriesTarget',
      'proteinTarget',
      'carbsTarget',
      'fatTarget',
      'rationale',
    };
    if (arguments.keys.any((key) => !allowed.contains(key))) return null;
    final calories = _intInRange(arguments['caloriesTarget'], 800, 6000);
    final protein = _doubleInRange(arguments['proteinTarget'], 0, 500);
    final carbs = _doubleInRange(arguments['carbsTarget'], 0, 1500);
    final fat = _doubleInRange(arguments['fatTarget'], 0, 400);
    final rationale = arguments['rationale'];
    if (calories == null || protein == null || carbs == null || fat == null) {
      return null;
    }
    if (rationale != null &&
        (rationale is! String ||
            rationale.trim().isEmpty ||
            rationale.length > 500)) {
      return null;
    }
    return NutritionProposalInput(
      caloriesTarget: calories,
      proteinTarget: protein,
      carbsTarget: carbs,
      fatTarget: fat,
      rationale: rationale is String ? rationale.trim() : null,
    );
  }

  static FoodLogProposalInput? _parseFoodLogInput(
    Map<String, Object?> arguments,
  ) {
    if (arguments.length != 1 || arguments['payload'] is! Map) return null;
    final rawPayload = Map<Object?, Object?>.from(arguments['payload']! as Map);
    const allowedPayload = {'date', 'items', 'note'};
    if (rawPayload.keys.any(
      (key) => key is! String || !allowedPayload.contains(key),
    )) {
      return null;
    }
    final date = rawPayload['date'];
    final rawItems = rawPayload['items'];
    final note = rawPayload['note'];
    if (date is! String || !_isRealDate(date)) return null;
    if (rawItems is! List || rawItems.isEmpty || rawItems.length > 20) {
      return null;
    }
    if (note != null &&
        (note is! String || note.trim().isEmpty || note.length > 500)) {
      return null;
    }

    final items = <FoodLogProposalItem>[];
    const allowedItem = {
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
    for (final rawItem in rawItems) {
      if (rawItem is! Map) return null;
      final item = Map<Object?, Object?>.from(rawItem);
      if (item.keys.any(
        (key) => key is! String || !allowedItem.contains(key),
      )) {
        return null;
      }
      final foodName = item['foodName'];
      final servingGrams = _doubleInRange(item['servingGrams'], 0, 5000);
      final calories = _doubleInRange(item['calories'], 0, 5000);
      final protein = _doubleInRange(item['proteinGrams'], 0, 1000);
      final carbs = _doubleInRange(item['carbsGrams'], 0, 1000);
      final fat = _doubleInRange(item['fatGrams'], 0, 1000);
      if (foodName is! String ||
          foodName.trim().isEmpty ||
          foodName.length > 200 ||
          servingGrams == null ||
          servingGrams <= 0 ||
          calories == null ||
          protein == null ||
          carbs == null ||
          fat == null) {
        return null;
      }
      final fiber = _optionalDoubleInRange(item['fiberGrams'], 0, 1000);
      final sugar = _optionalDoubleInRange(item['sugarGrams'], 0, 1000);
      final sodium = _optionalDoubleInRange(item['sodiumMg'], 0, 100000);
      if (fiber == _invalidOptionalNumber ||
          sugar == _invalidOptionalNumber ||
          sodium == _invalidOptionalNumber) {
        return null;
      }
      items.add(
        FoodLogProposalItem(
          foodName: foodName.trim(),
          servingGrams: servingGrams,
          calories: calories,
          proteinGrams: protein,
          carbsGrams: carbs,
          fatGrams: fat,
          fiberGrams: fiber as double?,
          sugarGrams: sugar as double?,
          sodiumMg: sodium as double?,
        ),
      );
    }
    return FoodLogProposalInput(
      date: date,
      items: List.unmodifiable(items),
      note: note is String ? note.trim() : null,
    );
  }

  static FoodLogEditProposalInput? _parseFoodLogEditInput(
    Map<String, Object?> arguments,
  ) {
    if (arguments.length != 1 || arguments['payload'] is! Map) return null;
    final payload = Map<Object?, Object?>.from(arguments['payload']! as Map);
    if (payload.length != 2 ||
        payload.keys.any(
          (key) =>
              key is! String || !{'targetEntryId', 'changes'}.contains(key),
        )) {
      return null;
    }
    final targetEntryId = payload['targetEntryId'];
    final rawChanges = payload['changes'];
    if (targetEntryId is! String ||
        !_uuidPattern.hasMatch(targetEntryId.trim()) ||
        rawChanges is! Map) {
      return null;
    }
    final changes = Map<Object?, Object?>.from(rawChanges);
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
        changes.keys.any((key) => key is! String || !allowed.contains(key))) {
      return null;
    }

    final foodName = changes['foodName'];
    if (changes.containsKey('foodName') &&
        (foodName is! String ||
            foodName.trim().isEmpty ||
            foodName.length > 200)) {
      return null;
    }
    double? number(String key, double min, double max) {
      if (!changes.containsKey(key)) return null;
      return _doubleInRange(changes[key], min, max);
    }

    final servingGrams = number('servingGrams', 0, 5000);
    final calories = number('calories', 0, 5000);
    final protein = number('proteinGrams', 0, 1000);
    final carbs = number('carbsGrams', 0, 1000);
    final fat = number('fatGrams', 0, 1000);
    final fiber = number('fiberGrams', 0, 1000);
    final sugar = number('sugarGrams', 0, 1000);
    final sodium = number('sodiumMg', 0, 100000);
    if ((changes.containsKey('servingGrams') &&
            (servingGrams == null || servingGrams <= 0)) ||
        (changes.containsKey('calories') && calories == null) ||
        (changes.containsKey('proteinGrams') && protein == null) ||
        (changes.containsKey('carbsGrams') && carbs == null) ||
        (changes.containsKey('fatGrams') && fat == null) ||
        (changes.containsKey('fiberGrams') && fiber == null) ||
        (changes.containsKey('sugarGrams') && sugar == null) ||
        (changes.containsKey('sodiumMg') && sodium == null)) {
      return null;
    }
    return FoodLogEditProposalInput(
      targetEntryId: targetEntryId.trim(),
      changes: FoodLogRevisionChanges(
        foodName: foodName is String ? foodName.trim() : null,
        servingGrams: servingGrams,
        calories: calories,
        proteinGrams: protein,
        carbsGrams: carbs,
        fatGrams: fat,
        fiberGrams: fiber,
        sugarGrams: sugar,
        sodiumMg: sodium,
      ),
    );
  }

  static FoodLogDeleteProposalInput? _parseFoodLogDeleteInput(
    Map<String, Object?> arguments,
  ) {
    if (arguments.length != 1 || arguments['payload'] is! Map) return null;
    final payload = Map<Object?, Object?>.from(arguments['payload']! as Map);
    if (payload.length != 1 || payload['targetEntryId'] is! String) {
      return null;
    }
    final targetEntryId = (payload['targetEntryId']! as String).trim();
    if (!_uuidPattern.hasMatch(targetEntryId)) return null;
    return FoodLogDeleteProposalInput(targetEntryId: targetEntryId);
  }

  static ({int limit, String? cursor})? _parseWorkoutHistoryInput(
    Map<String, Object?> arguments,
  ) {
    if (arguments.keys.any((key) => !{'limit', 'cursor'}.contains(key))) {
      return null;
    }
    final limit = arguments.containsKey('limit')
        ? _intInRange(arguments['limit'], 1, 20)
        : 10;
    final cursor = arguments['cursor'];
    if (limit == null ||
        (cursor != null &&
            (cursor is! String ||
                cursor.trim().isEmpty ||
                cursor.length > 1024))) {
      return null;
    }
    return (limit: limit, cursor: cursor is String ? cursor.trim() : null);
  }

  static ({int limit, int sinceDays})? _parseExerciseHistoryInput(
    Map<String, Object?> arguments,
  ) {
    if (arguments.keys.any((key) => !{'limit', 'sinceDays'}.contains(key))) {
      return null;
    }
    final limit = arguments.containsKey('limit')
        ? _intInRange(arguments['limit'], 1, 20)
        : 10;
    final sinceDays = arguments.containsKey('sinceDays')
        ? _intInRange(arguments['sinceDays'], 1, 3650)
        : 365;
    if (limit == null || sinceDays == null) return null;
    return (limit: limit, sinceDays: sinceDays);
  }

  static int? _parseCoachingTrendsInput(Map<String, Object?> arguments) {
    if (arguments.keys.any((key) => key != 'windowDays')) return null;
    final windowDays = arguments.containsKey('windowDays')
        ? _intInRange(arguments['windowDays'], 7, 90)
        : 30;
    return windowDays == 7 || windowDays == 30 || windowDays == 90
        ? windowDays
        : null;
  }

  static TemplateProposalPlan? _parseTemplatePlan(
    Map<String, Object?> arguments,
  ) {
    if (arguments.length != 1 || arguments['plan'] is! Map) return null;
    final rawPlan = Map<Object?, Object?>.from(arguments['plan']! as Map);
    const allowedPlan = {'name', 'description', 'exercises'};
    if (rawPlan.keys.any(
      (key) => key is! String || !allowedPlan.contains(key),
    )) {
      return null;
    }
    final name = rawPlan['name'];
    final description = rawPlan['description'];
    final rawExercises = rawPlan['exercises'];
    if (name is! String ||
        name.trim().isEmpty ||
        name.length > 120 ||
        (description != null &&
            (description is! String ||
                description.trim().isEmpty ||
                description.length > 2000)) ||
        rawExercises is! List ||
        rawExercises.isEmpty ||
        rawExercises.length > 30) {
      return null;
    }

    const allowedExercise = {
      'exerciseId',
      'slug',
      'sets',
      'repsTarget',
      'restTimerSeconds',
      'weightTarget',
      'rpeTarget',
      'notes',
    };
    final exercises = <TemplateProposalExercise>[];
    for (final rawExercise in rawExercises) {
      if (rawExercise is! Map) return null;
      final exercise = Map<Object?, Object?>.from(rawExercise);
      if (exercise.keys.any(
        (key) => key is! String || !allowedExercise.contains(key),
      )) {
        return null;
      }
      final exerciseId = exercise['exerciseId'];
      final slug = exercise['slug'];
      final sets = _intInRange(exercise['sets'], 1, 20);
      final reps = exercise['repsTarget'] == null
          ? null
          : _intInRange(exercise['repsTarget'], 1, 100);
      final rest = _intInRange(exercise['restTimerSeconds'], 0, 600);
      final weight = exercise['weightTarget'] == null
          ? null
          : _doubleInRange(exercise['weightTarget'], 0, 2000);
      final rpe = exercise['rpeTarget'] == null
          ? null
          : _intInRange(exercise['rpeTarget'], 1, 10);
      final notes = exercise['notes'];
      if (exerciseId is! String ||
          exerciseId.trim().isEmpty ||
          exerciseId.length > 120 ||
          sets == null ||
          rest == null ||
          (exercise.containsKey('repsTarget') && reps == null) ||
          (exercise.containsKey('weightTarget') && weight == null) ||
          (exercise.containsKey('rpeTarget') && rpe == null) ||
          (slug != null &&
              (slug is! String ||
                  slug.trim().isEmpty ||
                  slug.length > 120 ||
                  !RegExp(r'^[a-z0-9-]+$').hasMatch(slug))) ||
          (notes != null &&
              (notes is! String ||
                  notes.trim().isEmpty ||
                  notes.length > 500))) {
        return null;
      }
      exercises.add(
        TemplateProposalExercise(
          exerciseId: exerciseId.trim(),
          slug: slug is String ? slug : null,
          sets: sets,
          repsTarget: reps,
          restTimerSeconds: rest,
          weightTarget: weight,
          rpeTarget: rpe,
          notes: notes is String ? notes.trim() : null,
        ),
      );
    }
    return TemplateProposalPlan(
      name: name.trim(),
      description: description is String ? description.trim() : null,
      exercises: List.unmodifiable(exercises),
    );
  }

  static String? _templateIdFromRoute(String route) {
    const prefix = '/templates/';
    if (!route.startsWith(prefix)) return null;
    final encoded = route.substring(prefix.length);
    if (encoded.isEmpty || encoded.contains('/') || encoded.length > 384) {
      return null;
    }
    try {
      final decoded = Uri.decodeComponent(encoded).trim();
      return decoded.isEmpty || decoded.length > 128 ? null : decoded;
    } on FormatException {
      return null;
    }
  }

  static String? _proposalIdFromRoute(String route) {
    const prefix = '/proposals/';
    if (!route.startsWith(prefix)) return null;
    final encoded = route.substring(prefix.length);
    if (encoded.isEmpty || encoded.contains('/') || encoded.length > 384) {
      return null;
    }
    try {
      final decoded = Uri.decodeComponent(encoded).trim();
      return decoded.isEmpty || decoded.length > 128 ? null : decoded;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool _isRealDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return false;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    // Match the backend's Date.UTC round-trip validation. JavaScript treats
    // years 0 through 99 as 1900 through 1999, so those values are not valid
    // YYYY-MM-DD inputs for this shared contract.
    if (year < 100) return false;
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }

  static const Object _invalidOptionalNumber = Object();

  static Object? _optionalDoubleInRange(Object? value, double min, double max) {
    if (value == null) return null;
    return _doubleInRange(value, min, max) ?? _invalidOptionalNumber;
  }

  static int? _intInRange(Object? value, int min, int max) {
    if (value is! num || !value.isFinite || value.toInt() != value) return null;
    final result = value.toInt();
    return result >= min && result <= max ? result : null;
  }

  static double? _doubleInRange(Object? value, double min, double max) {
    if (value is! num) return null;
    final result = value.toDouble();
    return result.isFinite && result >= min && result <= max ? result : null;
  }

  void _log(String name, {required String tool, required String status}) {
    try {
      _telemetry?.call(name, {'tool': tool, 'status': status});
    } catch (_) {
      // Telemetry is best-effort and must not alter tool behavior.
    }
  }
}

const _emptySchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{},
  'additionalProperties': false,
};

const _workoutHistorySchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'limit': {'type': 'integer', 'minimum': 1, 'maximum': 20, 'default': 10},
    'cursor': {'type': 'string', 'minLength': 1, 'maxLength': 1024},
  },
  'additionalProperties': false,
};

const _exerciseHistorySchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'limit': {'type': 'integer', 'minimum': 1, 'maximum': 20, 'default': 10},
    'sinceDays': {
      'type': 'integer',
      'minimum': 1,
      'maximum': 3650,
      'default': 365,
    },
  },
  'additionalProperties': false,
};

const _coachingTrendsSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'windowDays': {
      'type': 'integer',
      'enum': [7, 30, 90],
      'default': 30,
    },
  },
  'additionalProperties': false,
};

const _workoutAdjustmentSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'changes': {
      'type': 'array',
      'minItems': 1,
      'maxItems': 8,
      'items': {
        'type': 'object',
        'properties': {
          'exerciseId': {'type': 'string'},
          'setId': {'type': 'string'},
          'weight': {'type': 'number', 'minimum': 0, 'maximum': 2000},
          'reps': {'type': 'integer', 'minimum': 0, 'maximum': 1000},
          'rpe': {'type': 'integer', 'minimum': 1, 'maximum': 10},
        },
        'required': ['exerciseId', 'setId'],
        'additionalProperties': false,
      },
    },
  },
  'required': ['changes'],
  'additionalProperties': false,
};

const _nutritionProposalSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'caloriesTarget': {'type': 'integer', 'minimum': 800, 'maximum': 6000},
    'proteinTarget': {'type': 'number', 'minimum': 0, 'maximum': 500},
    'carbsTarget': {'type': 'number', 'minimum': 0, 'maximum': 1500},
    'fatTarget': {'type': 'number', 'minimum': 0, 'maximum': 400},
    'rationale': {'type': 'string', 'minLength': 1, 'maxLength': 500},
  },
  'required': ['caloriesTarget', 'proteinTarget', 'carbsTarget', 'fatTarget'],
  'additionalProperties': false,
};

const _foodLogEntriesSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'date': {
      'type': 'string',
      'pattern': r'^\d{4}-\d{2}-\d{2}$',
      'description': 'User local diary date in YYYY-MM-DD form.',
    },
  },
  'required': ['date'],
  'additionalProperties': false,
};

const _foodLogProposalSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'payload': {
      'type': 'object',
      'properties': {
        'date': {
          'type': 'string',
          'pattern': r'^\d{4}-\d{2}-\d{2}$',
          'description': 'User local date in YYYY-MM-DD form.',
        },
        'items': {
          'type': 'array',
          'minItems': 1,
          'maxItems': 20,
          'items': {
            'type': 'object',
            'properties': {
              'foodName': {'type': 'string', 'minLength': 1, 'maxLength': 200},
              'servingGrams': {
                'type': 'number',
                'exclusiveMinimum': 0,
                'maximum': 5000,
              },
              'calories': {'type': 'number', 'minimum': 0, 'maximum': 5000},
              'proteinGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
              'carbsGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
              'fatGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
              'fiberGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
              'sugarGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
              'sodiumMg': {'type': 'number', 'minimum': 0, 'maximum': 100000},
            },
            'required': [
              'foodName',
              'servingGrams',
              'calories',
              'proteinGrams',
              'carbsGrams',
              'fatGrams',
            ],
            'additionalProperties': false,
          },
        },
        'note': {'type': 'string', 'minLength': 1, 'maxLength': 500},
      },
      'required': ['date', 'items'],
      'additionalProperties': false,
    },
  },
  'required': ['payload'],
  'additionalProperties': false,
};

const _foodLogRevisionChangesSchema = <String, Object?>{
  'type': 'object',
  'minProperties': 1,
  'properties': {
    'foodName': {'type': 'string', 'minLength': 1, 'maxLength': 200},
    'servingGrams': {'type': 'number', 'exclusiveMinimum': 0, 'maximum': 5000},
    'calories': {'type': 'number', 'minimum': 0, 'maximum': 5000},
    'proteinGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
    'carbsGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
    'fatGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
    'fiberGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
    'sugarGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
    'sodiumMg': {'type': 'number', 'minimum': 0, 'maximum': 100000},
  },
  'additionalProperties': false,
};

const _foodLogEditProposalSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'payload': {
      'type': 'object',
      'properties': {
        'targetEntryId': {
          'type': 'string',
          'format': 'uuid',
          'description':
              'Opaque entry id returned by hustl_get_food_log_entries.',
        },
        'changes': _foodLogRevisionChangesSchema,
      },
      'required': ['targetEntryId', 'changes'],
      'additionalProperties': false,
    },
  },
  'required': ['payload'],
  'additionalProperties': false,
};

const _foodLogDeleteProposalSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'payload': {
      'type': 'object',
      'properties': {
        'targetEntryId': {
          'type': 'string',
          'format': 'uuid',
          'description':
              'Opaque entry id returned by hustl_get_food_log_entries.',
        },
      },
      'required': ['targetEntryId'],
      'additionalProperties': false,
    },
  },
  'required': ['payload'],
  'additionalProperties': false,
};

const _templateExerciseSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'exerciseId': {'type': 'string', 'minLength': 1, 'maxLength': 120},
    'slug': {
      'type': 'string',
      'minLength': 1,
      'maxLength': 120,
      'pattern': r'^[a-z0-9-]+$',
    },
    'sets': {'type': 'integer', 'minimum': 1, 'maximum': 20},
    'repsTarget': {'type': 'integer', 'minimum': 1, 'maximum': 100},
    'restTimerSeconds': {'type': 'integer', 'minimum': 0, 'maximum': 600},
    'weightTarget': {'type': 'number', 'minimum': 0, 'maximum': 2000},
    'rpeTarget': {'type': 'integer', 'minimum': 1, 'maximum': 10},
    'notes': {'type': 'string', 'minLength': 1, 'maxLength': 500},
  },
  'required': ['exerciseId', 'sets', 'restTimerSeconds'],
  'additionalProperties': false,
};

const _templatePlanSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'name': {'type': 'string', 'minLength': 1, 'maxLength': 120},
    'description': {'type': 'string', 'minLength': 1, 'maxLength': 2000},
    'exercises': {
      'type': 'array',
      'minItems': 1,
      'maxItems': 30,
      'items': _templateExerciseSchema,
    },
  },
  'required': ['name', 'exercises'],
  'additionalProperties': false,
};

const _templateCreateProposalSchema = <String, Object?>{
  'type': 'object',
  'properties': {'plan': _templatePlanSchema},
  'required': ['plan'],
  'additionalProperties': false,
};

const _templateEditProposalSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'plan': _templatePlanSchema,
    'baseUpdatedAt': {
      'type': 'string',
      'format': 'date-time',
      'minLength': 20,
      'maxLength': 40,
      'description':
          'Exact updatedAt returned by hustl_get_template_context. The edit '
          'fails if the template changed after that read.',
    },
    'acknowledgeNormalization': {
      'type': 'boolean',
      'description':
          'Required when hustl_get_template_context reports lossyOnEdit=true.',
    },
  },
  'required': ['plan', 'baseUpdatedAt'],
  'additionalProperties': false,
};
