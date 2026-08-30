import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/workout_progress_utils.dart';

void main() {
  WorkoutSession makeSession({
    required String id,
    required String name,
    required DateTime start,
    required double weight,
    required int reps,
    String exerciseName = 'Ex',
  }) {
    final exercise = Exercise(name: exerciseName, muscles: const []);
    final workoutExercise = WorkoutExercise(
      id: 'we$id',
      exercise: exercise,
      sets: [
        WorkoutSet(id: 's$id', weight: weight, reps: reps, isCompleted: true),
      ],
    );
    return WorkoutSession(
      id: id,
      name: name,
      startTime: start,
      exercises: [workoutExercise],
      isCompleted: true,
    );
  }

  test('volumeByWorkout aggregates total volume by name', () {
    final sessions = [
      makeSession(
        id: '1',
        name: 'Upper',
        start: DateTime(2024, 1, 1),
        weight: 10,
        reps: 5,
      ),
      makeSession(
        id: '2',
        name: 'Upper',
        start: DateTime(2024, 1, 2),
        weight: 20,
        reps: 5,
      ),
      makeSession(
        id: '3',
        name: 'Lower',
        start: DateTime(2024, 1, 3),
        weight: 30,
        reps: 5,
      ),
    ];

    final result = volumeByWorkout(sessions);
    expect(result['Upper'], 10 * 5 + 20 * 5);
    expect(result['Lower'], 30 * 5);
  });

  test('filterSessionsByDate restricts to selected range', () {
    final sessions = [
      makeSession(
        id: '1',
        name: 'Upper',
        start: DateTime(2024, 1, 1),
        weight: 10,
        reps: 5,
      ),
      makeSession(
        id: '2',
        name: 'Upper',
        start: DateTime(2024, 2, 1),
        weight: 20,
        reps: 5,
      ),
      makeSession(
        id: '3',
        name: 'Lower',
        start: DateTime(2024, 3, 1),
        weight: 30,
        reps: 5,
      ),
    ];

    final range = DateTimeRange(
      start: DateTime(2024, 1, 15),
      end: DateTime(2024, 2, 15),
    );

    final filtered = filterSessionsByDate(sessions, range);
    expect(filtered.length, 1);
    expect(filtered.first.id, '2');
  });

  test('filterSessionsByDate includes boundary dates', () {
    final sessions = [
      makeSession(
        id: '1',
        name: 'Upper',
        start: DateTime(2024, 1, 1),
        weight: 10,
        reps: 5,
      ),
      makeSession(
        id: '2',
        name: 'Upper',
        start: DateTime(2024, 1, 31),
        weight: 20,
        reps: 5,
      ),
    ];

    final range = DateTimeRange(
      start: DateTime(2024, 1, 1),
      end: DateTime(2024, 1, 31),
    );

    final filtered = filterSessionsByDate(sessions, range);
    expect(filtered.length, 2);
  });

  test('filterSessionsByDate includes sessions on end date', () {
    final sessions = [
      makeSession(
        id: '1',
        name: 'Upper',
        start: DateTime(2024, 1, 31, 23, 59),
        weight: 10,
        reps: 5,
      ),
    ];

    final range = DateTimeRange(
      start: DateTime(2024, 1, 1),
      end: DateTime(2024, 1, 31),
    );

    final filtered = filterSessionsByDate(sessions, range);
    expect(filtered.length, 1);
  });

  test('aggregateWeeklyVolume groups by ISO week', () {
    final sessions = [
      makeSession(
        id: '1',
        name: 'A',
        start: DateTime(2024, 1, 1),
        weight: 10,
        reps: 5,
      ),
      makeSession(
        id: '2',
        name: 'B',
        start: DateTime(2024, 1, 3),
        weight: 20,
        reps: 5,
      ),
    ];

    final result = aggregateWeeklyVolume(sessions);
    expect(result.length, 1);
    expect(result.keys.first, '2024-W01');
    expect(result.values.first, 150);
  });

  test('aggregateWeeklyVolume handles year boundary', () {
    final sessions = [
      makeSession(
        id: '1',
        name: 'A',
        start: DateTime(2024, 12, 31),
        weight: 10,
        reps: 1,
      ),
    ];

    final result = aggregateWeeklyVolume(sessions);
    expect(result.keys.first, '2025-W01');
  });

  test('isoWeekNumber handles year boundary', () {
    expect(isoWeekNumber(DateTime(2024, 12, 31)), 1);
    expect(isoWeekNumber(DateTime(2025, 1, 1)), 1);
  });

  test('aggregateVolumeByPeriod groups by day', () {
    final sessions = [
      makeSession(
        id: '1',
        name: 'A',
        start: DateTime(2024, 1, 1),
        weight: 10,
        reps: 5,
      ),
      makeSession(
        id: '2',
        name: 'B',
        start: DateTime(2024, 1, 1),
        weight: 20,
        reps: 5,
      ),
      makeSession(
        id: '3',
        name: 'C',
        start: DateTime(2024, 1, 2),
        weight: 30,
        reps: 5,
      ),
    ];

    final result = aggregateVolumeByPeriod(sessions, TimeGroup.day);
    expect(result.length, 2);
    expect(result['2024-01-01'], 150);
    expect(result['2024-01-02'], 150);
  });

  test('sessionsByWorkout counts sessions', () {
    final sessions = [
      makeSession(
        id: '1',
        name: 'Upper',
        start: DateTime(2024, 1, 1),
        weight: 10,
        reps: 5,
      ),
      makeSession(
        id: '2',
        name: 'Upper',
        start: DateTime(2024, 1, 2),
        weight: 20,
        reps: 5,
      ),
      makeSession(
        id: '3',
        name: 'Lower',
        start: DateTime(2024, 1, 3),
        weight: 30,
        reps: 5,
      ),
    ];

    final result = sessionsByWorkout(sessions);
    expect(result['Upper'], 2);
    expect(result['Lower'], 1);
  });

  test('topPrsByWeight returns top N exercises by weight', () {
    final sessions = [
      for (int i = 0; i < 9; i++)
        makeSession(
          id: '$i',
          name: 'W$i',
          start: DateTime(2024, 1, 1),
          weight: (i + 1) * 10,
          reps: 1,
          exerciseName: 'E$i',
        ),
    ];

    final result = topPrsByWeight(sessions, limit: 8);
    expect(result.length, 8);
    expect(result.values.first, 90);
  });

  test('topE1rmByExercise ranks by est. 1RM, not raw weight', () {
    final start = DateTime(2024, 1, 1);
    final sessions = [
      // Both lift 100 kg, but the higher-rep set has the higher est. 1RM, so it
      // must rank first — the whole point of e1RM over raw max weight.
      makeSession(
        id: '1',
        name: 'A',
        start: start,
        weight: 100,
        reps: 1,
        exerciseName: 'Bench',
      ),
      makeSession(
        id: '2',
        name: 'B',
        start: start,
        weight: 100,
        reps: 10,
        exerciseName: 'Squat',
      ),
    ];

    final result = topE1rmByExercise(sessions);
    expect(result.keys.first, 'Squat');
    expect(result['Bench'], closeTo(100, 0.01));
    expect(result['Squat'], closeTo(100 * (1 + 10 / 30), 0.01));
  });

  test('topE1rmByExercise caps reps at 12 so high-rep sets cannot inflate', () {
    final sessions = [
      makeSession(
        id: '1',
        name: 'A',
        start: DateTime(2024, 1, 1),
        weight: 100,
        reps: 20,
        exerciseName: 'Leg press',
      ),
    ];

    // 20 reps capped to 12: 100·(1 + 12/30) = 140, not 100·(1 + 20/30) ≈ 166.7.
    final result = topE1rmByExercise(sessions);
    expect(result['Leg press'], closeTo(100 * (1 + 12 / 30), 0.01));
  });

  test('quickDateRange computes expected ranges', () {
    final now = DateTime(2024, 5, 15);
    final twoWeeks = quickDateRange(QuickDateRange.last2Weeks, now: now);
    expect(twoWeeks.end, DateTime(2024, 5, 15));
    expect(twoWeeks.start, DateTime(2024, 5, 2));

    final oneMonth = quickDateRange(QuickDateRange.last1Month, now: now);
    expect(oneMonth.start, DateTime(2024, 4, 15));
    expect(oneMonth.end, DateTime(2024, 5, 15));
  });

  test('goalHitWeeks counts weeks that met the goal in the window', () {
    final now = DateTime(2024, 5, 15); // a Wednesday
    String weekKey(DateTime d) {
      final week = isoWeekNumber(d);
      return '${startOfIsoWeek(d.year, week).year}-W'
          '${week.toString().padLeft(2, '0')}';
    }

    final thisWeek = weekKey(now);
    final lastWeek = weekKey(now.subtract(const Duration(days: 7)));
    final twoBack = weekKey(now.subtract(const Duration(days: 14)));

    final counts = {thisWeek: 3, lastWeek: 1, twoBack: 4};
    final hits = goalHitWeeks(
      countsByWeek: counts,
      weeklyGoal: 3,
      windowWeeks: 8,
      now: now,
    );
    // thisWeek (3) and twoBack (4) meet the goal; lastWeek (1) does not.
    expect(hits, 2);

    expect(
      goalHitWeeks(
        countsByWeek: counts,
        weeklyGoal: 3,
        windowWeeks: 0,
        now: now,
      ),
      0,
    );
  });
}
