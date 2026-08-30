import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hustl_app/core/services/token_storage.dart' as token;
import 'package:hustl_app/features/ai_proposals/data/datasources/proposals_api.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/starter_proposal_result.dart';

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

Map<String, dynamic> _proposalDto() => {
  'id': 'p1',
  'kind': 'template_create',
  'status': 'pending',
  'templateName': 'Push Day',
  'exerciseCount': 4,
  'createdAt': '2026-06-27T00:00:00.000Z',
  'proposedExercises': [
    {'exerciseId': 'Bench Press', 'sets': 3, 'restTimerSeconds': 90},
  ],
};

Future<StarterProposalResult> _run({
  required int statusCode,
  required Map<String, dynamic> body,
}) async {
  final client = MockClient((req) async {
    expect(req.method, 'POST');
    expect(req.url.path, '/api/proposals/starter');
    expect(req.headers['Authorization'], 'Bearer token');
    return http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  });
  final api = ProposalsApi(
    client: client,
    baseUrl: 'https://example.com',
    tokens: _FakeTokenStorage(),
  );
  return api.generateStarter();
}

void main() {
  group('ProposalsApi.generateStarter envelope parsing', () {
    test(
      'status=pending → StarterProposalCreated with the full proposal',
      () async {
        final result = await _run(
          statusCode: 201,
          body: {
            'success': true,
            'data': {
              'status': 'pending',
              'proposalId': 'p1',
              'approveDeepLink': 'hustl://proposal/p1',
              'humanMessage': "Here's a starter plan.",
              'summary': 'Create "Push Day" — 4 exercises',
              'proposal': _proposalDto(),
              'training': {'completedWorkouts': 3, 'loggedSets': 24},
            },
          },
        );

        expect(result, isA<StarterProposalCreated>());
        final created = result as StarterProposalCreated;
        expect(created.isDuplicate, isFalse);
        expect(created.proposalId, 'p1');
        expect(created.proposal.templateName, 'Push Day');
        expect(created.proposal.proposedExercises.single.name, 'Bench Press');
        expect(created.approveDeepLink, 'hustl://proposal/p1');
        expect(created.completedWorkouts, 3);
        expect(created.loggedSets, 24);
      },
    );

    test(
      'status=duplicate → StarterProposalDuplicate (still carries proposal)',
      () async {
        final result = await _run(
          statusCode: 200,
          body: {
            'success': true,
            'data': {
              'status': 'duplicate',
              'proposalId': 'p1',
              'proposal': _proposalDto(),
              'training': {'completedWorkouts': 3, 'loggedSets': 24},
            },
          },
        );

        expect(result, isA<StarterProposalDuplicate>());
        final dup = result as StarterProposalDuplicate;
        expect(dup.isDuplicate, isTrue);
        expect(dup.proposal.templateName, 'Push Day');
      },
    );

    test(
      'status=not_enough_data → StarterProposalNotEnoughData with reason',
      () async {
        final result = await _run(
          statusCode: 200,
          body: {
            'success': true,
            'data': {
              'status': 'not_enough_data',
              'reason': 'no_completed_workouts',
              'humanMessage': 'Keep logging.',
              'required': {'completedWorkouts': 1, 'loggedSets': 3},
              'training': {'completedWorkouts': 0, 'loggedSets': 0},
            },
          },
        );

        expect(result, isA<StarterProposalNotEnoughData>());
        final n = result as StarterProposalNotEnoughData;
        expect(n.reason, 'no_completed_workouts');
        expect(n.requiredCompletedWorkouts, 1);
        expect(n.requiredLoggedSets, 3);
      },
    );

    test(
      '401 auth error → StarterProposalError with the parsed code',
      () async {
        final result = await _run(
          statusCode: 401,
          body: {
            'success': false,
            'error': {'code': 'unauthorized', 'message': 'Sign in again'},
          },
        );

        expect(result, isA<StarterProposalError>());
        final e = result as StarterProposalError;
        expect(e.code, 'unauthorized');
        expect(e.message, 'Sign in again');
      },
    );

    test('429 pending_cap_exceeded → StarterProposalError', () async {
      final result = await _run(
        statusCode: 429,
        body: {
          'success': false,
          'error': {
            'code': 'pending_cap_exceeded',
            'message': 'Too many pending proposals',
          },
        },
      );

      expect(result, isA<StarterProposalError>());
      expect((result as StarterProposalError).code, 'pending_cap_exceeded');
    });

    test('500 starter_failed → StarterProposalError', () async {
      final result = await _run(
        statusCode: 500,
        body: {
          'success': false,
          'error': {'code': 'starter_failed', 'message': 'Server error'},
        },
      );

      expect(result, isA<StarterProposalError>());
      expect((result as StarterProposalError).code, 'starter_failed');
    });
  });
}
