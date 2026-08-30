import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_coach.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_service.dart';
import 'package:hustl_app/features/workout_log/domain/utils/time_periods.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';

void main() {
  // A Wednesday, mid-week, so "this week" is a genuinely partial in-progress
  // week (Mon-Wed = day 3 of 7). The closed periods all end before it.
  final anchor = DateTime(2026, 6, 17, 12);

  WorkoutSession coreSession({
    required String id,
    required DateTime start,
    required int sets,
    List<String> muscles = const ['Upper Abs'],
    String name = 'Crunch',
  }) {
    return WorkoutSession(
      id: id,
      name: name,
      startTime: start,
      endTime: start.add(const Duration(hours: 1)),
      isCompleted: true,
      exercises: [
        WorkoutExercise(
          id: 'ex-$id',
          exercise: Exercise(name: name, muscles: muscles),
          sets: [
            for (var i = 0; i < sets; i++)
              WorkoutSet(
                id: 'set-$id-$i',
                weight: 0,
                reps: 15,
                isCompleted: true,
              ),
          ],
        ),
      ],
    );
  }

  group('BodyScorePeriod.currentWeek', () {
    test('is the default period for the surface', () {
      expect(BodyScorePeriod.defaultPeriod, BodyScorePeriod.currentWeek);
    });

    test('resolves to the in-progress week range (week start -> now)', () {
      final window = BodyScorePeriod.currentWeek.resolve(
        anchor,
        firstWeekday: DateTime.monday,
      );
      // Mon 2026-06-15 .. Wed 2026-06-17 12:00.
      expect(window.range.start, DateTime(2026, 6, 15));
      expect(window.range.end, anchor);
      expect(currentWeekDayOf(window.range), 3);
      expect(window.labelWithDate, contains('This week so far'));
      expect(window.labelWithDate, contains('day 3 of 7'));
    });

    test('closed periods still end before the current week', () {
      final closed = BodyScorePeriod.lastFullWeek.resolve(
        anchor,
        firstWeekday: DateTime.monday,
      );
      final currentStart = BodyScorePeriod.currentWeek
          .resolve(anchor, firstWeekday: DateTime.monday)
          .range
          .start;
      expect(closed.range.end.isBefore(currentStart), isTrue);
    });
  });

  group('raw current-week headline (Phase 1)', () {
    final service = BodyScoreService();

    test('10 raw core sets this week => Core 10 / 10, no "add core" nag', () {
      // Spread 10 raw core sets across the three core sub-muscles so the whole
      // Core display-region target (3.5 + 3.5 + 3.0 = 10) is met.
      final sessions = [
        coreSession(
          id: 'upper',
          start: DateTime(2026, 6, 15, 9),
          sets: 4,
          muscles: const ['Upper Abs'],
        ),
        coreSession(
          id: 'lower',
          start: DateTime(2026, 6, 16, 9),
          sets: 3,
          muscles: const ['Lower Abs'],
          name: 'Leg Raise',
        ),
        coreSession(
          id: 'obliques',
          start: DateTime(2026, 6, 17, 9),
          sets: 3,
          muscles: const ['Obliques'],
          name: 'Side Bend',
        ),
      ];

      final range = BodyScorePeriod.currentWeek
          .resolve(anchor, firstWeekday: DateTime.monday)
          .range;
      final rawSets = {
        for (final entry
            in service.aggregateForRange(sessions, range).entries)
          entry.key: entry.value.sets,
      };

      final byRegion = BodyScoreCoach.currentWeekByDisplayRegion(rawSets);
      final core = byRegion[DisplayRegion.core]!;
      expect(core.weeklyTarget.round(), 10);
      expect(core.rawSets.round(), 10);
      expect(core.isMet, isTrue);

      // The cue must NOT nag about core (it is met). With every OTHER region at
      // zero this week the cue points at one of those, never core.
      final cue = BodyScoreCoach.currentWeekCue(rawSets);
      expect(cue.primaryRegion, isNot(DisplayRegion.core));
      expect(cue.headline.toLowerCase(), isNot(contains('core')));
    });

    test('the OLD paced score would have inflated/diluted core - the raw '
        'headline does not', () {
      // 10 core sets logged on a single mid-week day. The paced score
      // ((vol/days)*7) would NOT equal the raw 10/10; the raw headline must.
      final sessions = [
        coreSession(
          id: 'upper',
          start: DateTime(2026, 6, 17, 9),
          sets: 4,
          muscles: const ['Upper Abs'],
        ),
        coreSession(
          id: 'lower',
          start: DateTime(2026, 6, 17, 10),
          sets: 3,
          muscles: const ['Lower Abs'],
          name: 'Leg Raise',
        ),
        coreSession(
          id: 'obliques',
          start: DateTime(2026, 6, 17, 11),
          sets: 3,
          muscles: const ['Obliques'],
          name: 'Side Bend',
        ),
      ];
      final range = BodyScorePeriod.currentWeek
          .resolve(anchor, firstWeekday: DateTime.monday)
          .range;
      final rawSets = {
        for (final entry
            in service.aggregateForRange(sessions, range).entries)
          entry.key: entry.value.sets,
      };
      final core = BodyScoreCoach.currentWeekByDisplayRegion(
        rawSets,
      )[DisplayRegion.core]!;
      // RAW, summed - exactly 10, not paced up to ~23 or diluted.
      expect(core.rawSets.round(), 10);
      expect(core.percent.round(), 100);
    });

    test('an under-target region this week gets a raw "add about N" cue', () {
      // Only 4 core sets this week => 6 short of the 10 target. No other region
      // trained, but core is the relevant under-target region here.
      final sessions = [
        coreSession(id: 'c', start: DateTime(2026, 6, 16, 9), sets: 4),
      ];
      final range = BodyScorePeriod.currentWeek
          .resolve(anchor, firstWeekday: DateTime.monday)
          .range;
      final rawSets = {
        for (final entry
            in service.aggregateForRange(sessions, range).entries)
          entry.key: entry.value.sets,
      };
      // Core summary is 4 / 10.
      final core = BodyScoreCoach.currentWeekByDisplayRegion(
        rawSets,
      )[DisplayRegion.core]!;
      expect(core.rawSets.round(), 4);
      expect(core.isMet, isFalse);

      final cue = BodyScoreCoach.currentWeekCue(rawSets);
      expect(cue.mode, BodyScoreCoachingMode.addSets);
      expect(cue.headline.toLowerCase(), startsWith('add about'));
      expect(cue.setCount, greaterThanOrEqualTo(1));
    });

    test('all regions met => no nag, reads as done', () {
      // Give every targeted region its full weekly target this week.
      final rawSets = <MuscleGroup, double>{
        for (final entry in defaultWeeklyTargetsByMuscleGroup.entries)
          entry.key: entry.value,
      };
      final cue = BodyScoreCoach.currentWeekCue(rawSets);
      expect(cue.mode, BodyScoreCoachingMode.maintain);
      expect(cue.headline.toLowerCase(), isNot(contains('add')));
    });

    test('a region at 9.5 raw vs a 10 target renders met (10 / 10) with NO '
        '"add" nag', () {
      // Core nets 9.5 raw sets (3.5 + 3.5 + 2.5) - a fractional value from split
      // compound/secondary muscle credit. Every OTHER targeted region gets its
      // full weekly target so Core is the only region that could be flagged.
      final rawSets = <MuscleGroup, double>{
        for (final entry in defaultWeeklyTargetsByMuscleGroup.entries)
          entry.key: entry.value,
        MuscleGroup.upperAbs: 3.5,
        MuscleGroup.lowerAbs: 3.5,
        MuscleGroup.obliques: 2.5, // total core = 9.5, target = 10.
      };

      // The displayed region figure rounds the raw value: 9.5 -> 10 / 10.
      final core = BodyScoreCoach.currentWeekByDisplayRegion(
        rawSets,
      )[DisplayRegion.core]!;
      expect(core.rawSets, 9.5);
      expect(core.rawSets.round(), 10);
      expect(core.weeklyTarget.round(), 10);
      // Met on the rounded/display basis, so the detail tile is not marked under
      // target and the headline does not nag.
      expect(core.isMet, isTrue);

      // The cue must NOT nag - a displayed 10 / 10 is done, not under target.
      final cue = BodyScoreCoach.currentWeekCue(rawSets);
      expect(cue.mode, BodyScoreCoachingMode.maintain);
      expect(cue.headline.toLowerCase(), isNot(contains('add')));
      expect(cue.primaryRegion, isNot(DisplayRegion.core));
    });
  });
}
