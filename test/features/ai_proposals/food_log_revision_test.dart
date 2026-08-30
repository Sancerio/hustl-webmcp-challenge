import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_detail.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_summary.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposed_food_log_revision.dart';
import 'package:hustl_app/features/ai_proposals/presentation/widgets/proposal_food_log_revision_view.dart';

void main() {
  group('ProposalKind parsing + getters', () {
    test('parses the revision kinds and groups them under the food diary', () {
      expect(proposalKindFromString('food_log_edit'), ProposalKind.foodLogEdit);
      expect(
        proposalKindFromString('food_log_delete'),
        ProposalKind.foodLogDelete,
      );

      final edit = ProposalSummary.fromJson(const {
        'id': 'p1',
        'kind': 'food_log_edit',
      });
      expect(edit.isFoodLogEdit, isTrue);
      expect(edit.isFoodLogRevision, isTrue);
      expect(edit.touchesFoodDiary, isTrue);
      // A revision is a log kind (revertible) but NOT a plain food add.
      expect(edit.isLog, isTrue);
      expect(edit.isFoodLog, isFalse);

      final del = ProposalSummary.fromJson(const {
        'id': 'p2',
        'kind': 'food_log_delete',
      });
      expect(del.isFoodLogDelete, isTrue);
      expect(del.touchesFoodDiary, isTrue);
    });
  });

  group('ProposedFoodLogRevision.fromJson', () {
    test('edit surfaces the changed field as a before→after diff, first', () {
      final rev = ProposedFoodLogRevision.fromJson(const {
        'targetEntryId': 'e1',
        'target': {
          'foodName': 'Chicken',
          'date': '2026-06-27',
          'servingGrams': 300,
          'calories': 495,
          'proteinGrams': 90,
          'carbsGrams': 0,
          'fatGrams': 11,
        },
        'changes': {'calories': 330, 'servingGrams': 200},
      }, isDelete: false)!;

      expect(rev.isDelete, isFalse);
      expect(rev.foodName, 'Chicken');
      expect(rev.date, isNotNull);
      // Changed fields are sorted to the front.
      final changed = rev.changes.where((c) => c.changed).toList();
      expect(changed.map((c) => c.label), containsAll(['Calories', 'Portion']));
      final cal = rev.changes.firstWhere((c) => c.label == 'Calories');
      expect(cal.from, '495 kcal');
      expect(cal.to, '330 kcal');
      // An untouched field has no "to".
      final protein = rev.changes.firstWhere((c) => c.label == 'Protein');
      expect(protein.changed, isFalse);
    });

    test('edit rename produces a Name row', () {
      final rev = ProposedFoodLogRevision.fromJson(const {
        'targetEntryId': 'e1',
        'target': {'foodName': 'Chiken', 'calories': 200},
        'changes': {'foodName': 'Chicken'},
      }, isDelete: false)!;
      expect(rev.foodName, 'Chicken');
      final name = rev.changes.firstWhere((c) => c.label == 'Name');
      expect(name.from, 'Chiken');
      expect(name.to, 'Chicken');
    });

    test(
      'a changed micro (sodium) is always shown so nothing is approved unseen',
      () {
        final rev = ProposedFoodLogRevision.fromJson(const {
          'targetEntryId': 'e1',
          'target': {'foodName': 'Soup', 'calories': 120, 'sodiumMg': 800},
          'changes': {'sodiumMg': 400},
        }, isDelete: false)!;
        final sodium = rev.changes.firstWhere((c) => c.label == 'Sodium');
        expect(sodium.changed, isTrue);
        expect(sodium.from, '800 mg');
        expect(sodium.to, '400 mg');
        // The changed field sorts to the front.
        expect(rev.changes.first.label, 'Sodium');
      },
    );

    test('absent, unchanged micros are omitted (no noise)', () {
      final rev = ProposedFoodLogRevision.fromJson(const {
        'targetEntryId': 'e1',
        'target': {'foodName': 'Rice', 'calories': 200},
        'changes': {'calories': 180},
      }, isDelete: false)!;
      // fiber/sugar/sodium are null and unchanged → not rendered.
      expect(rev.changes.any((c) => c.label == 'Fiber'), isFalse);
      expect(rev.changes.any((c) => c.label == 'Sodium'), isFalse);
      // ...but core macros still show.
      expect(rev.changes.any((c) => c.label == 'Calories'), isTrue);
    });

    test('delete carries the target name + calories and no diff rows', () {
      final rev = ProposedFoodLogRevision.fromJson(const {
        'targetEntryId': 'e9',
        'target': {'foodName': 'Protein shake', 'calories': 180},
      }, isDelete: true)!;
      expect(rev.isDelete, isTrue);
      expect(rev.foodName, 'Protein shake');
      expect(rev.currentCalories, 180);
      expect(rev.changes, isEmpty);
    });
  });

  group('ProposalFoodLogRevisionView layout', () {
    testWidgets('a long rename wraps instead of overflowing a narrow screen', (
      tester,
    ) async {
      final longName = 'Grilled chicken breast with herbs ' * 6; // ~200 chars
      final detail = ProposalDetail.fromJson({
        'id': 'p1',
        'kind': 'food_log_edit',
        'proposedPayload': {
          'targetEntryId': 'e1',
          'target': const {'foodName': 'Chicken', 'calories': 200},
          'changes': {'foodName': longName},
        },
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320, // a narrow phone width
              child: SingleChildScrollView(
                child: ProposalFoodLogRevisionView(detail: detail),
              ),
            ),
          ),
        ),
      );

      // The old horizontal Row would throw a RenderFlex overflow here.
      expect(tester.takeException(), isNull);
    });
  });

  group('ProposalDetail.fromJson', () {
    test('routes a revision payload into proposedFoodLogRevision only', () {
      final detail = ProposalDetail.fromJson(const {
        'id': 'p1',
        'kind': 'food_log_delete',
        'proposedPayload': {
          'targetEntryId': 'e1',
          'target': {'foodName': 'Soda', 'calories': 140},
        },
      });
      expect(detail.isFoodLogRevision, isTrue);
      expect(detail.proposedFoodLogRevision, isNotNull);
      expect(detail.proposedFoodLog, isNull);
      expect(detail.proposedFoodLogRevision!.isDelete, isTrue);
    });
  });
}
