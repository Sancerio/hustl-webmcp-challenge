import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';

void main() {
  group('WorkoutSet serialization', () {
    test('toMap stores set type name and round-trips', () {
      const set = WorkoutSet(
        id: '1',
        weight: 100,
        reps: 5,
        setType: SetType.failure,
      );
      final map = set.toMap();
      expect(map['setType'], 'failure');
      final from = WorkoutSet.fromMap(map);
      expect(from.setType, SetType.failure);
    });

    test('parseSetType handles various inputs', () {
      expect(WorkoutSet.parseSetType('warmup'), SetType.warmup);
      expect(WorkoutSet.parseSetType(2), SetType.failure);
      expect(WorkoutSet.parseSetType('unknown'), SetType.regular);
      expect(WorkoutSet.parseSetType(99), SetType.regular);
      expect(WorkoutSet.parseSetType(null), SetType.regular);
    });
  });

  group('WorkoutSet rpe', () {
    const base = WorkoutSet(id: '1', weight: 100, reps: 5, rpe: 8);

    test('toMap/fromMap round-trips rpe', () {
      final from = WorkoutSet.fromMap(base.toMap());
      expect(from.rpe, 8);
    });

    test('fromMap coerces a numeric (double) rpe to int', () {
      final from = WorkoutSet.fromMap({
        'id': '1',
        'weight': 100,
        'reps': 5,
        'rpe': 7.0,
      });
      expect(from.rpe, 7);
    });

    test('fromMap tolerates a missing rpe', () {
      final from = WorkoutSet.fromMap({'id': '1', 'weight': 100, 'reps': 5});
      expect(from.rpe, isNull);
    });

    test('copyWith preserves rpe when omitted', () {
      expect(base.copyWith(reps: 6).rpe, 8);
    });

    test('copyWith sets a new rpe', () {
      expect(base.copyWith(rpe: 10).rpe, 10);
    });

    test('copyWith clears rpe when passed explicit null', () {
      expect(base.copyWith(rpe: null).rpe, isNull);
    });
  });
}
