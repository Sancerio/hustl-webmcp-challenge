import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_coach.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_service.dart';
import 'package:hustl_app/features/workout_log/domain/utils/time_periods.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/body_score_screen.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';

// PR #384 Finding 2: the coach-explain `regions` payload must cite the SAME
// basis the visible cue + region bars use. For the in-progress current week that
// is the RAW summed-sets-vs-target basis, NOT the paced (vol/days)*7 weekly
// equivalent. Before the fix the cue/bars read raw while `_buildTrainingFacts`
// read paced, so for the same partial week the visible cue could say "add sets"
// while the explanation facts called that region over 100%.
void main() {
  WorkoutSession makeSession({
    required String id,
    required DateTime start,
    required String name,
    required List<String> muscles,
    int sets = 3,
  }) {
    return WorkoutSession(
      id: id,
      name: name,
      startTime: start,
      endTime: start.add(const Duration(hours: 1)),
      isCompleted: true,
      exercises: [
        WorkoutExercise(
          id: 'exercise-$id',
          exercise: Exercise(name: name, muscles: muscles),
          sets: [
            for (var index = 0; index < sets; index++)
              WorkoutSet(
                id: 'set-$id-$index',
                weight: 100,
                reps: 8,
                isCompleted: true,
              ),
          ],
        ),
      ],
    );
  }

  int regionPercent(List<Map<String, dynamic>> regions, DisplayRegion region) {
    final match = regions.firstWhere(
      (r) => r['name'] == region.label,
      orElse: () => const {'percentOfGoal': -1},
    );
    return match['percentOfGoal'] as int;
  }

  group('Phase 1: _buildTrainingFacts regions match the on-screen basis', () {
    // A Wednesday so the current week is day 3 of 7: the paced (sets/days)*7
    // weekly equivalent multiplies a region's raw sets by ~7/3 (= 2.33), enough
    // to flip a genuinely under-target region above 100% under the paced basis.
    final anchor = DateTime(2026, 6, 17, 12);
    final window = BodyScorePeriod.currentWeek.resolve(
      anchor,
      firstWeekday: DateTime.monday,
    );

    // All core volume on one mid-week day: 6 raw core sets (target 10) so the
    // RAW basis shows core ~60% (under). The PACED weekly equivalent inflates it
    // by ~7/3 to well over 100%. Every other region is covered generously so
    // core is the sole laggard.
    final sessions = [
      makeSession(
        id: 'core-upper',
        start: DateTime(2026, 6, 17, 9),
        name: 'Crunch',
        muscles: const ['Upper Abs'],
        sets: 3,
      ),
      makeSession(
        id: 'core-lower',
        start: DateTime(2026, 6, 17, 10),
        name: 'Leg Raise',
        muscles: const ['Lower Abs'],
        sets: 3,
      ),
      makeSession(
        id: 'chest',
        start: DateTime(2026, 6, 15, 9),
        name: 'Bench',
        muscles: const ['Chest', 'Upper Pecs', 'Lower Pecs'],
        sets: 12,
      ),
      makeSession(
        id: 'back',
        start: DateTime(2026, 6, 15, 10),
        name: 'Row',
        muscles: const ['Lats', 'Upper Traps', 'Rhomboids', 'Lower Back'],
        sets: 12,
      ),
      makeSession(
        id: 'shoulders',
        start: DateTime(2026, 6, 16, 9),
        name: 'Press',
        muscles: const ['Front Delts', 'Side Delts', 'Rear Delts'],
        sets: 12,
      ),
      makeSession(
        id: 'arms',
        start: DateTime(2026, 6, 16, 10),
        name: 'Curl',
        muscles: const ['Biceps', 'Triceps', 'Forearms'],
        sets: 12,
      ),
      makeSession(
        id: 'legs',
        start: DateTime(2026, 6, 16, 11),
        name: 'Squat',
        muscles: const ['Quads', 'Hamstrings', 'Glutes', 'Calves'],
        sets: 12,
      ),
    ];

    final summary = BodyScoreService().summarize(sessions, range: window.range)!;
    final currentWeekRawSets = {
      for (final entry in BodyScoreService()
          .aggregateForRange(sessions, window.range)
          .entries)
        entry.key: entry.value.sets,
    };

    test('current week: regions use the RAW raw-vs-target basis (match the cue), '
        'NOT the paced percents - so the under-target region is NOT > 100%', () {
      // The RAW basis (the same one the cue + bars read) shows core under goal.
      final rawCore = BodyScoreCoach.currentWeekByDisplayRegion(
        currentWeekRawSets,
        weeklyTargets: summary.weeklyTargets,
      )[DisplayRegion.core]!;
      expect(rawCore.isMet, isFalse, reason: 'core is genuinely under target');
      final rawCorePercent = rawCore.percent.round();
      expect(rawCorePercent, lessThan(100));

      // The coach-explain regions built for the current week must cite that SAME
      // raw figure, not the paced one.
      final regions = trainingFactsRegionsForTest(
        summary: summary,
        isCurrentWeek: true,
        currentWeekRawSets: currentWeekRawSets,
      );
      expect(regionPercent(regions, DisplayRegion.core), rawCorePercent);
      // ...and crucially NOT over 100% (the paced contradiction the fix removes).
      expect(regionPercent(regions, DisplayRegion.core), lessThan(100));
    });

    test('the OLD paced basis would have contradicted the cue (core > 100%) - '
        'the current-week branch is what avoids that', () {
      // Sanity: with the same partial week the paced basis the closed-period path
      // uses inflates core above goal, so an unbranched _buildTrainingFacts would
      // emit a > 100% core figure while the visible cue says "add sets".
      final pacedRegions = trainingFactsRegionsForTest(
        summary: summary,
        isCurrentWeek: false, // the paced (closed-period) basis
        currentWeekRawSets: currentWeekRawSets,
      );
      expect(
        regionPercent(pacedRegions, DisplayRegion.core),
        greaterThanOrEqualTo(100),
        reason: 'the paced basis inflates core above target mid-week',
      );
    });

    test('closed periods keep the paced basis (independent of currentWeekRawSets)',
        () {
      final pacedRegions = trainingFactsRegionsForTest(
        summary: summary,
        isCurrentWeek: false,
        currentWeekRawSets: const {},
      );
      final alsoPaced = trainingFactsRegionsForTest(
        summary: summary,
        isCurrentWeek: false,
        currentWeekRawSets: currentWeekRawSets,
      );
      expect(
        regionPercent(pacedRegions, DisplayRegion.core),
        regionPercent(alsoPaced, DisplayRegion.core),
      );
    });
  });
}
