import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/utils/working_set_count.dart';

void main() {
  const exercise = Exercise(name: 'Leg Extension', muscles: ['quads']);

  // A working set (the dropset parent) plus two lighter, linked drops.
  const parent = WorkoutSet(id: 'p1', weight: 60, reps: 10, isCompleted: true);
  const drop1 = WorkoutSet(
    id: 'd1',
    weight: 50,
    reps: 8,
    isCompleted: true,
    setType: SetType.dropset,
    parentSetId: 'p1',
    dropIndex: 1,
  );
  const drop2 = WorkoutSet(
    id: 'd2',
    weight: 40,
    reps: 6,
    isCompleted: true,
    setType: SetType.dropset,
    parentSetId: 'p1',
    dropIndex: 2,
  );

  group('WorkoutSet dropset linkage fields', () {
    test('default to null (legacy/standalone set)', () {
      const set = WorkoutSet(id: 'x', weight: 100, reps: 5);
      expect(set.parentSetId, isNull);
      expect(set.dropIndex, isNull);
    });

    test('toMap emits snake_case keys', () {
      final map = drop1.toMap();
      expect(map['parent_set_id'], 'p1');
      expect(map['drop_index'], 1);
    });

    test('fromMap tolerates missing keys -> null (back-compat)', () {
      final map = parent.toMap()
        ..remove('parent_set_id')
        ..remove('drop_index');
      final restored = WorkoutSet.fromMap(map);
      expect(restored.parentSetId, isNull);
      expect(restored.dropIndex, isNull);
    });

    test('round-trips through toMap/fromMap', () {
      final restored = WorkoutSet.fromMap(drop2.toMap());
      expect(restored.parentSetId, 'p1');
      expect(restored.dropIndex, 2);
      expect(restored.setType, SetType.dropset);
      expect(restored, equals(drop2));
    });

    test('copyWith preserves linkage when omitted', () {
      final updated = drop1.copyWith(reps: 9);
      expect(updated.parentSetId, 'p1');
      expect(updated.dropIndex, 1);
    });

    test('copyWith can clear linkage back to null (un-link a drop)', () {
      final unlinked = drop1.copyWith(
        parentSetId: null,
        dropIndex: null,
        setType: SetType.regular,
      );
      expect(unlinked.parentSetId, isNull);
      expect(unlinked.dropIndex, isNull);
      expect(unlinked.setType, SetType.regular);
    });

    test('== and hashCode account for linkage', () {
      final relinked = drop1.copyWith(parentSetId: 'other');
      expect(relinked == drop1, isFalse);
      expect(relinked.hashCode == drop1.hashCode, isFalse);
    });
  });

  group('workingSetCount helper', () {
    WorkoutExercise withSets(List<WorkoutSet> sets) =>
        WorkoutExercise(id: 'we1', exercise: exercise, sets: sets);

    test(
      'counts a dropset as ONE working set (drops roll into the parent)',
      () {
        final ex = withSets(const [parent, drop1, drop2]);
        expect(ex.workingSetCount, 1);
        expect(ex.completedWorkingSetCount, 1);
      },
    );

    test('counts multiple working sets, excluding drops', () {
      const setA = WorkoutSet(id: 'a', weight: 60, reps: 10, isCompleted: true);
      const setB = WorkoutSet(id: 'b', weight: 60, reps: 10, isCompleted: true);
      final ex = withSets(const [setA, drop1, setB, drop2]);
      // Two top-level (parentSetId == null) sets; two drops roll in.
      expect(ex.workingSetCount, 2);
    });

    test('legacy sets (no linkage) count exactly like sets.length', () {
      const setA = WorkoutSet(id: 'a', weight: 60, reps: 10);
      const setB = WorkoutSet(id: 'b', weight: 60, reps: 10);
      final ex = withSets(const [setA, setB]);
      expect(ex.workingSetCount, ex.sets.length);
    });

    test('completedWorkingSetCount ignores incomplete working sets', () {
      const done = WorkoutSet(id: 'a', weight: 60, reps: 10, isCompleted: true);
      const pending = WorkoutSet(id: 'b', weight: 60, reps: 10);
      final ex = withSets(const [done, pending]);
      expect(ex.workingSetCount, 2);
      expect(ex.completedWorkingSetCount, 1);
    });
  });

  group('dropset volume', () {
    test('every drop\'s reps DO count toward session volume', () {
      final session = WorkoutSession(
        id: 's1',
        name: 'Drop day',
        startTime: DateTime(2026, 1, 1),
        exercises: const [
          WorkoutExercise(
            id: 'we1',
            exercise: exercise,
            sets: [parent, drop1, drop2],
          ),
        ],
      );
      // 60*10 (parent) + 50*8 (drop1) + 40*6 (drop2) = 600 + 400 + 240 = 1240.
      expect(session.totalVolume, 1240);
    });
  });
}
