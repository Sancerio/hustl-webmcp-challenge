import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/exercise_library/domain/services/exercise_record_service.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/workout_progress_utils.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';

void main() {
  const service = ExerciseRecordService();
  const weightExercise = Exercise(
    name: 'Bench',
    muscles: ['Chest'],
    kind: ExerciseKind.strength,
  );

  group('Exercise canonical identity', () {
    test('canonicalKeyFrom slugifies provided slug separators', () {
      expect(Exercise.canonicalKeyFrom(slug: 'Wood Chopper '), 'wood-chopper');
      expect(Exercise.canonicalKeyFrom(slug: 'wood_chopper'), 'wood-chopper');
    });

    test('matchesIdentity tolerates slug separator differences', () {
      const libraryExercise = Exercise(
        name: 'Wood Chopper',
        slug: 'wood-chopper',
        muscles: [],
      );
      const storedExercise = Exercise(
        name: 'Wood chopper',
        slug: 'wood chopper',
        muscles: [],
      );

      expect(
        libraryExercise.matchesIdentity(
          name: storedExercise.name,
          slug: storedExercise.slug,
        ),
        isTrue,
      );

      expect(
        storedExercise.matchesIdentity(
          name: libraryExercise.name,
          slug: libraryExercise.slug,
        ),
        isTrue,
      );
    });
  });

  RecordEntry entry(DateTime d, double w, int r) => RecordEntry(
    date: d,
    set: WorkoutSet(id: 'id', weight: w, reps: r, isCompleted: true),
  );

  test('generateChartData day grouping, weight vs 1RM', () {
    final d = DateTime(2024, 1, 10);
    final entries = [entry(d, 100, 5), entry(d, 102, 3)];
    final dayWeight = service.generateChartData(
      entries,
      group: TimeGroup.day,
      useEstimated1Rm: false,
      exercise: weightExercise,
    );
    expect(dayWeight.length, 1);
    expect(dayWeight.values.single, 102);

    final day1rm = service.generateChartData(
      entries,
      group: TimeGroup.day,
      useEstimated1Rm: true,
      exercise: weightExercise,
    );
    expect(day1rm.length, 1);
    final v = day1rm.values.single;
    // 100*(1+5/30) = 116.666..., dominates 102*(1+3/30) ~ 112.2
    expect(v, closeTo(116.666, 0.01));
  });

  test('generateChartData week/month aggregation keys are ordered', () {
    final e1 = entry(DateTime(2024, 1, 1), 100, 5); // Week 01
    final e2 = entry(DateTime(2024, 1, 15), 110, 3); // Week 03
    final week = service.generateChartData(
      [e1, e2],
      group: TimeGroup.week,
      exercise: weightExercise,
    );
    expect(week.keys.first.compareTo(week.keys.last) < 0, isTrue);

    final m1 = entry(DateTime(2024, 2, 1), 100, 5);
    final m2 = entry(DateTime(2024, 3, 1), 120, 1);
    final month = service.generateChartData(
      [m1, m2],
      group: TimeGroup.month,
      exercise: weightExercise,
    );
    expect(month.keys, orderedEquals(['2024-02', '2024-03']));
  });

  test('prMilestoneIndices finds new highs', () {
    final series = LinkedHashMap<String, double>.from({
      'a': 100.0,
      'b': 100.0,
      'c': 105.0,
      'd': 104.0,
      'e': 110.0,
    });
    final idx = service.prMilestoneIndices(series);
    expect(idx, {0, 2, 4});
  });

  group('buildEntries excludes warm-up sets from records', () {
    WorkoutSession sessionWith(List<WorkoutSet> sets) => WorkoutSession(
      id: 'sess',
      name: 'Session',
      startTime: DateTime(2024, 5, 1),
      isCompleted: true,
      exercises: [
        WorkoutExercise(id: 'we', exercise: weightExercise, sets: sets),
      ],
    );

    test('a heavy warm-up never becomes the best record set', () {
      // The warm-up is "heavier" than the working set; without the guard it
      // would win the record (and pollute the Epley estimate). It must not.
      final session = sessionWith(const [
        WorkoutSet(
          id: 'w',
          weight: 200,
          reps: 1,
          setType: SetType.warmup,
          isCompleted: true,
        ),
        WorkoutSet(id: 's', weight: 100, reps: 5, isCompleted: true),
      ]);

      final entries = service.buildEntries([session], weightExercise);
      expect(entries, hasLength(1));
      // Best comes from the working set, not the 200 kg warm-up.
      expect(entries.single.set.weight, 100);
      expect(entries.single.set.reps, 5);
    });

    test('a card with only warm-up sets yields no record entry', () {
      final session = sessionWith(const [
        WorkoutSet(
          id: 'w',
          weight: 80,
          reps: 8,
          setType: SetType.warmup,
          isCompleted: true,
        ),
      ]);

      final entries = service.buildEntries([session], weightExercise);
      expect(entries, isEmpty);
    });

    test('a dropset drop never becomes the best record set', () {
      // A drop with more reps than the top set would win the Epley estimate
      // without the guard. Only the heavy top set is eligible for a record.
      final session = sessionWith(const [
        WorkoutSet(id: 'top', weight: 100, reps: 5, isCompleted: true),
        WorkoutSet(
          id: 'drop',
          weight: 90,
          reps: 20,
          setType: SetType.dropset,
          parentSetId: 'top',
          dropIndex: 1,
          isCompleted: true,
        ),
      ]);

      final entries = service.buildEntries([session], weightExercise);
      expect(entries, hasLength(1));
      // Best comes from the top working set, not the high-rep drop.
      expect(entries.single.set.weight, 100);
      expect(entries.single.set.reps, 5);
    });
  });

  test('suggestNextTarget increments and rounds correctly', () {
    // Under 40 => 1.25kg increments
    final s1 = LinkedHashMap<String, double>.from({'d1': 39.0});
    expect(
      service.suggestNextTarget(s1, weightExercise),
      40.0,
    ); // 39 + 1.25 = 40.25 => rounds to 40.0

    // At 40 => 2.5kg increments
    final s2 = LinkedHashMap<String, double>.from({'d1': 40.0});
    expect(service.suggestNextTarget(s2, weightExercise), 42.5);

    // Larger value
    final s3 = LinkedHashMap<String, double>.from({'d1': 110.0});
    expect(service.suggestNextTarget(s3, weightExercise), 112.5);
  });
}
