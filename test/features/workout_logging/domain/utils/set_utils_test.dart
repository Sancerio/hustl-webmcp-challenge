import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/utils/set_utils.dart';

void main() {
  group('generateEmptySets', () {
    test('preserves previous set types', () {
      const uuid = Uuid();
      const previous = [
        WorkoutSet(id: 'a', weight: 0, reps: 0, setType: SetType.warmup),
        WorkoutSet(id: 'b', weight: 0, reps: 0, setType: SetType.failure),
      ];

      final result = generateEmptySets(2, uuid, previousSets: previous);

      expect(result[0].setType, SetType.warmup);
      expect(result[1].setType, SetType.failure);
    });

    test('defaults to regular when previous set types missing', () {
      const uuid = Uuid();
      final result = generateEmptySets(2, uuid, previousSets: const []);
      expect(result[0].setType, SetType.regular);
      expect(result[1].setType, SetType.regular);
    });

    test('excludes linked drops from the seed template', () {
      const uuid = Uuid();
      // A working set, then a drop linked to it, then another working set.
      // The template must skip the drop so positional set types line up with
      // top-level working sets only — never a stray dropset row.
      const previous = [
        WorkoutSet(id: 'w1', weight: 0, reps: 0, setType: SetType.warmup),
        WorkoutSet(
          id: 'd1',
          weight: 0,
          reps: 0,
          setType: SetType.dropset,
          parentSetId: 'w1',
          dropIndex: 1,
        ),
        WorkoutSet(id: 'w2', weight: 0, reps: 0, setType: SetType.failure),
      ];

      // Seed two working sets: should mirror w1 (warmup) and w2 (failure),
      // never the drop, and never produce a dropset/linked row.
      final result = generateEmptySets(2, uuid, previousSets: previous);
      expect(result[0].setType, SetType.warmup);
      expect(result[1].setType, SetType.failure);
      expect(result.any((s) => s.setType == SetType.dropset), isFalse);
      expect(result.every((s) => s.parentSetId == null), isTrue);
      expect(result.every((s) => s.dropIndex == null), isTrue);
    });
  });
}
