import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/navigation/route_observer.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/auto_logged_proposal.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/food_log_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/nutrition_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_detail.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_summary.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/starter_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/repositories/proposals_repository.dart';
import 'package:hustl_app/features/ai_proposals/presentation/bloc/proposal_history_cubit.dart';
import 'package:hustl_app/features/ai_proposals/presentation/bloc/proposals_bloc.dart';
import 'package:hustl_app/features/ai_proposals/presentation/screens/proposals_inbox_screen.dart';
import 'package:hustl_app/features/ai_proposals/services/proposal_events_service.dart';
import 'package:hustl_app/features/workout_templates/domain/models/workout_template.dart';
import 'package:hustl_app/features/workout_templates/domain/repositories/template_repository.dart';

ProposalSummary _pendingProposal() => ProposalSummary(
  id: 'pending-1',
  kind: ProposalKind.templateCreate,
  status: 'pending',
  templateName: 'Plan pending',
  exerciseCount: 2,
  createdAt: DateTime(2026, 7, 11),
);

class _FakeProposalsRepository implements ProposalsRepository {
  int decidedLoads = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<NutritionProposalResult> proposeNutritionTargets(
    NutritionProposalInput input,
  ) => throw UnimplementedError();

  @override
  Future<FoodLogProposalResult> proposeFoodLog(FoodLogProposalInput input) =>
      throw UnimplementedError();

  @override
  Future<List<ProposalSummary>> listPending({int limit = 50}) async => [
    _pendingProposal(),
  ];

  @override
  Future<List<ProposalSummary>> listDecided({
    List<String> statuses = const ['applied', 'reverted', 'rejected'],
    int limit = 50,
  }) async {
    decidedLoads++;
    return const [];
  }

  @override
  Future<ProposalDetail> getProposal(String id) async =>
      throw UnimplementedError();

  @override
  Future<ApproveResult> approve(
    String id, {
    required String idempotencyKey,
    String? asOfDate,
  }) async => throw UnimplementedError();

  @override
  Future<void> reject(String id, {String? reason}) async {}

  @override
  Future<void> revert(String id) async {}

  @override
  Future<List<AutoLoggedProposal>> listAutoAppliedLogs({
    DateTime? since,
  }) async => const [];

  @override
  Future<StarterProposalResult> generateStarter() async =>
      const StarterProposalError(code: 'unused', message: 'unused');
}

class _FakeTemplateRepository implements TemplateRepository {
  @override
  Future<List<WorkoutTemplate>> getWorkoutTemplates() async => const [];

  @override
  Future<WorkoutTemplate?> getWorkoutTemplate(String id) async => null;

  @override
  Future<WorkoutTemplate> createWorkoutTemplate(WorkoutTemplate t) async => t;

  @override
  Future<WorkoutTemplate> updateWorkoutTemplate(WorkoutTemplate t) async => t;

  @override
  Future<void> deleteWorkoutTemplate(String id) async {}
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('returning from proposal detail refreshes loaded history', (
    tester,
  ) async {
    final repository = _FakeProposalsRepository();
    final templateRepository = _FakeTemplateRepository();
    getIt.registerFactory<ProposalsBloc>(
      () => ProposalsBloc(
        repository: repository,
        events: ProposalEventsService(),
        templateRepository: templateRepository,
      ),
    );
    getIt.registerFactory<ProposalHistoryCubit>(
      () => ProposalHistoryCubit(repository: repository),
    );

    final router = GoRouter(
      initialLocation: '/proposals',
      observers: [routeObserver],
      routes: [
        GoRoute(
          path: '/proposals',
          builder: (_, __) => const ProposalsInboxScreen(),
        ),
        GoRoute(
          path: '/proposals/:id',
          builder: (context, state) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.pop(),
                child: const Text('Finish decision'),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(repository.decidedLoads, 1);

    await tester.tap(find.textContaining('Pending'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan pending'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish decision'));
    await tester.pumpAndSettle();

    expect(repository.decidedLoads, 2);
  });
}
