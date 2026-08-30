import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/onboarding/domain/import_summary.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';

WorkoutSet _set(
  double weight,
  int reps, {
  SetType type = SetType.regular,
  bool completed = true,
}) {
  return WorkoutSet(
    id: 'set-$weight-$reps-${type.name}',
    weight: weight,
    reps: reps,
    setType: type,
    isCompleted: completed,
  );
}

WorkoutExercise _exercise(String name, List<WorkoutSet> sets) {
  return WorkoutExercise(
    id: 'ex-$name',
    exercise: Exercise(name: name, muscles: const []),
    sets: sets,
  );
}

void main() {
  group('ImportSummary.fromSessions', () {
    test('aggregates counts, volume, and date range across sessions', () {
      final sessions = [
        WorkoutSession(
          id: 'a',
          name: 'Upper',
          startTime: DateTime(2023, 1, 15),
          exercises: [
            // 100x5 + 100x5 (regular) = 1000; warmup 60x5 excluded from volume
            // but counted in totalSets.
            _exercise('Bench Press', [
              _set(100, 5),
              _set(100, 5),
              _set(60, 5, type: SetType.warmup),
            ]),
            _exercise('Squat', [_set(200, 5)]), // 1000
          ],
        ),
        WorkoutSession(
          id: 'b',
          name: 'Upper 2',
          startTime: DateTime(2023, 2, 1),
          exercises: [
            // Same exercise, different casing — must de-dupe to one exercise.
            _exercise('bench press', [_set(50, 10)]), // 500
          ],
        ),
      ];

      final summary = ImportSummary.fromSessions(sessions);

      expect(summary.isEmpty, isFalse);
      expect(summary.workouts, 2);
      expect(summary.exercises, 2); // {bench press, squat}
      expect(summary.totalSets, 5); // 3 + 1 + 1
      expect(
        summary.totalVolumeKg,
        2500,
      ); // 1000 + 1000 + 500 (warmup excluded)
      expect(summary.totalVolumeTonnes, closeTo(2.5, 1e-9));
      expect(summary.firstDate, DateTime(2023, 1, 15));
      expect(summary.lastDate, DateTime(2023, 2, 1));
    });

    test('empty session list yields an empty summary', () {
      final summary = ImportSummary.fromSessions(const []);

      expect(summary.isEmpty, isTrue);
      expect(summary.workouts, 0);
      expect(summary.exercises, 0);
      expect(summary.totalSets, 0);
      expect(summary.totalVolumeKg, 0);
      expect(summary.totalVolumeTonnes, 0);
      expect(summary.firstDate, isNull);
      expect(summary.lastDate, isNull);
    });
  });
}
