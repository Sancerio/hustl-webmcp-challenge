import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';

void main() {
  const exercise = Exercise(name: 'Back Squat', muscles: ['quads']);

  WorkoutExercise base({String? groupId, int? order}) => WorkoutExercise(
    id: 'we1',
    exercise: exercise,
    sets: const [],
    supersetGroupId: groupId,
    supersetOrder: order,
  );

  group('WorkoutExercise superset fields', () {
    test('default to null (legacy flat behavior)', () {
      const ex = WorkoutExercise(id: 'x', exercise: exercise, sets: []);
      expect(ex.supersetGroupId, isNull);
      expect(ex.supersetOrder, isNull);
    });

    test('toMap emits snake_case keys', () {
      final map = base(groupId: 'g1', order: 2).toMap();
      expect(map['superset_group_id'], 'g1');
      expect(map['superset_order'], 2);
    });

    test('fromMap tolerates missing keys -> null', () {
      final map = base().toMap()
        ..remove('superset_group_id')
        ..remove('superset_order');
      final restored = WorkoutExercise.fromMap(map, exercise);
      expect(restored.supersetGroupId, isNull);
      expect(restored.supersetOrder, isNull);
    });

    test('round-trips through toMap/fromMap', () {
      final original = base(groupId: 'g1', order: 1);
      final restored = WorkoutExercise.fromMap(original.toMap(), exercise);
      expect(restored.supersetGroupId, 'g1');
      expect(restored.supersetOrder, 1);
      expect(restored, original);
    });

    test('copyWith preserves fields when not specified', () {
      final original = base(groupId: 'g1', order: 1);
      final copy = original.copyWith(notes: 'hi');
      expect(copy.supersetGroupId, 'g1');
      expect(copy.supersetOrder, 1);
    });

    test('copyWith can clear group back to null via sentinel', () {
      final grouped = base(groupId: 'g1', order: 1);
      final cleared = grouped.copyWith(
        supersetGroupId: null,
        supersetOrder: null,
      );
      expect(cleared.supersetGroupId, isNull);
      expect(cleared.supersetOrder, isNull);
    });

    test('equality and hashCode account for grouping', () {
      expect(
        base(groupId: 'g1', order: 0),
        isNot(base(groupId: 'g2', order: 0)),
      );
      expect(
        base(groupId: 'g1', order: 0).hashCode,
        base(groupId: 'g1', order: 0).hashCode,
      );
    });
  });
}
