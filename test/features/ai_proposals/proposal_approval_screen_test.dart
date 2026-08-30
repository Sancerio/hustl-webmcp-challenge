import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/features/ai_proposals/domain/models/proposal_detail.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposed_food_log.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_summary.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposed_nutrition_target.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposed_workout_log.dart';
import 'package:hustl_app/features/ai_proposals/domain/repositories/proposals_repository.dart';
import 'package:hustl_app/features/ai_proposals/presentation/bloc/proposals_bloc.dart';
import 'package:hustl_app/features/ai_proposals/presentation/screens/proposal_approval_screen.dart';
import 'package:hustl_app/features/ai_proposals/services/proposal_events_service.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/nutrition_target_plan.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';
import 'package:hustl_app/features/workout_templates/domain/models/workout_template.dart';
import 'package:hustl_app/features/workout_templates/domain/repositories/template_repository.dart';
import 'package:hustl_app/app/theme/app_theme.dart';

ProposalSummary _pendingNutritionProposal() => ProposalSummary(
  id: 'proposal-1',
  kind: ProposalKind.nutritionTargets,
  status: 'pending',
  templateName: 'Nutrition targets',
  exerciseCount: 0,
  createdAt: DateTime(2026, 8, 28),
);

ProposalDetail _pendingNutritionDetail() => ProposalDetail(
  summary: _pendingNutritionProposal(),
  proposedExercises: const [],
  resolvedExercises: const [],
  proposedNutrition: const ProposedNutritionTarget(
    caloriesTarget: 2000,
    proteinTarget: 150,
    carbsTarget: 220,
    fatTarget: 60,
  ),
);

ProposalDetail _terminalNutritionDetail(String status) => ProposalDetail(
  summary: ProposalSummary(
    id: 'proposal-1',
    kind: ProposalKind.nutritionTargets,
    status: status,
    templateName: 'Nutrition targets',
    exerciseCount: 0,
    createdAt: DateTime(2026, 8, 28),
    decidedAt: DateTime(2026, 8, 29),
  ),
  proposedExercises: const [],
  resolvedExercises: const [],
  proposedNutrition: const ProposedNutritionTarget(
    caloriesTarget: 2000,
    proteinTarget: 150,
    carbsTarget: 220,
    fatTarget: 60,
  ),
);

ProposalDetail _terminalFoodDetail(String status) => ProposalDetail(
  summary: ProposalSummary(
    id: 'proposal-1',
    kind: ProposalKind.foodLog,
    status: status,
    templateName: 'Food log',
    exerciseCount: 0,
    createdAt: DateTime(2026, 8, 28),
    decidedAt: DateTime(2026, 8, 29),
  ),
  proposedExercises: const [],
  resolvedExercises: const [],
  proposedFoodLog: ProposedFoodLog(
    date: DateTime(2026, 8, 28),
    items: const [
      ProposedFoodItem(
        foodName: 'Test meal',
        servingGrams: 100,
        calories: 250,
        proteinGrams: 20,
        carbsGrams: 30,
        fatGrams: 6,
      ),
    ],
  ),
);

ProposalDetail _terminalWorkoutDetail(String status) => ProposalDetail(
  summary: ProposalSummary(
    id: 'proposal-1',
    kind: ProposalKind.workoutLog,
    status: status,
    templateName: 'Workout log',
    exerciseCount: 1,
    createdAt: DateTime(2026, 8, 28),
    decidedAt: DateTime(2026, 8, 29),
  ),
  proposedExercises: const [],
  resolvedExercises: const [],
  proposedWorkoutLog: const ProposedWorkoutLog(
    name: 'Test workout',
    exercises: [
      ProposedWorkoutExercise(
        name: 'Test exercise',
        sets: [ProposedWorkoutSet(weight: 20, reps: 8)],
      ),
    ],
  ),
);

class _FakeProposalsRepository implements ProposalsRepository {
  _FakeProposalsRepository({ProposalDetail? detail})
    : detail = detail ?? _pendingNutritionDetail() {
    pending = this.detail.isPending ? [this.detail.summary] : [];
  }

