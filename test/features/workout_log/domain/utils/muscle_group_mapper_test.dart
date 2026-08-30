import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/workout_log/domain/models/muscle_group.dart';
import 'package:hustl_app/features/workout_log/domain/utils/muscle_group_mapper.dart';

void main() {
  group('figureMuscleGroups', () {
    test('resolves display labels and storage keys to figure groups', () {
      expect(
        figureMuscleGroups(['Chest', 'Triceps', 'Front Delts']),
        containsAll([
          MuscleGroup.middlePecs,
          MuscleGroup.triceps,
          MuscleGroup.frontDelts,
        ]),
      );
      // Storage-style keys resolve too.
      expect(
        figureMuscleGroups(['lower_back', 'lats']),
        containsAll([MuscleGroup.lowerBack, MuscleGroup.lats]),
      );
    });

    test('push / pull / legs produce distinct region sets', () {
      final push = figureMuscleGroups(['Chest', 'Triceps', 'Front Delts']);
      final pull = figureMuscleGroups(['Lats', 'Biceps', 'Mid Back']);
      final legs = figureMuscleGroups(['Quads', 'Glutes', 'Hamstrings']);

      // Each split highlights its own region, so the thumbnails differ.
      expect(push.intersection(legs), isEmpty);
      expect(pull.contains(MuscleGroup.lats), isTrue);
      expect(legs.contains(MuscleGroup.quads), isTrue);
      expect(push.contains(MuscleGroup.middlePecs), isTrue);
    });

    test('drops blank and unmappable labels', () {
      expect(figureMuscleGroups(['', '   ']), isEmpty);
      expect(
        figureMuscleGroups(['Quads', 'Definitely Not A Muscle']),
        equals({MuscleGroup.quads}),
      );
    });
  });
}
