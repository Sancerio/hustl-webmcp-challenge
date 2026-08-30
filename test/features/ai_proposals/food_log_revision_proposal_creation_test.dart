import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hustl_app/app/demo/demo_food_log_repository.dart';
import 'package:hustl_app/app/demo/demo_proposals_repository.dart';
import 'package:hustl_app/core/services/token_storage.dart' as token;
import 'package:hustl_app/features/ai_proposals/data/datasources/proposals_api.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/food_log_revision_proposal_result.dart';
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

const _entryId = '11111111-2222-4333-8444-555555555555';
const _edit = FoodLogEditProposalInput(
  targetEntryId: _entryId,
  changes: FoodLogRevisionChanges(servingGrams: 200, calories: 330),
);
const _delete = FoodLogDeleteProposalInput(targetEntryId: _entryId);

Map<String, Object?> _proposalJson(String kind) => {
  'id': 'revision-1',
  'kind': kind,
  'status': 'pending',
  'templateName': 'Chicken rice',
  'exerciseCount': 0,
  'summary': kind == 'food_log_edit'
      ? 'Update "Chicken rice"'
      : 'Remove "Chicken rice"',
  'createdAt': '2026-08-29T00:00:00.000Z',
  'proposedExercises': <Object?>[],
  'resolvedExercisesAsOfProposal': <Object?>[],
  'proposedPayload': {
    'targetEntryId': _entryId,
    if (kind == 'food_log_edit') 'changes': _edit.changes.toJson(),
    'target': {
      'date': '2026-08-28',
      'foodName': 'Chicken rice',
      'servingGrams': 300,
      'calories': 495,
      'proteinGrams': 40,
      'carbsGrams': 55,
      'fatGrams': 12,
    },
  },
};

void main() {
  test('app API posts an exact review-only food edit', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/proposals/food-log-revision');
      expect(request.headers['Authorization'], 'Bearer token');
      expect(jsonDecode(request.body), {
        'kind': 'food_log_edit',
        'payload': _edit.toJson(),
      });
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'status': 'pending',
            'proposalId': 'revision-1',
            'humanMessage': 'Review this correction in Hustl.',
            'proposal': _proposalJson('food_log_edit'),
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

    final result = await api.proposeFoodLogEdit(_edit);

    expect(result.status, 'pending');
    expect(result.proposalId, 'revision-1');
    expect(result.requiresHumanReview, isTrue);
    expect(result.proposal.isFoodLogEdit, isTrue);
    expect(result.proposal.proposedFoodLogRevision?.targetEntryId, _entryId);
  });

  test('app API posts an exact review-only food delete', () async {
    final client = MockClient((request) async {
      expect(jsonDecode(request.body), {
        'kind': 'food_log_delete',
        'payload': _delete.toJson(),
      });
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'status': 'pending',
            'proposalId': 'revision-1',
            'proposal': _proposalJson('food_log_delete'),
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

    final result = await api.proposeFoodLogDelete(_delete);

    expect(result.status, 'pending');
    expect(result.proposal.isFoodLogDelete, isTrue);
    expect(result.proposal.proposedFoodLogRevision?.isDelete, isTrue);
  });

  test('app API maps a missing target to a focused domain result', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'success': false,
          'error': {'code': 'not_found', 'message': 'Food log entry not found'},
        }),
        404,
        headers: {'content-type': 'application/json'},
      ),
    );
    final api = ProposalsApi(
      client: client,
      baseUrl: 'https://example.com',
      tokens: _FakeTokenStorage(),
    );

    await expectLater(
      api.proposeFoodLogEdit(_edit),
      throwsA(isA<FoodLogRevisionTargetUnavailable>()),
    );
  });

  test('app API preserves shared proposal-limit codes', () async {
    for (final code in ['proposal_rate_limited', 'pending_cap_exceeded']) {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': false,
            'error': {'code': code, 'message': 'Proposal limit reached.'},
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
        api.proposeFoodLogDelete(_delete),
        throwsA(
          isA<ProposalUnavailable>().having(
            (error) => error.code,
            'code',
            code,
          ),
        ),
      );
    }
  });

  test(
    'demo creates and replays review-only revisions without pre-approval writes',
    () async {
      final anchor = DateTime(2026, 8, 29);
      final foodLogs = DemoFoodLogRepository(anchor: anchor);
      final repository = DemoProposalsRepository(
        anchor: anchor,
        foodLogRepository: foodLogs,
      );
      const targetId = '11111111-1111-4111-8111-111111111111';
      const editInput = FoodLogEditProposalInput(
        targetEntryId: targetId,
        changes: FoodLogRevisionChanges(servingGrams: 200, calories: 330),
      );
      const deleteInput = FoodLogDeleteProposalInput(targetEntryId: targetId);
      final baseline = foodLogs.findEntry(targetId);

      final edit = await repository.proposeFoodLogEdit(editInput);
      final editReplay = await repository.proposeFoodLogEdit(editInput);
      final remove = await repository.proposeFoodLogDelete(deleteInput);
      final removeReplay = await repository.proposeFoodLogDelete(deleteInput);

      expect(edit.status, 'pending');
      expect(editReplay.status, 'duplicate');
      expect(editReplay.proposalId, edit.proposalId);
      expect(remove.status, 'pending');
      expect(removeReplay.status, 'duplicate');
      expect(removeReplay.proposalId, remove.proposalId);
      expect(edit.proposal.isFoodLogEdit, isTrue);
      expect(remove.proposal.isFoodLogDelete, isTrue);
      expect(foodLogs.findEntry(targetId), baseline);
    },
  );
}
