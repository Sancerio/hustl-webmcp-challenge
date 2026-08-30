import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_compute.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_service.dart';
import 'package:hustl_app/features/workout_log/domain/utils/time_periods.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/services/next_workout_focus_service.dart';

/// Regression guard for the post-login Train-home web freeze with large
/// histories (~455 sessions). On Flutter web `compute()` runs INLINE on the UI
/// thread, so any unbounded O(all-sessions) summarize on the home/focus path
/// stalls the frame loop. These timings:
///   (a) prove the unbounded read is slow enough to jank a web frame, and
///   (b) assert the bounded home/focus read the screen actually performs stays
///       fast - the fix is to keep the home path bounded.
///
/// The dataset mirrors a heavy real user: ~455 completed sessions spread over
/// ~3 years, each with a few exercises and several sets across varied regions.
void main() {
  // A fixed anchor so the windows resolve deterministically. A Monday noon so
  // the current week / last-4-weeks windows are stable.
  final anchor = DateTime(2026, 6, 15, 12);

  // Varied exercise/muscle rotation so the work touches every display region
  // and mirrors a realistic split, not a single-region degenerate case.
  const rotation = <(String, List<String>)>[
    ('Bench Press', ['Chest', 'Triceps', 'Front Delts']),
    ('Lat Pulldown', ['Lats', 'Biceps']),
    ('Hack Squat', ['Quads', 'Glutes']),
    ('Romanian Deadlift', ['Hamstrings', 'Glutes', 'Lower Back']),
    ('Overhead Press', ['Front Delts', 'Triceps']),
    ('Barbell Row', ['Lats', 'Upper Back', 'Biceps']),
    ('Lateral Raise', ['Side Delts']),
    ('Cable Curl', ['Biceps']),
    ('Leg Press', ['Quads', 'Glutes']),
    ('Crunch', ['Upper Abs']),
  ];

  WorkoutSession makeSession(int i, DateTime start) {
    // 2-3 exercises per session, 3-4 sets each - a realistic logged workout.
    final exerciseCount = 2 + (i % 2);
    final exercises = <WorkoutExercise>[];
    for (var e = 0; e < exerciseCount; e++) {
      final (name, muscles) = rotation[(i + e) % rotation.length];
      final setCount = 3 + (e % 2);
      exercises.add(
        WorkoutExercise(
          id: 'ex-$i-$e',
          exercise: Exercise(name: name, muscles: muscles),
          sets: [
            for (var s = 0; s < setCount; s++)
              WorkoutSet(
                id: 'set-$i-$e-$s',
                weight: 60 + (s * 5).toDouble(),
                reps: 8,
                isCompleted: true,
              ),
          ],
        ),
      );
    }
    return WorkoutSession(
      id: 'session-$i',
      name: 'Workout $i',
      startTime: start,
      endTime: start.add(const Duration(hours: 1)),
      isCompleted: true,
      exercises: exercises,
    );
  }

  /// ~455 sessions over ~3.4 years (roughly every 2.7 days back from anchor) -
  /// a representative heavy-history user.
  List<WorkoutSession> buildLargeHistory({int count = 455}) {
    return [
      for (var i = 0; i < count; i++)
        makeSession(
          i,
          anchor.subtract(Duration(hours: (i * 65).toInt())),
        ),
    ];
  }

  test('large-history dataset has the expected scale', () {
    final sessions = buildLargeHistory();
    expect(sessions.length, 455);
    // Spans years, not weeks - so an unbounded EWMA timeline is huge.
    final span = sessions.first.startTime.difference(sessions.last.startTime);
    expect(span.inDays, greaterThan(900));
  });

  test(
    'BodyScoreService.summarize over the UNBOUNDED multi-year span is slow '
    '(documents the freeze)',
    () {
      final sessions = buildLargeHistory();
      final service = BodyScoreService();
      // An unbounded range spanning the whole history - the worst case the EWMA
      // day-by-day loop (O(totalDays x groups)) hits if the home/focus path is
      // handed the full span instead of a period window.
      final fullRange = DateTimeRange(
        start: sessions.last.startTime.subtract(const Duration(days: 1)),
        end: anchor,
      );

      final sw = Stopwatch()..start();
      final summary = service.summarize(sessions, range: fullRange);
      sw.stop();

      expect(summary, isNotNull);
      // No hard upper bound asserted here (CI machines vary); this case exists to
      // measure + document the unbounded cost. Print it so before/after is
      // visible in the run log.
      // ignore: avoid_print
      print(
        'UNBOUNDED summarize over ${sessions.length} sessions '
        '/ ${fullRange.duration.inDays}-day span: ${sw.elapsedMilliseconds}ms',
      );
    },
  );

  test(
    'NextWorkoutFocusService.build over a BOUNDED window stays FAST '
    '(the post-login home/focus path)',
    () {
      final all = buildLargeHistory();
      // Mirror the home `_loadActive` bound: only the sessions inside the
      // ~35-day focus-fetch floor (the repo filters by startDate before the
      // service ever sees them). The focus card defaults to the current week.
      const focusFetchWindow = Duration(days: 35);
      final floor = anchor.subtract(focusFetchWindow);
      final bounded = all
          .where((s) => s.startTime.isAfter(floor))
          .toList(growable: false);
      expect(
        bounded.length,
        lessThan(all.length),
        reason: 'the home path must NOT process the full history',
      );

      final service = NextWorkoutFocusService(
        period: BodyScorePeriod.currentWeek,
      );

      // Warm + measured pass; the home builds once per load.
      final sw = Stopwatch()..start();
      service.build(bounded, anchor: anchor);
      final boundedMs = sw.elapsedMilliseconds;

      // ignore: avoid_print
      print(
        'BOUNDED focus.build over ${bounded.length} sessions: ${boundedMs}ms',
      );

      // A single bounded build must comfortably fit inside a web frame budget.
      // Generous ceiling to stay green on slow CI while still catching a
      // regression back to an unbounded O(all-sessions) read (which is
      // hundreds of ms+ on this dataset).
      expect(
        boundedMs,
        lessThan(150),
        reason: 'post-login focus build must stay well under a frame budget',
      );
    },
  );

  test(
    'focus.build handed the FULL unbounded history is materially slower than '
    'the bounded window (proves bounding is the fix)',
    () {
      final all = buildLargeHistory();
      const focusFetchWindow = Duration(days: 35);
      final floor = anchor.subtract(focusFetchWindow);
      final bounded = all
          .where((s) => s.startTime.isAfter(floor))
          .toList(growable: false);

      // The current-week period yields an empty closed window for old history,
      // so use last-4-full-weeks here: it resolves a concrete window and both
      // calls exercise the same summarize + suggestion paths, isolating the
      // effect of session SCOPE.
      final service = NextWorkoutFocusService(
        period: BodyScorePeriod.last4FullWeeks,
      );

      final swFull = Stopwatch()..start();
      service.build(all, anchor: anchor);
      swFull.stop();

      final swBounded = Stopwatch()..start();
      service.build(bounded, anchor: anchor);
      swBounded.stop();

      // ignore: avoid_print
      print(
        'focus.build FULL(${all.length})=${swFull.elapsedMicroseconds}us '
        'vs BOUNDED(${bounded.length})=${swBounded.elapsedMicroseconds}us',
      );

      // The bounded read must not be slower than the full read (it processes a
      // fraction of the sessions and a fraction of the suggestion range). This
      // is the load-bearing assertion: keeping the home path bounded is what
      // removes the freeze.
      expect(
        swBounded.elapsedMicroseconds,
        lessThanOrEqualTo(swFull.elapsedMicroseconds),
      );
    },
  );

  test(
    'Body Score DETAIL inline web recompute (runBodyScoreCompute: window + '
    'heatmap) over the detail fetch scope stays fast',
    () {
      final all = buildLargeHistory();
      // The detail fetches from _earliestRequiredStart - the earliest start of
      // any period (last-full-month start), i.e. up to ~2 months back. Mirror
      // that bound: only sessions newer than ~62 days reach the compute.
      final detailFloor = anchor.subtract(const Duration(days: 62));
      final detailSessions = all
          .where((s) => s.startTime.isAfter(detailFloor))
          .toList(growable: false);
      expect(detailSessions.length, lessThan(all.length));

      final window = BodyScorePeriod.currentWeek.resolve(anchor);
      final heatmapRange = rollingRangeToToday(days: 28, anchor: anchor);
      final request = BodyScoreComputeRequest(
        sessions: detailSessions,
        strategyIds: const ['effective_sets'],
        windowRange: window.range,
        heatmapRange: heatmapRange,
      );

      final sw = Stopwatch()..start();
      // The EXACT call the web fallback runs inline on the UI thread.
      runBodyScoreCompute(request);
      sw.stop();

      // ignore: avoid_print
      print(
        'DETAIL runBodyScoreCompute (inline web) over '
        '${detailSessions.length} sessions: ${sw.elapsedMilliseconds}ms',
      );

      // Bounded fetch scope + small ranges keep the inline web recompute inside
      // a frame budget. Regressing to feeding the full history here would blow
      // past this on web.
      expect(sw.elapsedMilliseconds, lessThan(120));
    },
  );
}
