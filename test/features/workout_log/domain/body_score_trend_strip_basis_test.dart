import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_coach.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_service.dart';
import 'package:hustl_app/features/workout_log/domain/utils/time_periods.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';

/// Guards the codex [P2 + P3s] (PR #385): the current-week HEADLINE bars use the
/// DEDUPED integer physical-set basis ([BodyScoreSummary.physicalSetsByDisplayRegion]
/// - a set training two muscles in one display region counts ONCE), but the
/// 4-week trend strip used to sum the raw fractional [aggregateForRange] `sets`
/// (`baseSet x groupRatio`, which double-counts a compound set across the muscles
/// it trains). So a compound leg day could read e.g. Legs 12 / 10 (emerald, met)
/// in the in-progress trend bar while the headline read Legs 8 / 10 (amber,
/// under) - the SAME week, the SAME region, two different met-states.
///
/// The trend strip now feeds on the SAME deduped path (`summarize(weekRange)
/// .physicalSetsByDisplayRegion`). These tests pin that the in-progress week's
/// per-region figure + met-state match the headline exactly, and that the raw
/// summed figure (the old basis) would have disagreed.
void main() {
  // Mid-week Wednesday so "this week" is a genuine in-progress partial week.
  final anchor = DateTime(2026, 6, 17, 12);

  /// A leg day of [sets] Hack-Squat working sets. Each set trains Quads + Glutes
  /// - two muscles that BOTH roll up to the Legs display region, so the deduped
  /// physical count is [sets], but the raw `baseSet x groupRatio` figure sums the
  /// primary (1.0) + secondary (0.5) credit to 1.5 per set.
  WorkoutSession legDay({
    required String id,
    required DateTime start,
    required int sets,
  }) {
    return WorkoutSession(
      id: id,
      name: 'Leg Day',
      startTime: start,
      endTime: start.add(const Duration(hours: 1)),
      isCompleted: true,
      exercises: [
        WorkoutExercise(
          id: 'hack-squat-$id',
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
                id: 'set-$id-$i',
                weight: 100,
                reps: 10,
                isCompleted: true,
              ),
          ],
        ),
      ],
    );
  }

  group('trend strip in-progress week uses the deduped headline basis', () {
    final service = BodyScoreService();

    double legsTargetSum() => MuscleGroup.values
        .where((g) => g.displayRegion == DisplayRegion.legs)
        .fold<double>(
          0,
          (sum, g) => sum + (defaultWeeklyTargetsByMuscleGroup[g] ?? 0),
        );

    test(
      'compound leg day: deduped Legs = 8 (under 10), raw summed = 12 (would be met)',
      () {
        // 8 Hack-Squat sets this week. Deduped Legs physical sets = 8 (one per
        // physical set), under the ~10 Legs target -> under-target/amber. The raw
        // summed figure would be 8*1.5 = 12, which rounds to >= 10 and reads MET.
        final range = BodyScorePeriod.currentWeek
            .resolve(anchor, firstWeekday: DateTime.monday)
            .range;
        final sessions = [
          legDay(id: 'w', start: DateTime(2026, 6, 16, 9), sets: 8),
        ];

        // The DEDUPED basis the trend strip (and headline) now consume.
        final summary = service.summarize(sessions, range: range)!;
        final dedupedLegs =
            summary.physicalSetsByDisplayRegion[DisplayRegion.legs]!;
        expect(dedupedLegs, 8);

        // The OLD raw summed basis the trend strip used to consume.
        final metrics = service.aggregateForRange(sessions, range);
        double rawLegs = 0.0;
        for (final entry in metrics.entries) {
          if (entry.key.displayRegion == DisplayRegion.legs) {
            rawLegs += entry.value.sets;
          }
        }
        expect(rawLegs.round(), 12);

        final legsTarget = legsTargetSum();
        expect(legsTarget.round(), 10);

        // Deduped -> UNDER target (matches the headline). Raw -> would be MET.
        expect(
          dedupedLegs >= legsTarget.round(),
          isFalse,
          reason: 'deduped 8 is under the 10 Legs target (headline basis)',
        );
        expect(
          rawLegs.round() >= legsTarget.round(),
          isTrue,
          reason: 'the OLD raw 12 would have read met - the contradiction',
        );
      },
    );

    test('the in-progress trend figure equals the headline figure for Legs', () {
      // The headline reads CurrentWeekRegionSummary.displaySets, which for the
      // current week is the deduped physicalSetsByDisplayRegion count. The trend
      // strip now reads the SAME number for the in-progress (rightmost) week.
      final range = BodyScorePeriod.currentWeek
          .resolve(anchor, firstWeekday: DateTime.monday)
          .range;
      final sessions = [
        legDay(id: 'w', start: DateTime(2026, 6, 16, 9), sets: 8),
      ];
      final summary = service.summarize(sessions, range: range)!;

      // Headline basis for Legs.
      final headline = BodyScoreCoach.currentWeekByDisplayRegion(
        {for (final e in summary.setsByGroup.entries) e.key: e.value},
        weeklyTargets: summary.weeklyTargets,
        physicalSetsByRegion: summary.physicalSetsByDisplayRegion,
        bandsByRegion: summary.bandsByDisplayRegion,
      )[DisplayRegion.legs]!;

      // Trend-strip in-progress basis for Legs (what _buildTrendWeeks now uses).
      final trendLegs = summary
          .physicalSetsByDisplayRegion[DisplayRegion.legs]!
          .toDouble();

      // SAME number, SAME met-state - no headline-vs-trend contradiction.
      expect(trendLegs, headline.displaySets.toDouble());
      expect(headline.displaySets, 8);
      expect(headline.isMet, isFalse);
      expect(trendLegs.round() >= headline.weeklyTarget.round(), isFalse);
    });

    test('an on-goal compound leg day reads met on the deduped basis', () {
      // 10 Hack-Squat sets -> deduped Legs = 10, meets the ~10 target. The strip's
      // met-state (deduped) and the headline (deduped) both read met.
      final range = BodyScorePeriod.currentWeek
          .resolve(anchor, firstWeekday: DateTime.monday)
          .range;
      final sessions = [
        legDay(id: 'w', start: DateTime(2026, 6, 16, 9), sets: 10),
      ];
      final summary = service.summarize(sessions, range: range)!;
      final dedupedLegs =
          summary.physicalSetsByDisplayRegion[DisplayRegion.legs]!;
      expect(dedupedLegs, 10);
      expect(dedupedLegs >= legsTargetSum().round(), isTrue);
    });
  });
}
