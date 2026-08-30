import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_coach.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_service.dart';
import 'package:hustl_app/features/workout_log/domain/utils/muscle_group_mapper.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';

Map<DisplayRegion, BodyRegionMetrics> aggregateMetricsToDisplayRegions(
  Map<MuscleGroup, BodyRegionMetrics> metrics,
) {
  final aggregated = <DisplayRegion, BodyRegionMetrics>{
    for (final region in DisplayRegion.values) region: BodyRegionMetrics.zero,
  };
  for (final entry in metrics.entries) {
    aggregated[entry.key.displayRegion] = aggregated[entry.key.displayRegion]!
        .add(entry.value);
  }
  return aggregated;
}

void main() {
  BodyScoreSummary summaryFromVolumes(
    Map<MuscleGroup, double> volumes, {
    int sessionCount = 3,
  }) {
    return BodyScoreSummary.calculate(
      volumes: volumes,
      window: DateTimeRange(
        start: DateTime.utc(2026, 3, 16),
        end: DateTime.utc(2026, 3, 22, 23, 59, 59),
      ),
      sessionCount: sessionCount,
    )!;
  }

  Map<MuscleGroup, double> balancedVolumes() =>
      Map<MuscleGroup, double>.from(defaultWeeklyTargetsByMuscleGroup);

  group('MuscleGroupMapper', () {
    test('maps common aliases to granular muscle groups', () {
      final mapper = MuscleGroupMapper();
      expect(mapper.groupFor('Upper Chest'), MuscleGroup.upperPecs);
      expect(mapper.groupFor('Chest'), MuscleGroup.middlePecs);
      expect(mapper.groupFor('Brachioradialis'), MuscleGroup.forearms);
      expect(mapper.groupFor('TFL'), MuscleGroup.hipAbductors);
      expect(mapper.groupFor('unknown'), MuscleGroup.other);
    });
  });

  group('muscleGroupFromKey', () {
    test('parses singular SVG ids', () {
      expect(muscleGroupFromKey('hip_abductor'), MuscleGroup.hipAbductors);
      expect(muscleGroupFromKey('hip_adductor'), MuscleGroup.hipAdductors);
    });
  });

  group('BodyScoreService', () {
    final service = BodyScoreService();

    WorkoutSession buildHackSquatSession({
      required String id,
      required DateTime start,
    }) {
      return WorkoutSession(
        id: id,
        name: 'Leg Day',
        startTime: start,
        endTime: start.add(const Duration(hours: 1)),
        exercises: const [
          WorkoutExercise(
            id: 'hack-squat',
            exercise: Exercise(
              id: 'hack-squat',
              slug: 'hack-squat',
              name: 'Hack Squat',
              muscles: ['Quads', 'Glutes'],
              kind: ExerciseKind.strength,
            ),
            sets: [
              WorkoutSet(id: 'set-1', weight: 100, reps: 10, isCompleted: true),
              WorkoutSet(id: 'set-2', weight: 100, reps: 10, isCompleted: true),
              WorkoutSet(id: 'set-3', weight: 100, reps: 10, isCompleted: true),
            ],
          ),
        ],
        isCompleted: true,
        lastUpdatedAt: start,
      );
    }

    DateTimeRange fullRange(DateTime reference) {
      return DateTimeRange(
        start: reference.subtract(const Duration(days: 30)),
        end: reference.add(const Duration(days: 30)),
      );
    }

    test('distributes stimulus across primary and secondary muscles', () {
      final start = DateTime.utc(2024, 1, 1, 12);
      final session = WorkoutSession(
        id: 'session-1',
        name: 'Push Day',
        startTime: start,
        endTime: start.add(const Duration(hours: 1)),
        exercises: const [
          WorkoutExercise(
            id: 'ex-1',
            exercise: Exercise(
              id: 'bench',
              slug: 'bench-press-barbell',
              name: 'Bench Press',
              muscles: ['Chest', 'Triceps', 'Front Delts'],
              kind: ExerciseKind.strength,
            ),
            sets: [
              WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: true),
            ],
          ),
        ],
        isCompleted: true,
        lastUpdatedAt: start,
      );

      final result = service.aggregateForRange([session], fullRange(start));
      final regions = aggregateMetricsToDisplayRegions(result);

      expect(regions[DisplayRegion.chest]!.volume, closeTo(0.9, 0.01));
      expect(regions[DisplayRegion.arms]!.volume, closeTo(0.4, 0.01));
      expect(regions[DisplayRegion.shoulders]!.volume, closeTo(0.4, 0.01));

      expect(regions[DisplayRegion.chest]!.sets, closeTo(1.0, 0.01));
      expect(regions[DisplayRegion.arms]!.sets, closeTo(0.5, 0.01));
      expect(regions[DisplayRegion.shoulders]!.sets, closeTo(0.5, 0.01));

      expect(regions[DisplayRegion.chest]!.minutes, closeTo(60.0, 0.1));
      expect(regions[DisplayRegion.arms]!.minutes, closeTo(30.0, 0.1));
      expect(regions[DisplayRegion.shoulders]!.minutes, closeTo(30.0, 0.1));
    });

    test('assigns zero-muscle exercises to Other', () {
      final start = DateTime.utc(2024, 3, 5, 7);
      const exercise = WorkoutExercise(
        id: 'mystery',
        exercise: Exercise(
          id: null,
          slug: null,
          name: 'Mystery Move',
          muscles: [],
          kind: ExerciseKind.strength,
        ),
        sets: [
          WorkoutSet(id: 'm1', weight: 50, reps: 10, isCompleted: true),
          WorkoutSet(id: 'm2', weight: 50, reps: 10, isCompleted: true),
        ],
      );
      final session = WorkoutSession(
        id: 'guest-session',
        name: 'Guest Only',
        startTime: start,
        endTime: start.add(const Duration(minutes: 30)),
        exercises: [exercise],
        isCompleted: true,
        lastUpdatedAt: null,
      );

      final result = service.aggregateForRange([session], fullRange(start));
      final regions = aggregateMetricsToDisplayRegions(result);

      expect(regions[DisplayRegion.other]!.volume, closeTo(1.8, 0.01));
      expect(regions[DisplayRegion.other]!.sets, closeTo(2, 0.01));
      expect(regions[DisplayRegion.other]!.minutes, closeTo(30, 0.1));
    });

    test(
      'fixed weekly summary does not decay earlier sessions in the week',
      () {
        final range = DateTimeRange(
          start: DateTime.utc(2026, 3, 16),
          end: DateTime.utc(2026, 3, 22, 23, 59, 59),
        );

        final mondaySummary = service.summarize([
          buildHackSquatSession(
            id: 'monday',
            start: DateTime.utc(2026, 3, 16, 3),
          ),
        ], range: range)!;

        final sundaySummary = service.summarize([
          buildHackSquatSession(
            id: 'sunday',
            start: DateTime.utc(2026, 3, 22, 3),
          ),
        ], range: range)!;

        expect(
          mondaySummary.regionScores[MuscleGroup.quads],
          closeTo(sundaySummary.regionScores[MuscleGroup.quads]!, 0.001),
        );
        expect(
          mondaySummary.recommendedSets[MuscleGroup.quads],
          closeTo(sundaySummary.recommendedSets[MuscleGroup.quads]!, 0.001),
        );
        expect(
          mondaySummary.weeklyEquivalentVolumes[MuscleGroup.quads],
          closeTo(
            sundaySummary.weeklyEquivalentVolumes[MuscleGroup.quads]!,
            0.001,
          ),
        );
      },
    );

    test(
      'balance score aligns to display-region totals, not subregion split',
      () {
        final volumes = balancedVolumes()
          ..[MuscleGroup.upperPecs] = 8.0
          ..[MuscleGroup.middlePecs] = 0.0
          ..[MuscleGroup.lowerPecs] = 2.0;
        final summary = summaryFromVolumes(volumes);

        expect(summary.balanceScore, closeTo(100.0, 0.001));
      },
    );
  });

  group('BodyScoreCoach', () {
    test('redistributes sets from oversupplied to undersupplied regions', () {
      final volumes = balancedVolumes()
        ..[MuscleGroup.lats] = 12.0
        ..[MuscleGroup.upperTraps] = 4.0
        ..[MuscleGroup.lowerTraps] = 3.0
        ..[MuscleGroup.rhomboids] = 3.0
        ..[MuscleGroup.lowerBack] = 2.0
        ..[MuscleGroup.upperAbs] = 1.0
        ..[MuscleGroup.lowerAbs] = 1.0
        ..[MuscleGroup.obliques] = 1.0;
      final cue = BodyScoreCoach.overallCue(summaryFromVolumes(volumes));

      expect(cue.mode, BodyScoreCoachingMode.redistributeSets);
      expect(cue.primaryRegion, DisplayRegion.core);
      expect(cue.secondaryRegion, DisplayRegion.back);
      expect(cue.setCount, inInclusiveRange(2, 4));
    });

    test('adds sets when one region is low without an oversized donor', () {
      final volumes = balancedVolumes()
        ..[MuscleGroup.upperAbs] = 2.0
        ..[MuscleGroup.lowerAbs] = 2.0
        ..[MuscleGroup.obliques] = 2.0;
      final cue = BodyScoreCoach.overallCue(summaryFromVolumes(volumes));

      expect(cue.mode, BodyScoreCoachingMode.addSets);
      expect(cue.primaryRegion, DisplayRegion.core);
      expect(cue.secondaryRegion, isNull);
      expect(cue.setCount, greaterThanOrEqualTo(1));
    });

    test(
      'mutes rebalancing recommendations when period has only one session',
      () {
        final volumes = balancedVolumes()
          ..[MuscleGroup.upperAbs] = 1.0
          ..[MuscleGroup.lowerAbs] = 1.0
          ..[MuscleGroup.obliques] = 1.0;
        final cue = BodyScoreCoach.overallCue(
          summaryFromVolumes(volumes, sessionCount: 1),
        );

        expect(cue.mode, BodyScoreCoachingMode.gatherMoreData);
        expect(cue.primaryRegion, DisplayRegion.core);
      },
    );

    test('applies low-data guardrail consistently to region cues', () {
      final volumes = balancedVolumes()
        ..[MuscleGroup.upperAbs] = 1.0
        ..[MuscleGroup.lowerAbs] = 1.0
        ..[MuscleGroup.obliques] = 1.0;
      final summary = summaryFromVolumes(volumes, sessionCount: 1);
      final cue = BodyScoreCoach.cueForRegion(summary, DisplayRegion.arms);

      expect(cue.mode, BodyScoreCoachingMode.gatherMoreData);
      expect(cue.primaryRegion, DisplayRegion.arms);
    });
  });

  group('BodyScoreSummary Phase 3 raw setsByGroup', () {
    final service = BodyScoreService();

    DateTimeRange weekRange() => DateTimeRange(
      start: DateTime.utc(2026, 3, 16),
      end: DateTime.utc(2026, 3, 22, 23, 59, 59),
    );

    WorkoutSession squatSession({int sets = 3}) {
      return WorkoutSession(
        id: 'legs-1',
        name: 'Leg Day',
        startTime: DateTime.utc(2026, 3, 17, 12),
        endTime: DateTime.utc(2026, 3, 17, 13),
        exercises: [
          WorkoutExercise(
            id: 'hack-squat',
            exercise: const Exercise(
              id: 'hack-squat',
              slug: 'hack-squat',
              name: 'Hack Squat',
              muscles: ['Quads', 'Glutes'],
              kind: ExerciseKind.strength,
            ),
            sets: [
              for (var i = 0; i < sets; i++)
                WorkoutSet(
                  id: 'set-$i',
                  weight: 100,
                  reps: 10,
                  isCompleted: true,
                ),
            ],
          ),
        ],
        isCompleted: true,
        lastUpdatedAt: DateTime.utc(2026, 3, 17, 12),
      );
    }

    test('summary.setsByGroup matches aggregateForRange raw set counts', () {
      final sessions = [squatSession(sets: 5)];
      final range = weekRange();

      final summary = service.summarize(sessions, range: range)!;
      final aggregate = service.aggregateForRange(sessions, range);

      for (final group in MuscleGroup.values) {
        final viaSummary = summary.setsByGroup[group] ?? 0.0;
        final viaAggregate = aggregate[group]?.sets ?? 0.0;
        expect(
          viaSummary,
          closeTo(viaAggregate, 0.001),
          reason: 'setsByGroup[$group] should equal aggregateForRange sets',
        );
      }
      // Hack Squat = Quads primary (ratio 1.0) + Glutes secondary (ratio 0.5).
      expect(summary.setsByGroup[MuscleGroup.quads], closeTo(5.0, 0.001));
      expect(summary.setsByGroup[MuscleGroup.glutes], closeTo(2.5, 0.001));
    });

    test('setsByDisplayRegion sums group raw sets per region', () {
      final summary = service.summarize([squatSession(sets: 4)], range: weekRange())!;
      // Legs = quads (4.0) + glutes (2.0) raw sets.
      expect(
        summary.setsForDisplayRegion(DisplayRegion.legs),
        closeTo(6.0, 0.001),
      );
    });
  });

  group('BodyScoreSummary Phase 4 integer physical-set counter', () {
    final service = BodyScoreService();

    DateTimeRange weekRange() => DateTimeRange(
      start: DateTime.utc(2026, 3, 16),
      end: DateTime.utc(2026, 3, 22, 23, 59, 59),
    );

    test(
      'a region with 10 physical sets reads 10, not the fractional 9.5',
      () {
        // 9 sets with Chest as PRIMARY (ratio 1.0 -> 9.0 raw) plus 1 set with
        // Chest as a SECONDARY muscle (ratio 0.5 -> 0.5 raw) = 9.5 raw sets,
        // but 10 actual physical working sets that trained the chest.
        final session = WorkoutSession(
          id: 'push-1',
          name: 'Push Day',
          startTime: DateTime.utc(2026, 3, 18, 12),
          endTime: DateTime.utc(2026, 3, 18, 13),
          exercises: [
            WorkoutExercise(
              id: 'bench',
              exercise: const Exercise(
                id: 'bench',
                slug: 'bench-press',
                name: 'Bench Press',
                muscles: ['Chest'],
                kind: ExerciseKind.strength,
              ),
              sets: [
                for (var i = 0; i < 9; i++)
                  WorkoutSet(
                    id: 'bench-$i',
                    weight: 80,
                    reps: 10,
                    isCompleted: true,
                  ),
              ],
            ),
            const WorkoutExercise(
              id: 'dip',
              exercise: Exercise(
                id: 'dip',
                slug: 'dip',
                name: 'Triceps Dip',
                muscles: ['Triceps', 'Chest'],
                kind: ExerciseKind.strength,
              ),
              sets: [
                WorkoutSet(
                  id: 'dip-0',
                  weight: 0,
                  reps: 10,
                  isCompleted: true,
                ),
              ],
            ),
          ],
          isCompleted: true,
          lastUpdatedAt: DateTime.utc(2026, 3, 18, 12),
        );

        final summary = service.summarize([session], range: weekRange())!;

        // Both Bench and Dip map Chest to the same granular group, so the raw
        // (fractional) figure is 9 * 1.0 + 1 * 0.5 = 9.5 ...
        final chestGroup = summary.setsByGroup.entries
            .where((e) => e.key.displayRegion == DisplayRegion.chest)
            .fold<double>(0.0, (sum, e) => sum + e.value);
        expect(chestGroup, closeTo(9.5, 0.001));

        // ... while the TRUE physical-set count is a whole 10.
        final chestPhysical = summary.physicalSetsByDisplayRegion[DisplayRegion.chest]!;
        expect(chestPhysical, 10);
        expect(chestPhysical, isA<int>());
      },
    );

    test('physicalSetsByGroup counts every completed non-warmup set once', () {
      final session = WorkoutSession(
        id: 'legs-2',
        name: 'Leg Day',
        startTime: DateTime.utc(2026, 3, 17, 12),
        endTime: DateTime.utc(2026, 3, 17, 13),
        exercises: [
          WorkoutExercise(
            id: 'hack-squat',
            exercise: const Exercise(
              id: 'hack-squat',
              slug: 'hack-squat',
              name: 'Hack Squat',
              muscles: ['Quads', 'Glutes'],
              kind: ExerciseKind.strength,
            ),
            sets: [
              for (var i = 0; i < 10; i++)
                WorkoutSet(
                  id: 'set-$i',
                  weight: 100,
                  reps: 10,
                  isCompleted: true,
                ),
              // A warm-up set must NOT count.
              const WorkoutSet(
                id: 'warmup',
                weight: 40,
                reps: 10,
                isCompleted: true,
                setType: SetType.warmup,
              ),
              // An incomplete set must NOT count.
              const WorkoutSet(
                id: 'incomplete',
                weight: 100,
                reps: 10,
                isCompleted: false,
              ),
            ],
          ),
        ],
        isCompleted: true,
        lastUpdatedAt: DateTime.utc(2026, 3, 17, 12),
      );

      final summary = service.summarize([session], range: weekRange())!;
      // Quads + Glutes are both trained by all 10 working sets.
      expect(summary.physicalSetsForGroup(MuscleGroup.quads), 10);
      expect(summary.physicalSetsForGroup(MuscleGroup.glutes), 10);
    });

    test(
      'physicalSetsByDisplayRegion dedupes a set across muscles in the same '
      'region (Quads + Glutes -> Legs counts once)',
      () {
        final session = WorkoutSession(
          id: 'legs-dedupe',
          name: 'Leg Day',
          startTime: DateTime.utc(2026, 3, 17, 12),
          endTime: DateTime.utc(2026, 3, 17, 13),
          exercises: [
            WorkoutExercise(
              id: 'hack-squat',
              exercise: const Exercise(
                id: 'hack-squat',
                slug: 'hack-squat',
                name: 'Hack Squat',
                // One physical set maps to two muscles that both roll up to the
                // Legs display region.
                muscles: ['Quads', 'Glutes'],
                kind: ExerciseKind.strength,
              ),
              sets: [
                for (var i = 0; i < 10; i++)
                  WorkoutSet(
                    id: 'set-$i',
                    weight: 100,
                    reps: 10,
                    isCompleted: true,
                  ),
              ],
            ),
          ],
          isCompleted: true,
          lastUpdatedAt: DateTime.utc(2026, 3, 17, 12),
        );

        final summary = service.summarize([session], range: weekRange())!;

        // Per-muscle counts are unchanged: both muscles see all 10 sets.
        expect(summary.physicalSetsForGroup(MuscleGroup.quads), 10);
        expect(summary.physicalSetsForGroup(MuscleGroup.glutes), 10);

        // But the DISPLAY-region rollup must count each physical set ONCE for
        // Legs (10 distinct sets), NOT sum the per-muscle counts (which would
        // read 20 and let the UI mark Legs in range / over max too early).
        expect(summary.physicalSetsByDisplayRegion[DisplayRegion.legs], 10);
      },
    );

    test(
      'physicalSetsByDisplayRegion counts a set spanning two DIFFERENT regions '
      'once in each',
      () {
        final session = WorkoutSession(
          id: 'cross-region',
          name: 'Push',
          startTime: DateTime.utc(2026, 3, 17, 12),
          endTime: DateTime.utc(2026, 3, 17, 13),
          exercises: [
            WorkoutExercise(
              id: 'dip',
              exercise: const Exercise(
                id: 'dip',
                slug: 'dip',
                name: 'Triceps Dip',
                // Chest -> chest region, Triceps -> arms region.
                muscles: ['Chest', 'Triceps'],
                kind: ExerciseKind.strength,
              ),
              sets: [
                for (var i = 0; i < 5; i++)
                  WorkoutSet(
                    id: 'dip-$i',
                    weight: 0,
                    reps: 10,
                    isCompleted: true,
                  ),
              ],
            ),
          ],
          isCompleted: true,
          lastUpdatedAt: DateTime.utc(2026, 3, 17, 12),
        );

        final summary = service.summarize([session], range: weekRange())!;

        // The 5 sets each touch two distinct display regions, so each region
        // reads 5 (not summed across the two muscles into one region).
        expect(summary.physicalSetsByDisplayRegion[DisplayRegion.chest], 5);
        expect(summary.physicalSetsByDisplayRegion[DisplayRegion.arms], 5);
      },
    );
  });

  group('RegionVolumeBand (Phase 4)', () {
    test('fromTarget derives min/target/max with the default factors', () {
      final band = RegionVolumeBand.fromTarget(10.0);
      expect(band.min, closeTo(6.0, 0.001));
      expect(band.target, closeTo(10.0, 0.001));
      expect(band.max, closeTo(14.0, 0.001));
      expect(band.contains(8.0), isTrue);
      expect(band.isBelow(5.0), isTrue);
      expect(band.isAbove(15.0), isTrue);
    });

    test('fromTarget collapses to zero for a non-positive target', () {
      expect(RegionVolumeBand.fromTarget(0.0), RegionVolumeBand.zero);
    });

    test('summary bandsByDisplayRegion sums per-region targets then bands', () {
      final summary = BodyScoreSummary.calculate(
        volumes: Map<MuscleGroup, double>.from(defaultWeeklyTargetsByMuscleGroup),
        window: DateTimeRange(
          start: DateTime.utc(2026, 3, 16),
          end: DateTime.utc(2026, 3, 22, 23, 59, 59),
        ),
        sessionCount: 3,
      )!;

      // Chest target = upper(4) + middle(4) + lower(2) = 10.
      final chest = summary.bandForDisplayRegion(DisplayRegion.chest);
      expect(chest.target, closeTo(10.0, 0.001));
      expect(chest.min, closeTo(6.0, 0.001));
      expect(chest.max, closeTo(14.0, 0.001));

      // Other is never banded.
      expect(
        summary.bandsByDisplayRegion.containsKey(DisplayRegion.other),
        isFalse,
      );
    });
  });
}
