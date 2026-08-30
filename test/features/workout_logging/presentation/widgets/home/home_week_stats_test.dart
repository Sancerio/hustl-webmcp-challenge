import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/home_week_stats.dart';

/// A realistic completed session: 6 exercises x 4 working sets, so each session
/// drives ~24 set iterations through [WorkoutSession.calculateTotalVolume] AND
/// another ~24 through the working-set tally - the exact nested per-set work the
/// freeze repro is about.
WorkoutSession _session(String id, DateTime start) => WorkoutSession(
  id: id,
  name: 'Session $id',
  startTime: start,
  endTime: start.add(const Duration(hours: 1)),
  isCompleted: true,
  exercises: [
    for (var e = 0; e < 6; e++)
      WorkoutExercise(
        id: '$id-ex$e',
        exercise: Exercise(name: 'Lift $e', muscles: const ['Chest']),
        sets: [
          for (var setIndex = 0; setIndex < 4; setIndex++)
            WorkoutSet(
              id: '$id-ex$e-s$setIndex',
              weight: 100,
              reps: 5,
              isCompleted: true,
            ),
        ],
      ),
  ],
);

/// ~450 completed sessions spread one-per-day back from [now], emulating a
/// large-history account (the freeze repro: ~450 sessions on the web UI thread).
List<WorkoutSession> _largeHistory(DateTime now, {int count = 450}) => [
  for (var i = 0; i < count; i++)
    _session('s$i', now.subtract(Duration(days: i))),
];

void main() {
  group('HomeWeekStats bounds the work to the displayed window', () {
    test('only iterates sessions inside the display window, not all history', () {
      final now = DateTime(2026, 6, 19, 10);
      final sessions = _largeHistory(now);

      // Count how many sessions actually fall inside the displayed window
      // (current week + the 6-week trend). For a one-per-day history that is a
      // small constant (~7 weeks of days), NOT all 450.
      final floor = now.subtract(HomeWeekStats.displayWindow);
      final inWindow = sessions.where((s) => s.startTime.isAfter(floor)).length;

      expect(
        sessions.length,
        greaterThan(400),
        reason: 'sanity: this is a large-history account',
      );
      expect(
        inWindow,
        lessThan(60),
        reason:
            'the displayed window is ~7 calendar weeks, so the aggregation only '
            'needs a small slice - never all ~450 sessions',
      );
    });

    test(
      'displayed numbers are identical whether fed all history or only the '
      'in-window slice (bounding changes nothing the UI shows)',
      () {
        final now = DateTime(2026, 6, 19, 10);
        final all = _largeHistory(now);
        final floor = now.subtract(HomeWeekStats.displayWindow);
        final sliced = all.where((s) => s.startTime.isAfter(floor)).toList();

        final fromAll = HomeWeekStats.from(all, now: now);
        final fromSliced = HomeWeekStats.from(sliced, now: now);

        // Every figure the dashboard renders must match: bounding the input is
        // a pure optimisation, not a behaviour change.
        expect(fromAll.weekVolume, fromSliced.weekVolume);
        expect(fromAll.weekSets, fromSliced.weekSets);
        expect(fromAll.weekWorkouts, fromSliced.weekWorkouts);
        expect(fromAll.weeklyVolumes, fromSliced.weeklyVolumes);
        expect(
          fromAll.days.map((d) => (d.volume, d.sets, d.isToday)).toList(),
          fromSliced.days.map((d) => (d.volume, d.sets, d.isToday)).toList(),
        );
      },
    );

    test('the volume trend never exceeds maxTrendWeeks even on deep history', () {
      final now = DateTime(2026, 6, 19, 10);
      final stats = HomeWeekStats.from(_largeHistory(now), now: now);
      expect(
        stats.weeklyVolumes.length,
        lessThanOrEqualTo(HomeWeekStats.maxTrendWeeks),
      );
    });

    test(
      'aggregating ~450 sessions is fast (off the UI thread is not enough on '
      'Flutter web - it must also be cheap)',
      () {
        final now = DateTime(2026, 6, 19, 10);
        final sessions = _largeHistory(now);

        // Warm up, then time a single pass. This is a coarse guard, not a
        // microbenchmark: a regression that reintroduces O(all-sessions x sets)
        // work would blow far past this on the constrained web UI thread.
        HomeWeekStats.from(sessions, now: now);
        final sw = Stopwatch()..start();
        HomeWeekStats.from(sessions, now: now);
        sw.stop();

        expect(
          sw.elapsedMilliseconds,
          lessThan(50),
          reason:
              'bounded aggregation must stay well under a frame budget; '
              'took ${sw.elapsedMilliseconds}ms',
        );
      },
    );
  });
}
