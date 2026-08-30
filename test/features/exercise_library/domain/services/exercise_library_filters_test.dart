import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/exercise_library/domain/services/exercise_library_filters.dart';

void main() {
  test('Abs filter matches Abdominals muscle labels', () {
    const exercise = Exercise(name: 'Crunch', muscles: ['Abdominals']);

    expect(matchesExerciseLibraryFilter(exercise, 'Abs'), isTrue);
  });

  test(
    'Obliques filter matches catalog exercises named with oblique variants',
    () {
      const obliqueCrunch = Exercise(
        name: 'Oblique Crunch',
        muscles: ['Abdominals'],
      );
      const crunch = Exercise(name: 'Crunch', muscles: ['Abdominals']);

      expect(matchesExerciseLibraryFilter(obliqueCrunch, 'Obliques'), isTrue);
      expect(matchesExerciseLibraryFilter(obliqueCrunch, 'Oblique'), isTrue);
      expect(matchesExerciseLibraryFilter(crunch, 'Obliques'), isFalse);
    },
  );

  test('Core filter stays broad across abs and oblique variants', () {
    const upperAbs = Exercise(
      name: 'Hanging Knee Raise',
      muscles: ['Upper Abs'],
    );
    const oblique = Exercise(name: 'Side Bend', muscles: ['Obliques']);

    expect(matchesExerciseLibraryFilter(upperAbs, 'Core'), isTrue);
    expect(matchesExerciseLibraryFilter(oblique, 'Core'), isTrue);
  });
}
