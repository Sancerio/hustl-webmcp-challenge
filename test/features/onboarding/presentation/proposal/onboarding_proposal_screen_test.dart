import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/auto_logged_proposal.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/food_log_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/nutrition_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_detail.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_summary.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposed_exercise.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/starter_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/repositories/proposals_repository.dart';
import 'package:hustl_app/features/ai_proposals/presentation/bloc/proposals_bloc.dart';
import 'package:hustl_app/features/ai_proposals/services/proposal_events_service.dart';
import 'package:hustl_app/features/onboarding/presentation/proposal/onboarding_proposal_screen.dart';
import 'package:hustl_app/features/workout_templates/domain/models/workout_template.dart';
import 'package:hustl_app/features/workout_templates/domain/repositories/template_repository.dart';

ProposalDetail _detail() => ProposalDetail(
  summary: ProposalSummary(
    id: 'p1',
    kind: ProposalKind.templateCreate,
    status: 'pending',
    templateName: 'Push Day',
    exerciseCount: 4,
    createdAt: DateTime(2026, 6, 27),
  ),
  description: 'Your bench is trending up — time to add a session.',
  proposedExercises: const [
    ProposedExercise(name: 'Bench Press', sets: 3, restTimerSeconds: 90),
  ],
  resolvedExercises: const [],
);

class _FakeRepo implements ProposalsRepository {
  _FakeRepo(this.starter);

  final StarterProposalResult starter;
  int generateCount = 0;
  int approveCount = 0;
  String? approvedId;

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
  Future<StarterProposalResult> generateStarter() async {
    generateCount++;
    return starter;
  }

  @override
  Future<ApproveResult> approve(
    String id, {
    required String idempotencyKey,
    String? asOfDate,
  }) async {
    approveCount++;
    approvedId = id;
    return const ApproveResult(templateId: 't1', syncVersion: 2);
  }

  @override
  Future<ProposalDetail> getProposal(String id) async => _detail();

  @override
  Future<List<ProposalSummary>> listPending({int limit = 50}) async => const [];

  @override
  Future<List<ProposalSummary>> listDecided({
    List<String> statuses = const ['applied', 'reverted', 'rejected'],
    int limit = 50,
  }) async => const [];

  @override
  Future<void> reject(String id, {String? reason}) async {}

  @override
  Future<void> revert(String id) async {}

  @override
  Future<List<AutoLoggedProposal>> listAutoAppliedLogs({
    DateTime? since,
  }) async => const [];
}

class _FakeTemplateRepo implements TemplateRepository {
  @override
  Future<WorkoutTemplate?> getWorkoutTemplate(String id) async => null;

  @override
  Future<List<WorkoutTemplate>> getWorkoutTemplates() async => const [];

  @override
  Future<WorkoutTemplate> createWorkoutTemplate(WorkoutTemplate t) async => t;

  @override
  Future<WorkoutTemplate> updateWorkoutTemplate(WorkoutTemplate t) async => t;

  @override
  Future<void> deleteWorkoutTemplate(String id) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = PreferencesService();
    prefs.resetForTests();
    await prefs.init();
  });

  ProposalsBloc buildBloc(_FakeRepo repo) => ProposalsBloc(
    repository: repo,
    events: ProposalEventsService(),
    templateRepository: _FakeTemplateRepo(),
  );

  Future<void> pump(
    WidgetTester tester, {
    required _FakeRepo repo,
    required ProposalsBloc bloc,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingProposalScreen(
          repository: repo,
          preferences: prefs,
          bloc: bloc,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('consent gate blocks generation until the user accepts', (
    tester,
  ) async {
    final repo = _FakeRepo(
      StarterProposalCreated(proposal: _detail(), proposalId: 'p1'),
    );
    final bloc = buildBloc(repo);
    addTearDown(bloc.close);

    // consent defaults to false → consent gate, no draft generated yet.
    await pump(tester, repo: repo, bloc: bloc);
    expect(find.text('Draft my plan'), findsOneWidget);
    expect(repo.generateCount, 0);
    expect(find.text('Your starter plan'), findsNothing);

    // Accepting consent kicks off generation and renders the real proposal.
    await tester.tap(find.text('Draft my plan'));
    await tester.pumpAndSettle();

    expect(repo.generateCount, 1);
    expect(prefs.onboardingProposalConsent, isTrue);
    expect(find.text('Your starter plan'), findsOneWidget);
    expect(find.textContaining('Push Day'), findsOneWidget);
  });

  testWidgets('Approve dispatches the existing ProposalsBloc approve event', (
    tester,
  ) async {
    final repo = _FakeRepo(
      StarterProposalCreated(proposal: _detail(), proposalId: 'p1'),
    );
    final bloc = buildBloc(repo);
    addTearDown(bloc.close);

    // Pre-consented → the screen auto-generates and shows the proposal.
    await prefs.setOnboardingProposalConsent(true);
    await pump(tester, repo: repo, bloc: bloc);
    expect(find.text('Approve'), findsOneWidget);

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    // The approve flowed through the REAL bloc handler (not a fork): the same
    // repository's approve() ran with the proposal id.
    expect(repo.approveCount, 1);
    expect(repo.approvedId, 'p1');
    // Terminal success state, never a dead-end.
    expect(find.text('Your plan is set'), findsOneWidget);
  });
}
