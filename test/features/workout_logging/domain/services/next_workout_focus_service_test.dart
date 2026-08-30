import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/core/coaching/coach_insight.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_coach.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_service.dart';
import 'package:hustl_app/features/workout_log/domain/utils/time_periods.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/services/next_workout_focus_service.dart';

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

  test(
    'build highlights stale undertrained region and surfaces known exercises',
    () {
      // A Monday anchor so the recent-session cluster falls inside the
      // default last-4-full-weeks window the service now aligns to, leaving
      // the 60-day-stale legs as the sole under-target region.
      final anchor = DateTime.utc(2026, 4, 6, 12);
      final service = NextWorkoutFocusService(
        bodyScoreService: BodyScoreService(),
        // These cases assert stale-region detection over a multi-week closed
        // window; the surface default is now the in-progress current week
        // (Phase 1), so pin the period explicitly to preserve their intent.
        period: BodyScorePeriod.last4FullWeeks,
      );
      final sessions = [
        makeSession(
          id: 'legs-old',
          start: anchor.subtract(const Duration(days: 60)),
          name: 'Hack Squat',
          muscles: const ['Quads', 'Glutes'],
          sets: 4,
        ),
        makeSession(
          id: 'chest',
          start: anchor.subtract(const Duration(days: 3)),
          name: 'Bench Press',
          muscles: const ['Chest', 'Triceps', 'Front Delts'],
          sets: 4,
        ),
        makeSession(
          id: 'back',
          start: anchor.subtract(const Duration(days: 6)),
          name: 'Lat Pulldown',
          muscles: const ['Lats', 'Biceps'],
          sets: 4,
        ),
        makeSession(
          id: 'shoulders',
          start: anchor.subtract(const Duration(days: 8)),
          name: 'Lateral Raise',
          muscles: const ['Side Delts'],
          sets: 4,
        ),
        makeSession(
          id: 'arms',
          start: anchor.subtract(const Duration(days: 10)),
          name: 'Cable Curl',
          muscles: const ['Biceps'],
          sets: 4,
        ),
        makeSession(
          id: 'core',
          start: anchor.subtract(const Duration(days: 12)),
          name: 'Crunch',
          muscles: const ['Upper Abs'],
          sets: 4,
        ),
      ];

      final plan = service.build(sessions, anchor: anchor);

      expect(plan, isNotNull);
      expect(plan!.primaryRegion, DisplayRegion.legs);
      expect(plan.statusLabel, 'Build');
      expect(plan.daysSincePrimaryStimulus, greaterThanOrEqualTo(55));
      expect(plan.exerciseSuggestions, contains('Hack Squat'));
    },
  );

  test(
    'build ignores skipped region exercises when computing last hit fallback',
    () {
      // A Monday anchor so the recent-session cluster falls inside the
      // default last-4-full-weeks window the service now aligns to, leaving
      // the 60-day-stale legs as the sole under-target region.
      final anchor = DateTime.utc(2026, 4, 6, 12);
      final service = NextWorkoutFocusService(
        bodyScoreService: BodyScoreService(),
        // These cases assert stale-region detection over a multi-week closed
        // window; the surface default is now the in-progress current week
        // (Phase 1), so pin the period explicitly to preserve their intent.
        period: BodyScorePeriod.last4FullWeeks,
      );
      final sessions = [
        makeSession(
          id: 'legs-old',
          start: anchor.subtract(const Duration(days: 60)),
          name: 'Hack Squat',
          muscles: const ['Quads', 'Glutes'],
          sets: 4,
        ),
        WorkoutSession(
          id: 'legs-skipped',
          name: 'Leg Day',
          startTime: anchor.subtract(const Duration(days: 1)),
          endTime: anchor,
          isCompleted: true,
          exercises: const [
            WorkoutExercise(
              id: 'leg-press',
              exercise: Exercise(
                name: 'Leg Press',
                muscles: ['Quads', 'Glutes'],
              ),
              sets: [
                WorkoutSet(
                  id: 'skipped-set',
                  weight: 100,
                  reps: 10,
                  isCompleted: false,
                ),
              ],
            ),
          ],
        ),
        makeSession(
          id: 'chest',
          start: anchor.subtract(const Duration(days: 3)),
          name: 'Bench Press',
          muscles: const ['Chest', 'Triceps', 'Front Delts'],
          sets: 4,
        ),
        makeSession(
          id: 'back',
          start: anchor.subtract(const Duration(days: 6)),
          name: 'Lat Pulldown',
          muscles: const ['Lats', 'Biceps'],
          sets: 4,
        ),
        makeSession(
          id: 'shoulders',
          start: anchor.subtract(const Duration(days: 8)),
          name: 'Lateral Raise',
          muscles: const ['Side Delts'],
          sets: 4,
        ),
        makeSession(
          id: 'arms',
          start: anchor.subtract(const Duration(days: 10)),
          name: 'Cable Curl',
          muscles: const ['Biceps'],
          sets: 4,
        ),
        makeSession(
          id: 'core',
          start: anchor.subtract(const Duration(days: 12)),
          name: 'Crunch',
          muscles: const ['Upper Abs'],
          sets: 4,
        ),
      ];

      final plan = service.build(sessions, anchor: anchor);

      expect(plan, isNotNull);
      expect(plan!.primaryRegion, DisplayRegion.legs);
      expect(plan.daysSincePrimaryStimulus, greaterThanOrEqualTo(55));
    },
  );

  group('card verdict stays consistent with the Training-balance detail', () {
    // The detail derives its displayed verdict from the FLAT per-region basis
    // (region tiles + balance score) over the persisted period. These tests
    // assert the home card, built over the SAME period, never contradicts it.
    const period = BodyScorePeriod.last4FullWeeks;
    final anchor = DateTime(2026, 6, 15, 12); // a Monday, mid-month.
    final window = period.resolve(anchor, firstWeekday: DateTime.monday);

    // Spread sessions evenly across the resolved 4-full-weeks window so each
    // lands inside it (the window ends before the current partial week).
    DateTime dayInWindow(int weekOffset) =>
        window.range.start.add(Duration(days: weekOffset * 7 + 1, hours: 10));

    /// The detail's lowest flat region (its surfaced "lagging" region) over the
    /// same window, or null when every targeted region is at/over goal.
    DisplayRegion? detailLaggingRegion(List<WorkoutSession> sessions) {
      final summary = BodyScoreService().summarize(
        sessions,
        range: window.range,
      );
      if (summary == null) return null;
      final regions =
          BodyScoreCoach.aggregateByDisplayRegion(summary, recencyAware: false)
              .values
              .where((r) => r.region != DisplayRegion.other)
              .where((r) => r.weeklyTarget > 0)
              .toList()
            ..sort((a, b) => a.percent.compareTo(b.percent));
      if (regions.isEmpty) return null;
      final lowest = regions.first;
      return lowest.percent < 100.0 ? lowest.region : null;
    }

    test('a region under target => card is NOT balanced/high and surfaces the '
        'same lagging region the detail shows', () {
      // Train chest/back/shoulders/arms/legs hard every week but never core, so
      // core sits far under its weekly goal in the flat detail basis.
      final sessions = <WorkoutSession>[];
      for (var week = 0; week < 4; week++) {
        sessions.addAll([
          makeSession(
            id: 'chest-$week',
            start: dayInWindow(week),
            name: 'Bench Press',
            muscles: const ['Chest', 'Triceps'],
            sets: 5,
          ),
          makeSession(
            id: 'back-$week',
            start: dayInWindow(week).add(const Duration(days: 1)),
            name: 'Barbell Row',
            muscles: const ['Lats', 'Biceps'],
            sets: 5,
          ),
          makeSession(
            id: 'legs-$week',
            start: dayInWindow(week).add(const Duration(days: 2)),
            name: 'Back Squat',
            muscles: const ['Quads', 'Glutes', 'Hamstrings'],
            sets: 5,
          ),
          makeSession(
            id: 'delts-$week',
            start: dayInWindow(week).add(const Duration(days: 3)),
            name: 'Overhead Press',
            muscles: const ['Front Delts', 'Side Delts'],
            sets: 4,
          ),
        ]);
      }

      final lagging = detailLaggingRegion(sessions);
      // Sanity: the detail genuinely shows a region under target here.
      expect(lagging, isNotNull);

      final plan = NextWorkoutFocusService(
        period: period,
      ).build(sessions, anchor: anchor);

      expect(plan, isNotNull);
      // The card must NOT claim "Balanced" while the detail shows a deficit.
      expect(plan!.tone, isNot(NextWorkoutFocusTone.balanced));
      expect(plan.statusLabel, isNot('Balanced'));
      // It surfaces the SAME lagging region the detail shows.
      expect(plan.primaryRegion, lagging);
      // Confidence is DERIVED (well-covered window => high here), never the old
      // hard-coded assertion regardless of data.
      expect(plan.confidence, CoachConfidence.high);
      // The window label tracks the selected period.
      expect(plan.windowLabel, 'last 4 weeks');
    });

    test('a genuinely balanced week => both the card and the detail agree it is '
        'balanced', () {
      // Cover every sub-muscle of every region with generous, even volume each
      // week so no display region sits under its weekly goal in the flat basis.
      // Each exercise's first muscle gets full credit and the rest half, so we
      // list a region's full muscle set per exercise to clear its whole target.
      final sessions = <WorkoutSession>[];
      for (var week = 0; week < 4; week++) {
        // Anchor each week's sessions inside that week of the window.
        WorkoutSession w(String name, int dayOffset, List<String> muscles) =>
            makeSession(
              id: '$name-$week',
              start: dayInWindow(week).add(Duration(days: dayOffset, hours: 2)),
              name: name,
              muscles: muscles,
              sets: 10,
            );
        sessions.addAll([
          w('Chest', 0, const ['Chest', 'Upper Pecs', 'Lower Pecs']),
          w('Back', 1, const ['Lats', 'Upper Traps', 'Rhomboids', 'Lower Back']),
          w('Shoulders', 2, const ['Front Delts', 'Side Delts', 'Rear Delts']),
          w('Arms', 3, const ['Biceps', 'Triceps', 'Forearms']),
          w('Legs', 4, const ['Quads', 'Hamstrings', 'Glutes', 'Calves']),
          w('Core', 5, const ['Upper Abs', 'Lower Abs', 'Obliques']),
        ]);
      }

      // The detail shows no region under target (everything at/over goal).
      expect(detailLaggingRegion(sessions), isNull);

      final plan = NextWorkoutFocusService(
        period: period,
      ).build(sessions, anchor: anchor);

      expect(plan, isNotNull);
      // Both surfaces agree it is balanced.
      expect(plan!.tone, NextWorkoutFocusTone.balanced);
      expect(plan.statusLabel, 'Balanced');
    });
  });

  group('Phase 1: focus card uses the same current-week window as the detail', () {
    // The home focus card now defaults to the in-progress current week (the
    // Training-balance detail's new default), so the two surfaces read ONE
    // window. With this-week data the card builds over the current week - not a
    // closed window that excludes it.
    test('default period is the in-progress current week', () {
      // A Wednesday so "this week" is partial; sessions this week feed the card.
      final anchor = DateTime(2026, 6, 17, 12);
      final sessions = [
        makeSession(
          id: 'chest-this-week',
          start: DateTime(2026, 6, 15, 9),
          name: 'Bench Press',
          muscles: const ['Chest', 'Triceps'],
          sets: 4,
        ),
        makeSession(
          id: 'legs-this-week',
          start: DateTime(2026, 6, 16, 9),
          name: 'Back Squat',
          muscles: const ['Quads', 'Glutes', 'Hamstrings'],
          sets: 4,
        ),
      ];

      // The default-constructed service (no explicit period) aligns to the
      // current week and renders a real plan from this-week data.
      final plan = NextWorkoutFocusService().build(sessions, anchor: anchor);
      expect(plan, isNotNull);
      // The window label tracks the current-week period, never a closed window.
      expect(plan!.windowLabel, 'this week');
      expect(plan.windowLabel, isNot('last 4 weeks'));

      // The current-week summary the card reads over is the SAME window the
      // detail's default resolves to.
      final window = BodyScorePeriod.defaultPeriod.resolve(
        anchor,
        firstWeekday: DateTime.monday,
      );
      final detailSummary = BodyScoreService().summarize(
        sessions,
        range: window.range,
      );
      expect(detailSummary, isNotNull);
    });
  });

  group('Phase 1: current-week verdict matches the detail (raw, not paced)', () {
    // On an IN-PROGRESS week the paced (sets/days)*7 weekly equivalent inflates a
    // mid-week read, so the old overallCue path could call a region
    // balanced/over target while the Training-balance detail - which uses RAW
    // summed sets vs target - shows it under target. These tests assert the home
    // focus card now reads the SAME raw basis as the detail, so the two never
    // contradict each other for the current week.

    // A Wednesday so the current week is day 3 of 7: paced multiplies a region's
    // raw sets by ~7/3 (= 2.33), enough to flip a genuinely under-target region
    // to "over" under the paced basis.
    final anchor = DateTime(2026, 6, 17, 12);
    final window = BodyScorePeriod.currentWeek.resolve(
      anchor,
      firstWeekday: DateTime.monday,
    );

    /// The detail's raw lowest region over the current week (its surfaced
    /// "lagging" region on the raw sets-vs-target basis), or null when every
    /// targeted region has met its weekly goal on the rounded display basis.
    DisplayRegion? detailRawLaggingRegion(List<WorkoutSession> sessions) {
      final rawSets = {
        for (final entry in BodyScoreService()
            .aggregateForRange(sessions, window.range)
            .entries)
          entry.key: entry.value.sets,
      };
      final regions =
          BodyScoreCoach.currentWeekByDisplayRegion(rawSets).values
              .where((r) => r.region != DisplayRegion.other)
              .where((r) => r.weeklyTarget > 0)
              .where((r) => !r.isMet)
              .toList()
            ..sort((a, b) => a.percent.compareTo(b.percent));
      return regions.isEmpty ? null : regions.first.region;
    }

    test('a region the detail shows under target (raw) is the SAME region Home '
        'surfaces - and Home is NOT balanced - even when the PACED basis would '
        'have called it over target', () {
      // All core volume on one mid-week day: 6 raw core sets (target 10) so the
      // RAW detail shows core ~60% (under). The PACED weekly equivalent inflates
      // it by ~7/3 to well over 100%, so the old overallCue path would NOT have
      // flagged core at all - a direct paced-vs-raw contradiction.
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
        // Cover every other region generously so core is the sole raw laggard.
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

      // The detail's RAW basis shows core under target.
      final lagging = detailRawLaggingRegion(sessions);
      expect(lagging, DisplayRegion.core);

      // Sanity: the PACED overallCue would NOT have flagged core (it inflates
      // core's mid-week volume above target), so a paced Home card would
      // contradict the detail. We assert the fix avoids exactly that.
      final pacedSummary = BodyScoreService().summarize(
        sessions,
        range: window.range,
      );
      expect(pacedSummary, isNotNull);
      final pacedCore = BodyScoreCoach.aggregateByDisplayRegion(
        pacedSummary!,
        recencyAware: false,
      )[DisplayRegion.core]!;
      expect(
        pacedCore.percent,
        greaterThanOrEqualTo(100.0),
        reason: 'the paced basis inflates core above target mid-week',
      );

      // Home (default current-week period) now reads the RAW basis: it surfaces
      // the SAME lagging region the detail shows and is NOT balanced.
      final plan = NextWorkoutFocusService().build(sessions, anchor: anchor);
      expect(plan, isNotNull);
      expect(plan!.windowLabel, 'this week');
      expect(plan.primaryRegion, lagging);
      expect(plan.tone, isNot(NextWorkoutFocusTone.balanced));
      expect(plan.statusLabel, isNot('Balanced'));
      expect(plan.statusLabel, 'Build');
    });

    test('a genuinely met current week => Home and the detail BOTH read it as '
        'balanced (no nag)', () {
      // Hit every region's full weekly target this week so the raw detail shows
      // no region under goal.
      WorkoutSession w(String name, int dayOffset, List<String> muscles) =>
          makeSession(
            id: name,
            start: window.range.start.add(Duration(days: dayOffset, hours: 9)),
            name: name,
            muscles: muscles,
            sets: 12,
          );
      final sessions = [
        w('Chest', 0, const ['Chest', 'Upper Pecs', 'Lower Pecs']),
        w('Back', 0, const ['Lats', 'Upper Traps', 'Rhomboids', 'Lower Back']),
        w('Shoulders', 1, const ['Front Delts', 'Side Delts', 'Rear Delts']),
        w('Arms', 1, const ['Biceps', 'Triceps', 'Forearms']),
        w('Legs', 2, const ['Quads', 'Hamstrings', 'Glutes', 'Calves']),
        w('Core', 2, const ['Upper Abs', 'Lower Abs', 'Obliques']),
      ];

      // The detail shows no raw region under target.
      expect(detailRawLaggingRegion(sessions), isNull);

      final plan = NextWorkoutFocusService().build(sessions, anchor: anchor);
      expect(plan, isNotNull);
      expect(plan!.windowLabel, 'this week');
      // Both surfaces agree it is balanced - no "Add N sets" nag.
      expect(plan.tone, NextWorkoutFocusTone.balanced);
      expect(plan.statusLabel, 'Balanced');
      expect(plan.headline.toLowerCase(), isNot(contains('add')));
    });
  });

  group('current-week default: empty current week shows the empty/gather state, '
      'NOT a rolling recent plan (PR #384 Finding 1)', () {
    // Phase 1 made the in-progress current week the DEFAULT period. The rolling
    // fallback (the #378 partial-week fix) must be GATED to CLOSED periods: when
    // the selected period is the current week and THIS week has no sessions
    // (summary == null), a user who trained recently but not since Monday must
    // NOT get a `recent` focus plan built from OLD history while the Training-
    // balance detail's default current-week window is empty — that contradiction
    // is exactly the class of P2 this fixes. Home must instead show the same
    // empty/gather state the detail shows (build() returns null => the plain
    // Training-balance nav row).

    // A Wednesday, mid-week, so "this week" is genuinely partial and empty here.
    final anchor = DateTime(2026, 6, 17, 12);

    // The user's only history is LAST week — nothing in the current week.
    final lastWeekSessions = [
      makeSession(
        id: 'chest-last-week',
        start: DateTime(2026, 6, 10, 9), // previous Wednesday
        name: 'Bench Press',
        muscles: const ['Chest', 'Triceps'],
        sets: 4,
      ),
      makeSession(
        id: 'back-last-week',
        start: DateTime(2026, 6, 11, 9),
        name: 'Lat Pulldown',
        muscles: const ['Lats', 'Biceps'],
        sets: 4,
      ),
    ];

    test('current-week period + no sessions this week => build() returns null '
        '(empty/gather state), NOT a recent plan from old history', () {
      // Sanity: the current-week window genuinely has no sessions...
      final window = BodyScorePeriod.currentWeek.resolve(
        anchor,
        firstWeekday: DateTime.monday,
      );
      expect(
        BodyScoreService().summarize(lastWeekSessions, range: window.range),
        isNull,
        reason: 'the current week must be empty for this case',
      );
      // ...while the rolling-to-today window DOES have data (so the un-gated
      // fallback would otherwise surface an old-history `recent` plan).
      expect(
        BodyScoreService().summarize(
          lastWeekSessions,
          range: rollingRangeToToday(days: 28, anchor: anchor),
        ),
        isNotNull,
        reason: 'old history exists in the rolling window',
      );

      // The default-constructed service uses the current-week period. With an
      // empty current week it returns null instead of the rolling recent plan,
      // mirroring the detail's empty/gather state.
      final plan = NextWorkoutFocusService().build(
        lastWeekSessions,
        anchor: anchor,
      );
      expect(plan, isNull);
    });

    test('the rolling fallback STILL works for a CLOSED period with old history',
        () {
      // Same data, but a CLOSED period (last full week) — which DOES contain the
      // old sessions, so this is the closed period's own data, not a fallback.
      // To exercise the fallback specifically, pick a closed period whose window
      // ends before the old sessions: last-4-full-weeks ends last Sunday, and the
      // old sessions (this set) land inside it, so instead use a period that is
      // empty but with rolling history. We assert the fallback path for closed
      // periods is intact using current-week sessions over a closed period.
      final thisWeekSessions = [
        makeSession(
          id: 'chest-this-week',
          start: anchor.subtract(const Duration(days: 2)),
          name: 'Bench Press',
          muscles: const ['Chest', 'Triceps'],
          sets: 4,
        ),
        makeSession(
          id: 'back-this-week',
          start: anchor.subtract(const Duration(days: 1)),
          name: 'Lat Pulldown',
          muscles: const ['Lats', 'Biceps'],
          sets: 4,
        ),
      ];
      const closedPeriod = BodyScorePeriod.last4FullWeeks;
      final closedWindow = closedPeriod.resolve(
        anchor,
        firstWeekday: DateTime.monday,
      );
      // Sanity: the closed window is empty (sessions are in the current week,
      // after the closed window end) but the rolling window has data.
      expect(
        BodyScoreService().summarize(
          thisWeekSessions,
          range: closedWindow.range,
        ),
        isNull,
      );

      final plan = NextWorkoutFocusService(
        period: closedPeriod,
      ).build(thisWeekSessions, anchor: anchor);

      // The rolling fallback still renders an early-signal/building read for the
      // CLOSED period (its original #378 purpose) — it is NOT gated away.
      expect(plan, isNotNull);
      expect(plan!.confidence, CoachConfidence.building);
      expect(plan.windowLabel, 'recent');
      expect(plan.tone, NextWorkoutFocusTone.earlySignal);
    });
  });

  group('current-week add-set copy reads naturally (PR #384 Finding 2)', () {
    // The add-set detail copy formats the window as "over the $windowLabel", but
    // the current-week label is "this week" — so the closed-period template would
    // render the ungrammatical "over the this week." For the current week the
    // copy must read naturally (e.g. "... of its weekly goal this week — aim for
    // about N more sets."), never "over the this week", and never a doubled
    // "this week ... this week."
    // A Wednesday so "this week" is partial; log only chest so another region
    // (e.g. core/back) sits at 0 of its weekly goal and yields an addSets cue.
    final anchor = DateTime(2026, 6, 17, 12);

    test('a current-week addSets plan detail reads naturally, not '
        '"over the this week"', () {
      final sessions = [
        makeSession(
          id: 'chest-this-week',
          start: DateTime(2026, 6, 17, 9),
          name: 'Bench Press',
          muscles: const ['Chest', 'Triceps'],
          sets: 4,
        ),
      ];

      final plan = NextWorkoutFocusService().build(sessions, anchor: anchor);
      expect(plan, isNotNull);
      expect(plan!.windowLabel, 'this week');
      // Sanity: this is genuinely an add-set (Build) plan, so the addSets copy
      // branch is exercised.
      expect(plan.statusLabel, 'Build');

      final detail = plan.detail;
      // The bug: "over the this week."
      expect(
        detail,
        isNot(contains('over the this week')),
        reason: 'current week must not render the ungrammatical "over the '
            'this week"',
      );
      // It still reads as a current-week add-set prompt.
      expect(detail, contains('this week'));
      expect(detail.toLowerCase(), contains('weekly goal'));
      // ...and the window phrase is not doubled ("this week ... this week").
      final firstThisWeek = detail.indexOf('this week');
      final lastThisWeek = detail.lastIndexOf('this week');
      expect(
        firstThisWeek,
        lastThisWeek,
        reason: 'the current-week copy must not repeat "this week"',
      );
    });

    test('a CLOSED period add-set plan keeps "over the <windowLabel>"', () {
      // The Finding 2 fix must NOT change closed-period copy. Use a closed
      // window with an under-target region so the addSets branch renders.
      const period = BodyScorePeriod.last4FullWeeks;
      final closedAnchor = DateTime(2026, 6, 15, 12); // a Monday.
      final window = period.resolve(closedAnchor, firstWeekday: DateTime.monday);
      DateTime dayInWindow(int weekOffset) =>
          window.range.start.add(Duration(days: weekOffset * 7 + 1, hours: 10));

      // Train everything but core hard each week so core lags over the closed
      // window and yields an addSets cue.
      final sessions = <WorkoutSession>[];
      for (var week = 0; week < 4; week++) {
        sessions.addAll([
          makeSession(
            id: 'chest-$week',
            start: dayInWindow(week),
            name: 'Bench Press',
            muscles: const ['Chest', 'Triceps'],
            sets: 5,
          ),
          makeSession(
            id: 'back-$week',
            start: dayInWindow(week).add(const Duration(days: 1)),
            name: 'Barbell Row',
            muscles: const ['Lats', 'Biceps'],
            sets: 5,
          ),
          makeSession(
            id: 'legs-$week',
            start: dayInWindow(week).add(const Duration(days: 2)),
            name: 'Back Squat',
            muscles: const ['Quads', 'Glutes', 'Hamstrings'],
            sets: 5,
          ),
          makeSession(
            id: 'delts-$week',
            start: dayInWindow(week).add(const Duration(days: 3)),
            name: 'Overhead Press',
            muscles: const ['Front Delts', 'Side Delts'],
            sets: 4,
          ),
        ]);
      }

      final plan = NextWorkoutFocusService(
        period: period,
      ).build(sessions, anchor: closedAnchor);
      expect(plan, isNotNull);
      expect(plan!.windowLabel, 'last 4 weeks');
      expect(plan.statusLabel, 'Build');
      // Closed periods are unchanged: the "over the <label>" phrasing remains.
      expect(plan.detail, contains('over the last 4 weeks'));
    });
  });

  group('rolling fallback when the closed period is empty', () {
    // The default last-4-full-weeks window ENDS before the current partial
    // week. A user whose only completed sessions are *this* week therefore
    // yields a null closed-period summary. Before the fallback, the home focus
    // card disappeared even though history exists; now it falls back to a
    // rolling-to-today read so the early-signal card still renders.
    test(
      'only current-partial-week sessions => card still renders as a rolling, '
      'building-confidence early read (not null)',
      () {
        const period = BodyScorePeriod.last4FullWeeks;
        // A Wednesday, mid-week, so "this week" is genuinely partial and the
        // closed last-4-full-weeks window ends last Sunday — before any of
        // these sessions.
        final anchor = DateTime(2026, 6, 17, 12);
        final window = period.resolve(anchor, firstWeekday: DateTime.monday);

        // Sanity: all sessions land in the current partial week, AFTER the
        // closed window's end, so the aligned closed-period summary is null.
        final sessions = [
          makeSession(
            id: 'chest-this-week',
            start: anchor.subtract(const Duration(days: 2)),
            name: 'Bench Press',
            muscles: const ['Chest', 'Triceps'],
            sets: 4,
          ),
          makeSession(
            id: 'back-this-week',
            start: anchor.subtract(const Duration(days: 1)),
            name: 'Lat Pulldown',
            muscles: const ['Lats', 'Biceps'],
            sets: 4,
          ),
        ];
        for (final s in sessions) {
          expect(
            s.startTime.isAfter(window.range.end),
            isTrue,
            reason: 'session must fall after the closed window end',
          );
        }
        expect(
          BodyScoreService().summarize(sessions, range: window.range),
          isNull,
          reason: 'the aligned closed-period summary must be empty here',
        );

        // Sanity: the rolling read here genuinely HAS 2+ sessions and an
        // under-target region, so the un-softened verdict would be a concrete
        // addSets cue. The fallback must downgrade it to gather-more anyway.
        final rollingSummary = BodyScoreService().summarize(
          sessions,
          range: rollingRangeToToday(days: 28, anchor: anchor),
        );
        expect(rollingSummary, isNotNull);
        expect(rollingSummary!.sessionCount, greaterThanOrEqualTo(2));
        final rawCue = BodyScoreCoach.overallCue(
          rollingSummary,
          recencyAware: false,
        );
        expect(
          rawCue.mode,
          anyOf(
            BodyScoreCoachingMode.addSets,
            BodyScoreCoachingMode.redistributeSets,
          ),
          reason: 'un-softened rolling verdict would be a concrete cue',
        );

        final plan = NextWorkoutFocusService(
          period: period,
        ).build(sessions, anchor: anchor);

        // The card still renders instead of disappearing.
        expect(plan, isNotNull);
        // It is a deliberately EARLY/ROLLING read: building confidence + a
        // rolling window label, never a confident closed-period verdict.
        expect(plan!.confidence, CoachConfidence.building);
        expect(plan.windowLabel, 'recent');
        expect(plan.windowLabel, isNot('last 4 weeks'));
        // ...and, crucially, an early-signal / gather-more plan — NOT the
        // concrete addSets/rebalance verdict the raw rolling cue would emit. So
        // Home matches the detail's gather-more state instead of contradicting
        // it with "Add N sets".
        expect(plan.tone, NextWorkoutFocusTone.earlySignal);
        expect(plan.statusLabel, 'Trending');
        expect(plan.suggestedSets, 0);
        expect(plan.secondaryRegion, isNull);
        expect(plan.headline, isNot(contains('Add')));
        expect(plan.headline, isNot(contains('Shift')));
        // It still surfaces a focus region (the card points somewhere).
        expect(plan.primaryRegion, isNotNull);
      },
    );
  });

  group('readiness context line (should I push today?)', () {
    const lowNote = 'Recovery is low today — a lighter session still counts.';
    const pushNote = 'You\'re recharged — a good day to push.';

    // Carries genuine recovery signal (hasRecoveryData true) by default; callers
    // override band/confidence/calibration per case.
    DailyRecoverySnapshot snapshot({
      RecoveryFlowBand? flowBand,
      RecoveryConfidence? confidence = RecoveryConfidence.high,
      bool isCalibrating = false,
      bool hasData = true,
    }) => DailyRecoverySnapshot(
      date: DateTime(2026, 4, 6),
      hrvValue: hasData ? 58 : null,
      hrvKind: hasData ? HrvKind.sdnn : null,
      baselineCoverageDays: 21,
      flowBand: flowBand,
      confidence: confidence,
      isCalibrating: isCalibrating,
    );

    test('null snapshot → no note', () {
      expect(NextWorkoutFocusService.readinessNoteFor(null), isNull);
    });

    test('no recovery signal (dataless) → no note', () {
      expect(
        NextWorkoutFocusService.readinessNoteFor(
          snapshot(flowBand: RecoveryFlowBand.recharge, hasData: false),
        ),
        isNull,
      );
    });

    test('still calibrating → no note', () {
      expect(
        NextWorkoutFocusService.readinessNoteFor(
          snapshot(flowBand: RecoveryFlowBand.recharge, isCalibrating: true),
        ),
        isNull,
      );
    });

    test('no band → no note', () {
      expect(
        NextWorkoutFocusService.readinessNoteFor(snapshot(flowBand: null)),
        isNull,
      );
    });

    test('low confidence suppresses the note on any band', () {
      expect(
        NextWorkoutFocusService.readinessNoteFor(
          snapshot(
            flowBand: RecoveryFlowBand.recharge,
            confidence: RecoveryConfidence.low,
          ),
        ),
        isNull,
      );
      expect(
        NextWorkoutFocusService.readinessNoteFor(
          snapshot(
            flowBand: RecoveryFlowBand.charged,
            confidence: RecoveryConfidence.low,
          ),
        ),
        isNull,
      );
    });

    test('lowest band (Recharge) with usable signal → lighter-session note', () {
      expect(
        NextWorkoutFocusService.readinessNoteFor(
          snapshot(flowBand: RecoveryFlowBand.recharge),
        ),
        lowNote,
      );
    });

    test('highest band (Charged) with good confidence → push note', () {
      expect(
        NextWorkoutFocusService.readinessNoteFor(
          snapshot(
            flowBand: RecoveryFlowBand.charged,
            confidence: RecoveryConfidence.medium,
          ),
        ),
        pushNote,
      );
    });

    test('middle bands (Steady / Ready) stay silent', () {
      expect(
        NextWorkoutFocusService.readinessNoteFor(
          snapshot(flowBand: RecoveryFlowBand.steady),
        ),
        isNull,
      );
      expect(
        NextWorkoutFocusService.readinessNoteFor(
          snapshot(flowBand: RecoveryFlowBand.ready),
        ),
        isNull,
      );
    });

    test('build() attaches the note onto the plan; null readiness leaves it '
        'null', () {
      final anchor = DateTime.utc(2026, 4, 6, 12);
      final sessions = [
        makeSession(
          id: 'chest',
          start: anchor.subtract(const Duration(days: 3)),
          name: 'Bench Press',
          muscles: const ['Chest', 'Triceps'],
          sets: 4,
        ),
      ];
      final service = NextWorkoutFocusService(
        period: BodyScorePeriod.last4FullWeeks,
      );

      final withReadiness = service.build(
        sessions,
        anchor: anchor,
        readiness: snapshot(flowBand: RecoveryFlowBand.recharge),
      );
      expect(withReadiness, isNotNull);
      expect(withReadiness!.readinessNote, lowNote);

      final withoutReadiness = service.build(sessions, anchor: anchor);
      expect(withoutReadiness, isNotNull);
      expect(withoutReadiness!.readinessNote, isNull);
    });
  });
}
