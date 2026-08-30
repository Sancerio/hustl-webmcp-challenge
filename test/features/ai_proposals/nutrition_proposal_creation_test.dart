import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hustl_app/app/demo/demo_proposals_repository.dart';
import 'package:hustl_app/core/services/token_storage.dart' as token;
import 'package:hustl_app/features/ai_proposals/data/datasources/proposals_api.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/nutrition_proposal_result.dart';
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

const _input = NutritionProposalInput(
  caloriesTarget: 2350,
  proteinTarget: 180,
  carbsTarget: 250,
  fatTarget: 70,
  rationale: 'Fuel training while keeping the cut steady.',
);

void main() {
  test(
    'app API posts the exact four-tuple and parses a pending proposal',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/proposals/nutrition');
        expect(request.headers['Authorization'], 'Bearer token');
        expect(jsonDecode(request.body), _input.toJson());
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'status': 'pending',
              'proposalId': 'nutrition-1',
              'proposal': {
                'id': 'nutrition-1',
                'kind': 'nutrition_targets',
                'status': 'pending',
                'templateName': 'Nutrition target update',
                'exerciseCount': 0,
                'summary': '2350 kcal · 180 g protein',
                'createdAt': '2026-08-27T00:00:00.000Z',
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

      final result = await api.proposeNutritionTargets(_input);

      expect(result.status, 'pending');
      expect(result.proposalId, 'nutrition-1');
      expect(result.proposal.isPending, isTrue);
      expect(result.proposal.proposedNutrition?.proteinTarget, 180);
    },
  );

  test('demo proposal path creates then replays the pending draft', () async {
    final repository = DemoProposalsRepository(anchor: DateTime(2026, 8, 27));
    const demoInput = NutritionProposalInput(
      caloriesTarget: 2400,
      proteinTarget: 185,
      carbsTarget: 255,
      fatTarget: 70,
      rationale: 'A distinct deterministic demo proposal.',
    );

    final created = await repository.proposeNutritionTargets(demoInput);
    final replay = await repository.proposeNutritionTargets(demoInput);

    expect(created.status, 'pending');
    expect(replay.status, 'duplicate');
    expect(replay.proposalId, created.proposalId);
    expect(
      (await repository.listPending()).any(
        (proposal) => proposal.id == created.proposalId,
      ),
      isTrue,
    );
  });

  test('app API preserves the shared proposal rate-limit code', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'success': false,
          'error': {
            'code': 'proposal_rate_limited',
            'message': 'Try again shortly.',
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
      api.proposeNutritionTargets(_input),
      throwsA(
        isA<ProposalUnavailable>().having(
          (error) => error.code,
          'code',
          'proposal_rate_limited',
        ),
      ),
    );
  });
}
