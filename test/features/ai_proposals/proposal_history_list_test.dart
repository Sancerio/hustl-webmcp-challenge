import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/auto_logged_proposal.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/food_log_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/nutrition_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_detail.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_summary.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/starter_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/repositories/proposals_repository.dart';
import 'package:hustl_app/features/ai_proposals/presentation/bloc/proposal_history_cubit.dart';
import 'package:hustl_app/features/ai_proposals/presentation/widgets/proposal_history_list.dart';

ProposalSummary _summary(
  String id, {
  required ProposalKind kind,
  required String status,
  required DateTime decidedAt,
  bool autoApplied = false,
  String? autoSource,
}) {
  return ProposalSummary(
    id: id,
    kind: kind,
    status: status,
    templateName: 'Entry $id',
    exerciseCount: 0,
    summary: 'Summary for $id',
    createdAt: decidedAt,
    decidedAt: decidedAt,
    autoApplied: autoApplied,
    autoSource: autoSource,
  );
}

class _FakeRepo implements ProposalsRepository {
  _FakeRepo(this.items);
  final List<ProposalSummary> items;

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
  Future<List<ProposalSummary>> listDecided({
    List<String> statuses = const ['applied', 'reverted', 'rejected'],
    int limit = 50,
  }) async => items;

  @override
  Future<void> revert(String id) async {}

  @override
  Future<List<ProposalSummary>> listPending({int limit = 50}) async => const [];

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
  Future<List<AutoLoggedProposal>> listAutoAppliedLogs({
    DateTime? since,
  }) async => const [];

  @override
  Future<StarterProposalResult> generateStarter() async =>
      const StarterProposalError(code: 'unused', message: 'unused');
}

Widget _wrap(ProposalHistoryCubit cubit) {
  return MaterialApp(
    home: Scaffold(
      body: BlocProvider<ProposalHistoryCubit>.value(
        value: cubit,
        child: const ProposalHistoryList(),
      ),
    ),
  );
}

void main() {
  testWidgets('day grouping renders a header per distinct day', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    final yesterday = today.subtract(const Duration(days: 1, hours: -1));
    final repo = _FakeRepo([
      _summary(
        'a',
        kind: ProposalKind.foodLog,
        status: 'applied',
        decidedAt: today,
      ),
      _summary(
        'b',
        kind: ProposalKind.templateEdit,
        status: 'rejected',
        decidedAt: yesterday,
      ),
    ]);
    final cubit = ProposalHistoryCubit(repository: repo);
    await cubit.load();

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    await cubit.close();
  });

  testWidgets('Undo shows only on an applied, revertable log row', (
    tester,
  ) async {
    final now = DateTime.now();
    final repo = _FakeRepo([
      _summary(
        'applied-log',
        kind: ProposalKind.foodLog,
        status: 'applied',
        decidedAt: now,
      ),
      _summary(
        'applied-nutrition',
        kind: ProposalKind.nutritionTargets,
        status: 'applied',
        decidedAt: now,
      ),
      _summary(
        'reverted-log',
        kind: ProposalKind.workoutLog,
        status: 'reverted',
        decidedAt: now,
      ),
      _summary(
        'rejected-template',
        kind: ProposalKind.templateCreate,
        status: 'rejected',
        decidedAt: now,
      ),
    ]);
    final cubit = ProposalHistoryCubit(repository: repo);
    await cubit.load();

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    // Only the applied log row offers Undo; the rest show a status chip.
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Applied'), findsOneWidget);
    expect(find.text('Undone'), findsOneWidget);
    expect(find.text('Declined'), findsOneWidget);
  });

  testWidgets(
    'first-party auto-applied food shows audit state and normal Undo',
    (tester) async {
      final repo = _FakeRepo([
        _summary(
          'web-food',
          kind: ProposalKind.foodLog,
          status: 'applied',
          decidedAt: DateTime.now(),
          autoApplied: true,
          autoSource: 'first_party_webmcp',
        ),
      ]);
      final cubit = ProposalHistoryCubit(repository: repo);
      await cubit.load();

      await tester.pumpWidget(_wrap(cubit));
      await tester.pumpAndSettle();

      expect(find.textContaining('Web auto-log'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      await cubit.close();
    },
  );
}
