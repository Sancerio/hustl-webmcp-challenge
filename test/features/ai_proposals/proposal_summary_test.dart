import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_summary.dart';

Map<String, dynamic> _json({
  required String kind,
  required String status,
  String? decidedAt,
}) {
  return {
    'id': 'p1',
    'kind': kind,
    'status': status,
    'templateName': 'Some entry',
    'exerciseCount': 0,
    'createdAt': '2026-07-01T10:00:00Z',
    'decidedAt': decidedAt,
  };
}

void main() {
  group('ProposalSummary.fromJson', () {
    test('parses decidedAt when present', () {
      final summary = ProposalSummary.fromJson(
        _json(
          kind: 'food_log',
          status: 'applied',
          decidedAt: '2026-07-02T09:30:00Z',
        ),
      );
      expect(summary.decidedAt, isNotNull);
      expect(summary.decidedAt!.toUtc(), DateTime.utc(2026, 7, 2, 9, 30));
    });

    test('decidedAt is null when absent', () {
      final summary = ProposalSummary.fromJson(
        _json(kind: 'food_log', status: 'pending'),
      );
      expect(summary.decidedAt, isNull);
    });
  });

  group('ProposalSummary.isRevertable', () {
    test('true for an applied log kind (food_log)', () {
      final summary = ProposalSummary.fromJson(
        _json(kind: 'food_log', status: 'applied'),
      );
      expect(summary.isRevertable, isTrue);
    });

    test('true for an applied workout_log', () {
      final summary = ProposalSummary.fromJson(
        _json(kind: 'workout_log', status: 'applied'),
      );
      expect(summary.isRevertable, isTrue);
    });

    test('true for an applied food_log_edit/food_log_delete', () {
      final edit = ProposalSummary.fromJson(
        _json(kind: 'food_log_edit', status: 'applied'),
      );
      final delete = ProposalSummary.fromJson(
        _json(kind: 'food_log_delete', status: 'applied'),
      );
      expect(edit.isRevertable, isTrue);
      expect(delete.isRevertable, isTrue);
    });

    test('false for an applied nutrition_targets proposal', () {
      final summary = ProposalSummary.fromJson(
        _json(kind: 'nutrition_targets', status: 'applied'),
      );
      expect(summary.isRevertable, isFalse);
    });

    test('false for an applied template_create/template_edit proposal', () {
      final create = ProposalSummary.fromJson(
        _json(kind: 'template_create', status: 'applied'),
      );
      final edit = ProposalSummary.fromJson(
        _json(kind: 'template_edit', status: 'applied'),
      );
      expect(create.isRevertable, isFalse);
      expect(edit.isRevertable, isFalse);
    });

    test('false once reverted, even for a log kind', () {
      final summary = ProposalSummary.fromJson(
        _json(kind: 'food_log', status: 'reverted'),
      );
      expect(summary.isRevertable, isFalse);
    });

    test('false when rejected', () {
      final summary = ProposalSummary.fromJson(
        _json(kind: 'workout_log', status: 'rejected'),
      );
      expect(summary.isRevertable, isFalse);
    });
  });
}
