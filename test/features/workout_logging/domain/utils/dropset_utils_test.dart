import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/utils/dropset_utils.dart';

WorkoutSet _set(String id, {String? parent, int? dropIndex, SetType? type}) {
  return WorkoutSet(
    id: id,
    weight: 20,
    reps: 8,
    setType: type ?? (parent != null ? SetType.dropset : SetType.regular),
    parentSetId: parent,
    dropIndex: dropIndex,
  );
}

void main() {
  group('suggestedDropWeight', () {
    test(
      'drops ~15% and rounds to a plate-friendly value below the parent',
      () {
        // 100 - 15% = 85 → already a 2.5 multiple.
        expect(DropsetUtils.suggestedDropWeight(100), 85);
        // 60 - 15% = 51 → floors to 50.
        expect(DropsetUtils.suggestedDropWeight(60), 50);
      },
    );

    test('always returns strictly less than the parent magnitude', () {
      for (final w in [2.5, 5.0, 7.5, 10.0, 12.5]) {
        final drop = DropsetUtils.suggestedDropWeight(w);
        expect(drop, lessThan(w), reason: 'drop of $w must be lighter');
        expect(drop, greaterThanOrEqualTo(0));
      }
    });

    test('keeps the sign for assisted (negative) loads', () {
      final drop = DropsetUtils.suggestedDropWeight(-100);
      expect(drop, isNegative);
      expect(drop.abs(), lessThan(100));
    });

    test('zero parent weight passes through', () {
      expect(DropsetUtils.suggestedDropWeight(0), 0);
    });
  });

  group('renumberDrops', () {
    test(
      're-derives contiguous 1-based dropIndex per parent in list order',
      () {
        final sets = [
          _set('p1'),
          _set('d1', parent: 'p1', dropIndex: 5),
          _set('d2', parent: 'p1', dropIndex: 9),
          _set('p2'),
          _set('d3', parent: 'p2', dropIndex: 2),
        ];
        final out = DropsetUtils.renumberDrops(sets);
        expect(out[1].dropIndex, 1);
        expect(out[2].dropIndex, 2);
        expect(out[4].dropIndex, 1);
        // Working sets untouched.
        expect(out[0].parentSetId, isNull);
        expect(out[3].parentSetId, isNull);
      },
    );

    test('closes the gap left by a deleted middle drop', () {
      final sets = [
        _set('p1'),
        _set('d1', parent: 'p1', dropIndex: 1),
        _set('d3', parent: 'p1', dropIndex: 3),
      ];
      final out = DropsetUtils.renumberDrops(sets);
      expect(out[1].dropIndex, 1);
      expect(out[2].dropIndex, 2);
    });
  });

  group('dropsFor', () {
    test('returns only drops linked to the given parent, in list order', () {
      final sets = [
        _set('p1'),
        _set('d1', parent: 'p1', dropIndex: 1),
        _set('p2'),
        _set('d2', parent: 'p2', dropIndex: 1),
        _set('d3', parent: 'p1', dropIndex: 2),
      ];
      final drops = DropsetUtils.dropsFor(sets, 'p1');
      expect(drops.map((d) => d.id), ['d1', 'd3']);
    });
  });
}
