import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/auto_logged_proposal.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/food_log_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/nutrition_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_detail.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_summary.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/starter_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/repositories/proposals_repository.dart';
import 'package:hustl_app/features/ai_proposals/presentation/bloc/proposals_bloc.dart';
import 'package:hustl_app/features/ai_proposals/presentation/bloc/proposals_event.dart';
import 'package:hustl_app/features/ai_proposals/presentation/bloc/proposals_state.dart';
import 'package:hustl_app/features/ai_proposals/services/proposal_events_service.dart';
import 'package:hustl_app/features/workout_templates/domain/models/workout_template.dart';
import 'package:hustl_app/features/workout_templates/domain/repositories/template_repository.dart';

ProposalSummary _summary(
  String id, {
  String? targetTemplateId,
  bool edit = false,
}) {
  return ProposalSummary(
    id: id,
    kind: edit ? ProposalKind.templateEdit : ProposalKind.templateCreate,
    status: 'pending',
    templateName: 'Plan $id',
    exerciseCount: 3,
    targetTemplateId: targetTemplateId,
    createdAt: DateTime(2026, 1, 1),
  );
}

class _FakeRepo implements ProposalsRepository {
  _FakeRepo(this._items, {this.detailFor});

  List<ProposalSummary> _items;
  final ProposalDetail Function(String id)? detailFor;
  int approveCount = 0;
  int revertCount = 0;
  String? lastRevertedId;

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
  Future<List<ProposalSummary>> listPending({int limit = 50}) async => _items;

  @override
  Future<List<ProposalSummary>> listDecided({
    List<String> statuses = const ['applied', 'reverted', 'rejected'],
    int limit = 50,
  }) async => const [];

  @override
  Future<ProposalDetail> getProposal(String id) async {
    if (detailFor != null) return detailFor!(id);
    return ProposalDetail(
      summary: _summary(id),
      proposedExercises: const [],
      resolvedExercises: const [],
    );
  }

  @override
  Future<ApproveResult> approve(
    String id, {
    required String idempotencyKey,
    String? asOfDate,
  }) async {
    approveCount++;
    _items = _items.where((p) => p.id != id).toList();
    return const ApproveResult(templateId: 't1', syncVersion: 2);
  }

  @override
  Future<void> reject(String id, {String? reason}) async {
    _items = _items.where((p) => p.id != id).toList();
  }

  @override
  Future<void> revert(String id) async {
    revertCount++;
    lastRevertedId = id;
  }

  @override
  Future<List<AutoLoggedProposal>> listAutoAppliedLogs({
    DateTime? since,
  }) async => const [];

  @override
  Future<StarterProposalResult> generateStarter() async =>
      const StarterProposalError(code: 'unused', message: 'unused');
}

class _FakeTemplateRepo implements TemplateRepository {
  _FakeTemplateRepo(this.template);
  final WorkoutTemplate? template;

  @override
  Future<WorkoutTemplate?> getWorkoutTemplate(String id) async => template;

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
  group('ProposalsBloc', () {
    test('LoadProposals emits Loaded and pushes the count', () async {
      final events = ProposalEventsService();
      final bloc = ProposalsBloc(
        repository: _FakeRepo([_summary('a'), _summary('b')]),
        events: events,
        templateRepository: _FakeTemplateRepo(null),
      );
      final future = expectLater(
        bloc.stream,
        emitsInOrder([
          isA<ProposalsLoading>(),
          isA<ProposalsLoaded>().having((s) => s.items.length, 'len', 2),
        ]),
      );
      bloc.add(const LoadProposals());
      await future;
      expect(events.pendingCount.value, 2);
      await bloc.close();
    });

    blocTest<ProposalsBloc, ProposalsState>(
      'approve removes the item and decrements the count',
      build: () => ProposalsBloc(
        repository: _FakeRepo([_summary('a'), _summary('b')]),
        events: ProposalEventsService(),
        templateRepository: _FakeTemplateRepo(null),
      ),
      act: (bloc) async {
        bloc.add(const LoadProposals());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const ApproveProposal('a', idempotencyKey: 'k1'));
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        final s = bloc.state as ProposalsLoaded;
        expect(s.items.map((p) => p.id), ['b']);
        expect(s.inFlightIds, isEmpty);
      },
    );

    test(
      'RevertProposal undoes an applied food log via the repository',
      () async {
        final repo = _FakeRepo(const []);
        final bloc = ProposalsBloc(
          repository: repo,
          events: ProposalEventsService(),
          templateRepository: _FakeTemplateRepo(null),
        );
        bloc.add(const RevertProposal('applied-1', kind: ProposalKind.foodLog));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(repo.revertCount, 1);
        expect(repo.lastRevertedId, 'applied-1');
        await bloc.close();
      },
    );

    test('approving a sibling marks the other same-target edit stale', () async {
      // Two pending edits on the same template; the current template's
      // updatedAt is NEWER than the sibling's base snapshot → sibling is stale.
      final current = WorkoutTemplate(
        id: 't1',
        name: 'Push',
        description: '',
        exercises: const [],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 6, 1),
      );
      final repo = _FakeRepo(
        [
          _summary('a', targetTemplateId: 't1', edit: true),
          _summary('b', targetTemplateId: 't1', edit: true),
        ],
        detailFor: (id) => ProposalDetail(
          summary: _summary(id, targetTemplateId: 't1', edit: true),
          proposedExercises: const [],
          resolvedExercises: const [],
          baseTemplateUpdatedAt: DateTime(2026, 1, 1), // older than current
        ),
      );
      final bloc = ProposalsBloc(
        repository: repo,
        events: ProposalEventsService(),
        templateRepository: _FakeTemplateRepo(current),
      );
      bloc.add(const LoadProposals());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const ApproveProposal('a', idempotencyKey: 'k1'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final s = bloc.state as ProposalsLoaded;
      expect(s.items.map((p) => p.id), ['b']);
      expect(s.staleIds, contains('b'));
      await bloc.close();
    });
  });
}
