import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/ai_proposals/data/datasources/proposals_api.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/auto_logged_proposal.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/food_log_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/nutrition_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_detail.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_summary.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/starter_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/repositories/proposals_repository.dart';
import 'package:hustl_app/features/ai_proposals/presentation/bloc/proposal_history_cubit.dart';

ProposalSummary _summary(
  String id, {
  ProposalKind kind = ProposalKind.foodLog,
  String status = 'applied',
}) {
  return ProposalSummary(
    id: id,
    kind: kind,
    status: status,
    templateName: 'Entry $id',
    exerciseCount: 0,
    createdAt: DateTime(2026, 7, 1),
    decidedAt: DateTime(2026, 7, 2),
  );
}

/// Mirrors the `_FakeRepo` pattern used by `proposals_bloc_test.dart`.
class _FakeRepo implements ProposalsRepository {
  _FakeRepo({
    List<ProposalSummary>? items,
    this.failListDecided = false,
    this.failRevert = false,
  }) : _items = items ?? const [];

  final List<ProposalSummary> _items;
  final bool failListDecided;
  final bool failRevert;
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

  /// When set, the NEXT `listDecided` blocks on this gate instead of returning
  /// immediately — lets a test hold a refresh mid-flight while a revert lands.
  Completer<List<ProposalSummary>>? decidedGate;

  @override
  Future<List<ProposalSummary>> listDecided({
    List<String> statuses = const ['applied', 'reverted', 'rejected'],
    int limit = 50,
  }) async {
    final gate = decidedGate;
    if (gate != null) {
      decidedGate = null;
      return gate.future;
    }
    if (failListDecided) {
      throw ProposalsApiException(
        statusCode: 500,
        code: 'server_error',
        message: 'Something broke',
      );
    }
    return _items;
  }

  @override
  Future<void> revert(String id) async {
    revertCount++;
    lastRevertedId = id;
    if (failRevert) {
      throw ProposalsApiException(
        statusCode: 409,
        code: 'not_revertible',
        message: 'Cannot undo',
      );
    }
  }

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

void main() {
  group('ProposalHistoryCubit', () {
    blocTest<ProposalHistoryCubit, ProposalHistoryState>(
      'load success emits Loading then Loaded with the items',
      build: () => ProposalHistoryCubit(
        repository: _FakeRepo(items: [_summary('a'), _summary('b')]),
      ),
      act: (cubit) => cubit.load(),
      expect: () => [
        isA<ProposalHistoryLoading>(),
        isA<ProposalHistoryLoaded>().having((s) => s.items.length, 'len', 2),
      ],
    );

    blocTest<ProposalHistoryCubit, ProposalHistoryState>(
      'load failure emits Failure with the repository error',
      build: () =>
          ProposalHistoryCubit(repository: _FakeRepo(failListDecided: true)),
      act: (cubit) => cubit.load(),
      expect: () => [
        isA<ProposalHistoryLoading>(),
        isA<ProposalHistoryFailure>()
            .having((s) => s.code, 'code', 'server_error')
            .having((s) => s.message, 'message', 'Something broke'),
      ],
    );

    test(
      'revert success flips the item to reverted and returns true',
      () async {
        final repo = _FakeRepo(items: [_summary('a')]);
        final cubit = ProposalHistoryCubit(repository: repo);
        await cubit.load();
        final target = (cubit.state as ProposalHistoryLoaded).items.first;

        final result = await cubit.revert(target);

        expect(result, isTrue);
        expect(repo.revertCount, 1);
        expect(repo.lastRevertedId, 'a');
        final loaded = cubit.state as ProposalHistoryLoaded;
        expect(loaded.items.single.status, 'reverted');
        expect(loaded.items.single.isRevertable, isFalse);
        expect(loaded.inFlightIds, isEmpty);
        // The server stamps a fresh decided_at on revert; the local row's
        // terminal time advances past its original (2026-07-02) so it regroups.
        expect(
          loaded.items.single.decidedAt!.isAfter(DateTime(2026, 7, 2)),
          isTrue,
        );
        await cubit.close();
      },
    );

    test(
      'a refresh in-flight during a revert cannot clobber the undone row',
      () async {
        final repo = _FakeRepo(items: [_summary('a')]);
        final cubit = ProposalHistoryCubit(repository: repo);
        await cubit.load();
        final target = (cubit.state as ProposalHistoryLoaded).items.first;

        // Kick off a refresh that is stuck fetching a pre-revert snapshot.
        final gate = Completer<List<ProposalSummary>>();
        repo.decidedGate = gate;
        final refreshFuture = cubit.refresh();

        // Undo lands while that refresh is still in flight.
        await cubit.revert(target);
        expect(
          (cubit.state as ProposalHistoryLoaded).items.single.status,
          'reverted',
        );

        // The stale refresh now resolves with the OLD, still-applied snapshot.
        gate.complete([_summary('a')]);
        await refreshFuture;

        // The generation guard must have dropped that stale result — the row
        // stays 'reverted' rather than flipping back to 'applied'.
        expect(
          (cubit.state as ProposalHistoryLoaded).items.single.status,
          'reverted',
        );
        await cubit.close();
      },
    );

    test('an older fetch cannot overwrite a newer response', () async {
      final repo = _FakeRepo();
      final cubit = ProposalHistoryCubit(repository: repo);

      final olderGate = Completer<List<ProposalSummary>>();
      repo.decidedGate = olderGate;
      final olderRefresh = cubit.refresh();

      final newerGate = Completer<List<ProposalSummary>>();
      repo.decidedGate = newerGate;
      final newerRefresh = cubit.refresh();

      newerGate.complete([_summary('newer')]);
      await newerRefresh;
      expect((cubit.state as ProposalHistoryLoaded).items.single.id, 'newer');

      olderGate.complete([_summary('older')]);
      await olderRefresh;
      expect((cubit.state as ProposalHistoryLoaded).items.single.id, 'newer');
      await cubit.close();
    });

    test('a fetch completing after close does not throw or emit', () async {
      final repo = _FakeRepo();
      final cubit = ProposalHistoryCubit(repository: repo);
      final emitted = <ProposalHistoryState>[];
      final subscription = cubit.stream.listen(emitted.add);

      final gate = Completer<List<ProposalSummary>>();
      repo.decidedGate = gate;
      final refresh = cubit.refresh();
      await cubit.close();

      gate.complete([_summary('late')]);
      await expectLater(refresh, completes);
      expect(emitted, isEmpty);
      await subscription.cancel();
    });

    test(
      'revert failure leaves the item untouched and returns false',
      () async {
        final repo = _FakeRepo(items: [_summary('a')], failRevert: true);
        final cubit = ProposalHistoryCubit(repository: repo);
        await cubit.load();
        final target = (cubit.state as ProposalHistoryLoaded).items.first;

        final result = await cubit.revert(target);

        expect(result, isFalse);
        final loaded = cubit.state as ProposalHistoryLoaded;
        expect(loaded.items.single.status, 'applied');
        expect(loaded.inFlightIds, isEmpty);
        await cubit.close();
      },
    );
  });
}