  final ProposalDetail detail;
  late List<ProposalSummary> pending;
  bool reverted = false;

  @override
  Future<List<ProposalSummary>> listPending({int limit = 50}) async => pending;

  @override
  Future<ProposalDetail> getProposal(String id) async => detail;

  @override
  Future<void> reject(String id, {String? reason}) async {
    pending = pending.where((proposal) => proposal.id != id).toList();
  }

  @override
  Future<void> revert(String id) async {
    reverted = true;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTemplateRepository implements TemplateRepository {
  @override
  Future<List<WorkoutTemplate>> getWorkoutTemplates() async => const [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNutritionTargetsRepository implements NutritionTargetsRepository {
  @override
  Future<NutritionTargetPlan?> getCurrentPlan(
    DateTime date, {
    bool readOnly = false,
  }) async => null;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets(
    'direct proposal dismissal returns to Coach without actionable controls',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeProposalsRepository();
      final templateRepository = _FakeTemplateRepository();
      getIt.registerSingleton<ProposalsRepository>(repository);
      getIt.registerSingleton<TemplateRepository>(templateRepository);
      getIt.registerSingleton<NutritionTargetsRepository>(
        _FakeNutritionTargetsRepository(),
      );
      getIt.registerFactory<ProposalsBloc>(
        () => ProposalsBloc(
          repository: repository,
          events: ProposalEventsService(),
          templateRepository: templateRepository,
        ),
      );

      final router = GoRouter(
        initialLocation: '/proposals/proposal-1',
        routes: [
          GoRoute(
            path: '/proposals',
            builder: (_, __) => const Scaffold(body: Text('Coach inbox')),
          ),
          GoRoute(
            path: '/proposals/:id',
            builder: (_, state) =>
                ProposalApprovalScreen(proposalId: state.pathParameters['id']!),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('Apply targets'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Dismiss'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Dismiss'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Dismiss'));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/proposals');
      expect(find.text('Coach inbox'), findsOneWidget);
      expect(find.text('Apply targets'), findsNothing);
      expect(find.text('Dismiss'), findsNothing);
      expect(repository.pending, isEmpty);
    },
  );

  testWidgets(
    'rejected nutrition detail is read-only when revisited directly',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeProposalsRepository(
        detail: _terminalNutritionDetail('rejected'),
      );
      final templateRepository = _FakeTemplateRepository();
      getIt.registerSingleton<ProposalsRepository>(repository);
      getIt.registerSingleton<TemplateRepository>(templateRepository);
      getIt.registerSingleton<NutritionTargetsRepository>(
        _FakeNutritionTargetsRepository(),
      );
      getIt.registerFactory<ProposalsBloc>(
        () => ProposalsBloc(
          repository: repository,
          events: ProposalEventsService(),
          templateRepository: templateRepository,
        ),
      );

      final router = GoRouter(
        initialLocation: '/proposals/proposal-1',
        routes: [
          GoRoute(
            path: '/proposals',
            builder: (_, __) => const Scaffold(body: Text('Coach inbox')),
          ),
          GoRoute(
            path: '/proposals/:id',
            builder: (_, state) =>
                ProposalApprovalScreen(proposalId: state.pathParameters['id']!),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('This proposal was dismissed'), findsOneWidget);
      expect(find.text('Declined'), findsOneWidget);
      expect(find.text('Apply targets'), findsNothing);
      expect(find.text('Dismiss'), findsNothing);
      expect(find.textContaining('Applies to the week of'), findsNothing);
      expect(find.textContaining('will be saved'), findsNothing);
      expect(
        find.text(
          'These are the calorie and macro targets included in the proposal.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, 'Close'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Close'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/proposals');
    },
  );

  testWidgets('rejected food log never offers Undo or pending actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeProposalsRepository(
      detail: _terminalFoodDetail('rejected'),
    );
    final templateRepository = _FakeTemplateRepository();
    getIt.registerSingleton<ProposalsRepository>(repository);
    getIt.registerSingleton<TemplateRepository>(templateRepository);
    getIt.registerSingleton<NutritionTargetsRepository>(
      _FakeNutritionTargetsRepository(),
    );
    getIt.registerFactory<ProposalsBloc>(
      () => ProposalsBloc(
        repository: repository,
        events: ProposalEventsService(),
        templateRepository: templateRepository,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: ProposalApprovalScreen(proposalId: 'proposal-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('This proposal was dismissed'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
    expect(find.text('Log it'), findsNothing);
    expect(find.text('Dismiss'), findsNothing);
    expect(find.text('Proposed for 2026-08-28'), findsOneWidget);
    expect(find.textContaining('Logged by your assistant'), findsNothing);
    expect(find.text('Close', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expired workout log uses neutral terminal copy', (tester) async {
    final repository = _FakeProposalsRepository(
      detail: _terminalWorkoutDetail('expired'),
    );
    final templateRepository = _FakeTemplateRepository();
    getIt.registerSingleton<ProposalsRepository>(repository);
    getIt.registerSingleton<TemplateRepository>(templateRepository);
    getIt.registerSingleton<NutritionTargetsRepository>(
      _FakeNutritionTargetsRepository(),
    );
    getIt.registerFactory<ProposalsBloc>(
      () => ProposalsBloc(
        repository: repository,
        events: ProposalEventsService(),
        templateRepository: templateRepository,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: ProposalApprovalScreen(proposalId: 'proposal-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('This proposal is no longer actionable'), findsOneWidget);
    expect(find.textContaining('Logged by your assistant'), findsNothing);
    expect(find.text('Undo'), findsNothing);
    expect(find.text('Log workout'), findsNothing);
    expect(find.text('Dismiss'), findsNothing);
  });

  testWidgets('reverted food log stays read-only with neutral detail copy', (
    tester,
  ) async {
    final repository = _FakeProposalsRepository(
      detail: _terminalFoodDetail('reverted'),
    );
    final templateRepository = _FakeTemplateRepository();
    getIt.registerSingleton<ProposalsRepository>(repository);
    getIt.registerSingleton<TemplateRepository>(templateRepository);
    getIt.registerSingleton<NutritionTargetsRepository>(
      _FakeNutritionTargetsRepository(),
    );
    getIt.registerFactory<ProposalsBloc>(
      () => ProposalsBloc(
        repository: repository,
        events: ProposalEventsService(),
        templateRepository: templateRepository,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: ProposalApprovalScreen(proposalId: 'proposal-1')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('This was already undone — nothing is logged.'),
      findsOneWidget,
    );
    expect(find.text('Proposed for 2026-08-28'), findsOneWidget);
    expect(find.textContaining('Logged by your assistant'), findsNothing);
    expect(find.text('Undo'), findsNothing);
    expect(find.text('Dismiss'), findsNothing);
  });

  testWidgets('applied food log keeps its existing Undo action', (
    tester,
  ) async {
    final repository = _FakeProposalsRepository(
      detail: _terminalFoodDetail('applied'),
    );
    final templateRepository = _FakeTemplateRepository();
    getIt.registerSingleton<ProposalsRepository>(repository);
    getIt.registerSingleton<TemplateRepository>(templateRepository);
    getIt.registerSingleton<NutritionTargetsRepository>(
      _FakeNutritionTargetsRepository(),
    );
    getIt.registerFactory<ProposalsBloc>(
      () => ProposalsBloc(
        repository: repository,
        events: ProposalEventsService(),
        templateRepository: templateRepository,
      ),
    );

    final router = GoRouter(
      initialLocation: '/proposals/proposal-1',
      routes: [
        GoRoute(
          path: '/proposals',
          builder: (_, __) => const Scaffold(body: Text('Coach inbox')),
        ),
        GoRoute(
          path: '/proposals/:id',
          builder: (_, state) =>
              ProposalApprovalScreen(proposalId: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Undo'), findsOneWidget);
    expect(find.textContaining('Logged by your assistant'), findsOneWidget);
    expect(find.text('Log it'), findsNothing);
    expect(find.text('Dismiss'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(repository.reverted, isTrue);
    expect(router.routeInformationProvider.value.uri.path, '/proposals');
  });
}
