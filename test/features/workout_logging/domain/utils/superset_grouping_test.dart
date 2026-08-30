import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/utils/superset_grouping.dart';

WorkoutExercise _ex(String id, {String? groupId, int? order}) {
  return WorkoutExercise(
    id: id,
    exercise: Exercise(name: 'Ex $id', muscles: const []),
    sets: const [],
    supersetGroupId: groupId,
    supersetOrder: order,
  );
}

void main() {
  group('SupersetKind', () {
    test('derives kind from member count with sentence-case labels', () {
      expect(SupersetKind.fromMemberCount(2), SupersetKind.superset);
      expect(SupersetKind.fromMemberCount(3), SupersetKind.giantSet);
      expect(SupersetKind.fromMemberCount(4), SupersetKind.circuit);
      expect(SupersetKind.fromMemberCount(7), SupersetKind.circuit);
      expect(SupersetKind.superset.label, 'Superset');
      expect(SupersetKind.giantSet.label, 'Giant set');
      expect(SupersetKind.circuit.label, 'Circuit');
    });

    test('clamps degenerate counts to superset', () {
      expect(SupersetKind.fromMemberCount(1), SupersetKind.superset);
      expect(SupersetKind.fromMemberCount(0), SupersetKind.superset);
    });
  });

  group('groupsFor', () {
    test('returns empty for an all-ungrouped (legacy) list', () {
      final exercises = [_ex('a'), _ex('b'), _ex('c')];
      expect(SupersetGrouping.groupsFor(exercises), isEmpty);
    });

    test('buckets a contiguous 2-member group as a superset', () {
      final exercises = [
        _ex('a', groupId: 'g1', order: 0),
        _ex('b', groupId: 'g1', order: 1),
        _ex('c'),
      ];
      final groups = SupersetGrouping.groupsFor(exercises);
      expect(groups, hasLength(1));
      expect(groups.first.groupId, 'g1');
      expect(groups.first.kind, SupersetKind.superset);
      expect(groups.first.members.map((m) => m.id), ['a', 'b']);
      expect(groups.first.colorIndex, 0);
    });

    test('sorts members by supersetOrder (nulls last)', () {
      final exercises = [
        _ex('a', groupId: 'g1', order: 2),
        _ex('b', groupId: 'g1', order: null),
        _ex('c', groupId: 'g1', order: 0),
      ];
      final groups = SupersetGrouping.groupsFor(exercises);
      expect(groups.single.members.map((m) => m.id), ['c', 'a', 'b']);
      expect(groups.single.kind, SupersetKind.giantSet);
    });

    test('classifies 4+ members as a circuit', () {
      final exercises = [
        for (var i = 0; i < 4; i++) _ex('m$i', groupId: 'g1', order: i),
      ];
      expect(
        SupersetGrouping.groupsFor(exercises).single.kind,
        SupersetKind.circuit,
      );
    });

    test('does not surface a lone-member group', () {
      final exercises = [_ex('a', groupId: 'g1', order: 0), _ex('b')];
      expect(SupersetGrouping.groupsFor(exercises), isEmpty);
    });

    test('treats non-contiguous same-id runs as separate groups', () {
      final exercises = [
        _ex('a', groupId: 'g1', order: 0),
        _ex('b', groupId: 'g1', order: 1),
        _ex('c'),
        _ex('d', groupId: 'g1', order: 0),
        _ex('e', groupId: 'g1', order: 1),
      ];
      final groups = SupersetGrouping.groupsFor(exercises);
      expect(groups, hasLength(2));
      expect(groups[0].members.map((m) => m.id), ['a', 'b']);
      expect(groups[1].members.map((m) => m.id), ['d', 'e']);
    });

    test('cycles colorIndex across the palette by appearance order', () {
      final exercises = <WorkoutExercise>[];
      for (var g = 0; g < SupersetGrouping.paletteSize + 1; g++) {
        exercises.add(_ex('${g}a', groupId: 'g$g', order: 0));
        exercises.add(_ex('${g}b', groupId: 'g$g', order: 1));
      }
      final groups = SupersetGrouping.groupsFor(exercises);
      expect(groups, hasLength(SupersetGrouping.paletteSize + 1));
      expect(groups.first.colorIndex, 0);
      // Wraps back to 0 after exhausting the palette.
      expect(groups.last.colorIndex, 0);
    });
  });

  group('lookups', () {
    final exercises = [
      _ex('a', groupId: 'g1', order: 0),
      _ex('b', groupId: 'g1', order: 1),
      _ex('c', groupId: 'g1', order: 2),
      _ex('solo'),
    ];

    test('groupForExercise finds the owning group or null', () {
      expect(SupersetGrouping.groupForExercise(exercises, 'b')?.groupId, 'g1');
      expect(SupersetGrouping.groupForExercise(exercises, 'solo'), isNull);
      expect(SupersetGrouping.groupForExercise(exercises, 'missing'), isNull);
    });

    test('isGrouped reflects membership', () {
      expect(SupersetGrouping.isGrouped(exercises, 'a'), isTrue);
      expect(SupersetGrouping.isGrouped(exercises, 'solo'), isFalse);
    });

    test('nextMemberId walks round order and wraps', () {
      expect(SupersetGrouping.nextMemberId(exercises, 'a'), 'b');
      expect(SupersetGrouping.nextMemberId(exercises, 'b'), 'c');
      expect(SupersetGrouping.nextMemberId(exercises, 'c'), 'a');
      expect(SupersetGrouping.nextMemberId(exercises, 'solo'), isNull);
    });
  });

  group('memberLetter', () {
    test('maps 0-based index to A, B, C…', () {
      expect(SupersetGrouping.memberLetter(0), 'A');
      expect(SupersetGrouping.memberLetter(1), 'B');
      expect(SupersetGrouping.memberLetter(25), 'Z');
    });

    test('wraps past Z into AA, AB…', () {
      expect(SupersetGrouping.memberLetter(26), 'AA');
      expect(SupersetGrouping.memberLetter(27), 'AB');
    });
  });
}
