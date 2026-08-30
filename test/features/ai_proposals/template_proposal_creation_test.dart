import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hustl_app/app/demo/demo_proposals_repository.dart';
import 'package:hustl_app/app/demo/demo_template_repository.dart';
import 'package:hustl_app/core/services/token_storage.dart' as token;
import 'package:hustl_app/features/ai_proposals/data/datasources/proposals_api.dart';
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

const _plan = TemplateProposalPlan(
  name: 'Lower strength',
  description: 'A compact lower-body session.',
  exercises: [
    TemplateProposalExercise(
      exerciseId: 'Hack Squat',
      slug: 'hack-squat',
      sets: 4,
      repsTarget: 8,
      restTimerSeconds: 150,
      weightTarget: 120,
      rpeTarget: 8,
      notes: 'Controlled eccentric.',
    ),
  ],
);

Map<String, Object?> _proposalJson({
  required String id,
  required String kind,
  String? targetTemplateId,
}) => {
  'id': id,
  'kind': kind,
  'status': 'pending',
  'templateName': _plan.name,
  'exerciseCount': 1,
  if (targetTemplateId != null) 'targetTemplateId': targetTemplateId,
  'summary': 'Create "Lower strength" — 1 exercise',
  'createdAt': '2026-08-28T00:00:00.000Z',
  'proposedExercises': _plan.exercises
      .map((exercise) => exercise.toJson())
      .toList(),
  'resolvedExercisesAsOfProposal': [],
};

void main() {
  test(
    'app API posts exact template-create input and parses pending detail',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/proposals/template');
        expect(request.headers['Authorization'], 'Bearer token');
        expect(jsonDecode(request.body), {
          'kind': 'template_create',
          'plan': _plan.toJson(),
        });
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'status': 'pending',
              'proposalId': 'template-1',
              'proposal': _proposalJson(
                id: 'template-1',
                kind: 'template_create',
              ),
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

      final result = await api.proposeTemplate(_plan);

      expect(result.status, 'pending');
      expect(result.proposalId, 'template-1');
      expect(result.proposal.proposedExercises.single.name, 'Hack Squat');
    },
  );

  test('app API posts route-derived template edit target', () async {
    final client = MockClient((request) async {
      expect(jsonDecode(request.body), {
        'kind': 'template_edit',
        'targetTemplateId': 'visible-template',
        'baseUpdatedAt': '2026-08-28T00:00:00.000Z',
        'plan': _plan.toJson(),
      });
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'status': 'pending',
            'proposalId': 'edit-1',
            'proposal': _proposalJson(
              id: 'edit-1',
              kind: 'template_edit',
              targetTemplateId: 'visible-template',
            ),
          },
        }),
        201,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = ProposalsApi(
      client: client,
      baseUrl: 'https://example.com',
      tokens: _FakeTokenStorage(),
    );

    final result = await api.proposeTemplateEdit(
      'visible-template',
      DateTime.utc(2026, 8, 28),
      _plan,
    );

    expect(result.proposal.targetTemplateId, 'visible-template');
  });

  test('app API maps a stale template version to a domain conflict', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'success': false,
          'error': {
            'code': 'template_changed',
            'message': 'Template changed after it was read.',
          },
        }),
        409,
        headers: {'content-type': 'application/json'},
      ),
    );
    final api = ProposalsApi(
      client: client,
      baseUrl: 'https://example.com',
      tokens: _FakeTokenStorage(),
    );

    await expectLater(
      api.proposeTemplateEdit(
        'visible-template',
        DateTime.utc(2026, 8, 28),
        _plan,
      ),
      throwsA(isA<TemplateProposalConflict>()),
    );
  });

  test(
    'app API preserves authoritative template proposal limit codes',
    () async {
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
          api.proposeTemplateEdit(
            'visible-template',
            DateTime.utc(2026, 8, 28),
            _plan,
          ),
          throwsA(
            isA<TemplateProposalUnavailable>().having(
              (error) => error.code,
              'code',
              code,
            ),
          ),
        );
      }
    },
  );

  test(
    'demo creates and replays review-only templates without pre-approval writes',
    () async {
      final anchor = DateTime(2026, 8, 28);
      final templates = DemoTemplateRepository(anchor: anchor);
      final repository = DemoProposalsRepository(
        anchor: anchor,
        templateRepository: templates,
      );
      const targetId = 'demo-template-push';
      final baseline = await templates.getWorkoutTemplate(targetId);
      final baseUpdatedAt = baseline!.updatedAt;

      final created = await repository.proposeTemplate(_plan);
      final createReplay = await repository.proposeTemplate(_plan);
      final edited = await repository.proposeTemplateEdit(
        targetId,
        baseUpdatedAt,
        _plan,
      );
      final editReplay = await repository.proposeTemplateEdit(
        targetId,
        baseUpdatedAt,
        _plan,
      );

      expect(created.status, 'pending');
      expect(createReplay.status, 'duplicate');
      expect(createReplay.proposalId, created.proposalId);
      expect(edited.status, 'pending');
      expect(editReplay.status, 'duplicate');
      expect(editReplay.proposalId, edited.proposalId);
      expect(edited.proposal.targetTemplateId, targetId);
      expect(await templates.getWorkoutTemplate(targetId), same(baseline));
    },
  );
}
