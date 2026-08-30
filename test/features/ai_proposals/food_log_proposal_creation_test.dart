import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hustl_app/app/demo/demo_proposals_repository.dart';
import 'package:hustl_app/core/services/token_storage.dart' as token;
import 'package:hustl_app/features/ai_proposals/data/datasources/proposals_api.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/food_log_proposal_result.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/template_proposal_result.dart';

class _FakeTokenStorage implements token.TokenStorage {
  @override
  Future<String?> getAccessToken() async => 'token';

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<void> saveTokenPair({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
  }) async {}

  @override
  Future<void> clearAccessToken() async {}

  @override
  Future<void> clearAll() async {}
}

const _input = FoodLogProposalInput(
  date: '2026-08-28',
  note: 'One medium apple.',
  items: [
    FoodLogProposalItem(
      foodName: 'Apple',
      servingGrams: 182,
      calories: 95,
      proteinGrams: 0.5,
      carbsGrams: 25,
      fatGrams: 0.3,
      fiberGrams: 4.4,
      sugarGrams: 19,
      sodiumMg: 2,
    ),
  ],
);

void main() {
  test(
    'app API posts the exact food log and parses a pending proposal',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/proposals/food-log');
        expect(request.headers['Authorization'], 'Bearer token');
        expect(jsonDecode(request.body), _input.toJson());
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'status': 'pending',
              'proposalId': 'food-1',
              'humanMessage': 'Review this food log in Hustl.',
              'proposal': {
                'id': 'food-1',
                'kind': 'food_log',
                'status': 'pending',
                'templateName': 'Food log',
                'exerciseCount': 0,
                'summary': 'Log 1 item — 95 kcal',
                'createdAt': '2026-08-28T00:00:00.000Z',
                'proposedExercises': [],
                'resolvedExercisesAsOfProposal': [],
                'proposedPayload': _input.toJson(),
              },
            },
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = ProposalsApi(
        client: client,
        baseUrl: 'https://example.com',
        tokens: _FakeTokenStorage(),
      );

      final result = await api.proposeFoodLog(_input);

      expect(result.status, 'pending');
      expect(result.proposalId, 'food-1');
      expect(result.humanMessage, 'Review this food log in Hustl.');
      expect(result.requiresHumanReview, isTrue);
      expect(result.proposal.isPending, isTrue);
      expect(result.proposal.proposedFoodLog?.items.single.foodName, 'Apple');
    },
  );

  test('demo path creates then replays one pending draft', () async {
    final repository = DemoProposalsRepository(anchor: DateTime(2026, 8, 28));

    final created = await repository.proposeFoodLog(_input);
    final replay = await repository.proposeFoodLog(_input);

    expect(created.status, 'pending');
    expect(replay.status, 'duplicate');
    expect(replay.proposalId, created.proposalId);
    expect(
      (await repository.listPending()).where(
        (proposal) => proposal.id == created.proposalId,
      ),
      hasLength(1),
    );
    expect(created.proposal.proposedFoodLog?.items.single.foodName, 'Apple');
  });

  test(
    'legacy rollout limit response normalizes to the short-window code',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'daily_quota_exceeded',
              'message': 'Legacy rollout response.',
            },
          }),
          429,
          headers: {'content-type': 'application/json'},
        ),
      );
      final api = ProposalsApi(
        client: client,
        baseUrl: 'https://example.com',
        tokens: _FakeTokenStorage(),
      );

      await expectLater(
        api.proposeFoodLog(_input),
        throwsA(
          isA<ProposalUnavailable>().having(
            (error) => error.code,
            'code',
            'proposal_rate_limited',
          ),
        ),
      );
    },
  );

  test('demo path reports an already-applied replay truthfully', () async {
    final repository = DemoProposalsRepository(anchor: DateTime(2026, 8, 28));

    final created = await repository.proposeFoodLog(_input);
    await repository.approve(
      created.proposalId,
      idempotencyKey: 'demo-food-log-apply',
    );
    final replay = await repository.proposeFoodLog(_input);

    expect(replay.status, 'applied');
    expect(replay.proposalId, created.proposalId);
    expect(replay.requiresHumanReview, isFalse);
    expect(replay.proposal.summary.isApplied, isTrue);
  });
}
