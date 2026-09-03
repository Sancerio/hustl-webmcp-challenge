import '../../features/exercise_library/domain/models/exercise.dart';
import '../../features/workout_logging/domain/models/workout_exercise.dart';
import '../../features/workout_logging/domain/models/workout_session.dart';
import '../../features/workout_logging/domain/models/workout_set.dart';

/// Blueprint for one exercise inside a demo day's routine.
class _ExerciseBlueprint {
  const _ExerciseBlueprint({
    required this.slug,
    required this.name,
    required this.muscles,
    required this.sets,
    required this.baseWeight,
    required this.weightStep,
    required this.baseReps,
  });

  final String slug;
  final String name;

  /// First muscle gets weight 1.0 in the body-score mapper, the rest 0.5.
  final List<String> muscles;
  final int sets;

  /// Working weight in the very first (oldest) week.
  final double baseWeight;

  /// Linear load added per completed week (progressive overload).
  final double weightStep;
  final int baseReps;
}

/// One training day in the push/pull/legs/upper rotation.
class _DayBlueprint {
  const _DayBlueprint({required this.name, required this.exercises});

  final String name;
  final List<_ExerciseBlueprint> exercises;
}

/// Deterministic generator for Alex's 12-week / 4x-per-week training history.
///
/// All output is a pure function of the [anchor] date. No randomness and no
/// `DateTime.now()` calls live here, so the same anchor always yields byte-for
/// byte identical sessions (spec §10).
class DemoWorkoutSeed {
  DemoWorkoutSeed({required this.anchor});

  /// Local midnight of "today" for the demo.
  final DateTime anchor;

  static const int weeks = 12;
  static const int daysPerWeek = 4;

  /// 48 completed sessions for the persona.
  static const int sessionCount = weeks * daysPerWeek;

  /// The four weekdays (1 = Mon … 7 = Sun, `DateTime.weekday`) the persona
  /// trains on within each calendar week: Mon / Wed / Fri / Sat.
  ///
  /// Sessions are pinned to the *calendar* week (Mon–Sun) they belong to rather
  /// than counted backward in raw 7-day blocks from the anchor. That keeps every
  /// seed week inside a single ISO/calendar week, so the Progress "Volume · last
  /// 4 wk" delta and the Train-home weekly-volume trend bucket cleanly and climb
  /// with the progressive-overload ramp — instead of the newest block straddling
  /// two ISO weeks (which split the most-recent week into a tiny partial that
  /// read as a regression). The newest week is clamped to distinct days at or
  /// before the anchor (see [_buildSession]) so it never seeds a future date and
  /// the current calendar week always shows the climb's peak volume.
  static const List<int> _trainingWeekdays = [1, 3, 5, 6];

  /// push -> pull -> legs -> upper, repeated each week.
  static final List<_DayBlueprint> _rotation = [
    const _DayBlueprint(
      name: 'Chest Power',
      exercises: [
        _ExerciseBlueprint(
          slug: 'barbell-bench-press',
          name: 'Barbell Bench Press',
          muscles: ['Chest', 'Front Delts', 'Triceps'],
          sets: 4,
          baseWeight: 70,
          weightStep: 2.0,
          baseReps: 8,
        ),
        _ExerciseBlueprint(
          slug: 'incline-dumbbell-press',
          name: 'Incline Dumbbell Press',
          muscles: ['Upper Chest', 'Front Delts'],
          sets: 3,
          baseWeight: 26,
          weightStep: 0.75,
          baseReps: 10,
        ),
        _ExerciseBlueprint(
          slug: 'overhead-press',
          name: 'Overhead Press',
          muscles: ['Front Delts', 'Triceps'],
          sets: 3,
          baseWeight: 42,
          weightStep: 1.0,
          baseReps: 8,
        ),
        _ExerciseBlueprint(
          slug: 'lateral-raise',
          name: 'Dumbbell Lateral Raise',
          muscles: ['Side Delts'],
          sets: 3,
          baseWeight: 11,
          weightStep: 0.4,
          baseReps: 14,
        ),
        _ExerciseBlueprint(
          slug: 'cable-fly',
          name: 'Cable Chest Fly',
          muscles: ['Chest'],
          sets: 4,
          baseWeight: 20,
          weightStep: 0.5,
          baseReps: 14,
        ),
        _ExerciseBlueprint(
          slug: 'triceps-pushdown',
          name: 'Cable Triceps Pushdown',
          muscles: ['Triceps'],
          sets: 3,
          baseWeight: 28,
          weightStep: 0.75,
          baseReps: 12,
        ),
        _ExerciseBlueprint(
          slug: 'cable-crunch',
          name: 'Cable Crunch',
          muscles: ['Upper Abs', 'Lower Abs'],
          sets: 4,
          baseWeight: 45,
          weightStep: 1.0,
          baseReps: 15,
        ),
      ],
    ),
    const _DayBlueprint(
      name: 'Pull Power',
      exercises: [
        _ExerciseBlueprint(
          slug: 'deadlift',
          name: 'Barbell Deadlift',
          muscles: ['Lower Back', 'Lats', 'Glutes'],
          sets: 3,
          baseWeight: 120,
          weightStep: 3.5,
          baseReps: 5,
        ),
        _ExerciseBlueprint(
          slug: 'pull-up',
          name: 'Weighted Pull-up',
          muscles: ['Lats', 'Biceps'],
          sets: 4,
          baseWeight: 6,
          weightStep: 0.6,
          baseReps: 8,
        ),
        _ExerciseBlueprint(
          slug: 'barbell-row',
          name: 'Barbell Row',
          muscles: ['Lats', 'Rhomboids', 'Rear Delts'],
          sets: 3,
          baseWeight: 72,
          weightStep: 1.5,
          baseReps: 9,
        ),
        _ExerciseBlueprint(
          slug: 'lat-pulldown',
          name: 'Lat Pulldown',
          muscles: ['Lats', 'Biceps'],
          sets: 3,
          baseWeight: 58,
          weightStep: 1.0,
          baseReps: 11,
        ),
        _ExerciseBlueprint(
          slug: 'barbell-curl',
          name: 'Barbell Curl',
          muscles: ['Biceps', 'Forearms'],
          sets: 3,
          baseWeight: 32,
          weightStep: 0.6,
          baseReps: 10,
        ),
        _ExerciseBlueprint(
          slug: 'hanging-knee-raise',
          name: 'Hanging Knee Raise',
          muscles: ['Lower Abs', 'Obliques'],
          sets: 2,
          baseWeight: 0,
          weightStep: 0,
          baseReps: 16,
        ),
      ],
    ),
    const _DayBlueprint(
      name: 'Leg Power',
      exercises: [
        _ExerciseBlueprint(
          slug: 'back-squat',
          name: 'Barbell Back Squat',
          muscles: ['Quads', 'Glutes'],
          sets: 4,
          baseWeight: 100,
          weightStep: 3.0,
          baseReps: 6,
        ),
        _ExerciseBlueprint(
          slug: 'leg-press',
          name: 'Leg Press',
          muscles: ['Quads', 'Glutes'],
          sets: 3,
          baseWeight: 180,
          weightStep: 5.0,
          baseReps: 12,
        ),
        _ExerciseBlueprint(
          slug: 'leg-extension',
          name: 'Leg Extension',
          muscles: ['Quads'],
          sets: 3,
          baseWeight: 60,
          weightStep: 1.5,
          baseReps: 14,
        ),
        // Hamstrings get a single, lighter-volume slot so the body score reads
        // them as lagging relative to the quad-heavy legs muscle group.
        _ExerciseBlueprint(
          slug: 'romanian-deadlift',
          name: 'Romanian Deadlift',
          muscles: ['Hamstrings', 'Glutes'],
          sets: 2,
          baseWeight: 80,
          weightStep: 2.0,
          baseReps: 10,
        ),
        _ExerciseBlueprint(
          slug: 'standing-calf-raise',
          name: 'Standing Calf Raise',
          muscles: ['Calves'],
          sets: 3,
          baseWeight: 90,
          weightStep: 2.0,
          baseReps: 14,
        ),
      ],
    ),
    const _DayBlueprint(
      name: 'Push Power',
      exercises: [
        _ExerciseBlueprint(
          slug: 'incline-bench-press',
          name: 'Incline Barbell Press',
          muscles: ['Upper Chest', 'Front Delts', 'Triceps'],
          sets: 4,
          baseWeight: 58,
          weightStep: 1.5,
          baseReps: 8,
        ),
        _ExerciseBlueprint(
          slug: 'flat-dumbbell-press',
          name: 'Flat Dumbbell Press',
          muscles: ['Chest', 'Triceps'],
          sets: 4,
          baseWeight: 30,
          weightStep: 0.75,
          baseReps: 10,
        ),
        _ExerciseBlueprint(
          slug: 'chest-supported-row',
          name: 'Chest-Supported Row',
          muscles: ['Rhomboids', 'Lats', 'Rear Delts'],
          sets: 4,
          baseWeight: 64,
          weightStep: 1.25,
          baseReps: 10,
        ),
        _ExerciseBlueprint(
          slug: 'arnold-press',
          name: 'Arnold Press',
          muscles: ['Side Delts', 'Front Delts'],
          sets: 3,
          baseWeight: 18,
          weightStep: 0.5,
          baseReps: 11,
        ),
        _ExerciseBlueprint(
          slug: 'face-pull',
          name: 'Cable Face Pull',
          muscles: ['Rear Delts', 'Upper Traps'],
          sets: 3,
          baseWeight: 24,
          weightStep: 0.6,
          baseReps: 15,
        ),
        _ExerciseBlueprint(
          slug: 'hammer-curl',
          name: 'Dumbbell Hammer Curl',
          muscles: ['Biceps', 'Forearms'],
          sets: 3,
          baseWeight: 14,
          weightStep: 0.4,
          baseReps: 12,
        ),
        _ExerciseBlueprint(
          slug: 'hanging-leg-raise',
          name: 'Hanging Leg Raise',
          muscles: ['Lower Abs', 'Obliques'],
          sets: 3,
          baseWeight: 0,
          weightStep: 0,
          baseReps: 14,
        ),
      ],
    ),
  ];

  /// Local Monday (midnight) of the calendar week the [anchor] falls in.
  DateTime get _anchorWeekStart =>
      anchor.subtract(Duration(days: anchor.weekday - 1));

  /// Weekday-of-month placement for each training day of a given week, with the
  /// newest week (weeksAgo == 0) clamped so every session lands on a distinct
  /// weekday at or before the anchor's weekday — never a future date, never two
  /// sessions stacked on one day. Older weeks use the plain Mon/Wed/Fri/Sat
  /// schedule. Returned values are `DateTime.weekday` (1 = Mon … 7 = Sun).
  List<int> _weekdaysForWeek(int weeksAgo) {
    if (weeksAgo > 0) return _trainingWeekdays;
    final anchorWeekday = anchor.weekday; // 1..7
    final result = List<int>.filled(daysPerWeek, 0);
    final used = <int>{};
    final overflow = <int>[];
    // Keep any scheduled day that already sits at/before the anchor weekday.
    for (var d = 0; d < daysPerWeek; d++) {
      final wd = _trainingWeekdays[d];
      if (wd <= anchorWeekday) {
        result[d] = wd;
        used.add(wd);
      } else {
        overflow.add(d);
      }
    }
    // Pull any later-in-week days back onto the latest free weekday ≤ anchor.
    var candidate = anchorWeekday;
    for (final d in overflow) {
      while (candidate >= 1 && used.contains(candidate)) {
        candidate--;
      }
      if (candidate < 1) candidate = 1;
      result[d] = candidate;
      used.add(candidate);
      candidate--;
    }
    return result;
  }

  /// The day index of the newest week's most-recent session by date+time, which
  /// carries the PR flags. Ties on the same clamped weekday resolve to the later
  /// rotation slot (higher [dayIndex] = later start time), so "Push Power"
  /// (dayIndex 3) stays the latest session even when the current week collapses
  /// onto a single weekday.
  int get _latestDayIndex {
    final weekdays = _weekdaysForWeek(0);
    var latest = 0;
    for (var d = 1; d < weekdays.length; d++) {
      if (weekdays[d] >= weekdays[latest]) latest = d;
    }
    return latest;
  }

  /// All 48 completed sessions, newest first.
  List<WorkoutSession> buildSessions() {
    final sessions = <WorkoutSession>[];
    // Each seed week maps to one real calendar week (Mon–Sun); sessions land on
    // fixed weekdays inside it. The newest week is the anchor's own calendar
    // week, older weeks step back a full 7 days each, so every week buckets into
    // a single ISO week and the recent-volume trend climbs cleanly.
    for (var w = 0; w < weeks; w++) {
      for (var d = 0; d < daysPerWeek; d++) {
        final globalIndex = w * daysPerWeek + d;
        // weeksAgo counts down so older weeks are further in the past.
        final weeksAgo = (weeks - 1) - w;
        final session = _buildSession(
          weekIndex: w,
          dayIndex: d,
          weeksAgo: weeksAgo,
          globalIndex: globalIndex,
        );
        sessions.add(session);
      }
    }
    // Newest first for screens that expect descending order.
    sessions.sort((a, b) => b.startTime.compareTo(a.startTime));
    return sessions;
  }

  WorkoutSession _buildSession({
    required int weekIndex,
    required int dayIndex,
    required int weeksAgo,
    required int globalIndex,
  }) {
    final blueprint = _rotation[dayIndex % _rotation.length];
    // Pin to the calendar week this seed week represents, then to the chosen
    // weekday inside it (clamped for the current week so nothing is future-dated).
    final weekMonday = _anchorWeekStart.subtract(Duration(days: weeksAgo * 7));
    final weekday = _weekdaysForWeek(weeksAgo)[dayIndex];
    // Stagger the start time by the rotation order so that when the current
    // week's days collapse onto a single weekday (early-week anchor clamp), the
    // sessions stay chronologically ordered push→pull→legs→upper — keeping
    // "Push Power" (dayIndex 3) the most-recent session and a clean History
    // order. On a normal week each weekday holds one session, so this only ever
    // disambiguates same-day ties.
    final startHour = 15 + dayIndex; // 15:15, 16:15, 17:15, 18:15
    final start = weekMonday
        .add(Duration(days: weekday - 1))
        .add(Duration(hours: startHour, minutes: 15));
    final end = start.add(const Duration(minutes: 58));

    // The most recent session by DATE carries the PRs. With the newest week's
    // weekdays clamped at/before the anchor, the latest day is no longer a fixed
    // dayIndex, so we resolve it from the clamped schedule instead of pinning to
    // globalIndex.
    final isLatest = weekIndex == weeks - 1 && dayIndex == _latestDayIndex;

    final exercises = <WorkoutExercise>[];
    for (var e = 0; e < blueprint.exercises.length; e++) {
      final bp = blueprint.exercises[e];
      exercises.add(
        _buildExercise(
          bp: bp,
          weekIndex: weekIndex,
          exerciseIndex: e,
          sessionId: 'demo-w$weekIndex-d$dayIndex',
          markPrs: isLatest,
        ),
      );
    }

    return WorkoutSession(
      id: 'demo-session-$globalIndex',
      name: blueprint.name,
      startTime: start,
      endTime: end,
      exercises: exercises,
      isCompleted: true,
      dirty: false,
      lastUpdatedAt: end,
    );
  }

  WorkoutExercise _buildExercise({
    required _ExerciseBlueprint bp,
    required int weekIndex,
    required int exerciseIndex,
    required String sessionId,
    required bool markPrs,
  }) {
    final weight = _weightForWeek(bp, weekIndex);
    final sets = <WorkoutSet>[];
    for (var s = 0; s < bp.sets; s++) {
      // Last working set on the first two exercises of the newest session is a
      // PR (3 total across the session's first exercises).
      final isPrSet = markPrs && exerciseIndex < 3 && s == bp.sets - 1;
      sets.add(
        WorkoutSet(
          id: '$sessionId-${bp.slug}-set$s',
          weight: bp.baseWeight == 0 ? 0 : weight,
          reps: bp.baseReps + (s == bp.sets - 1 && isPrSet ? 1 : 0),
          rpe: 8 + (s == bp.sets - 1 ? 1 : 0),
          isCompleted: true,
          isPr: isPrSet,
          completedAt: null,
        ),
      );
    }

    final exercise = Exercise(
      id: bp.slug,
      slug: bp.slug,
      name: bp.name,
      muscles: bp.muscles,
      kind: ExerciseKind.strength,
      loggingMode: ExerciseLoggingMode.weightReps,
    );

    return WorkoutExercise(
      id: '$sessionId-${bp.slug}',
      exercise: exercise,
      sets: sets,
      restTimerSeconds: 120,
    );
  }

  double _weightForWeek(_ExerciseBlueprint bp, int weekIndex) {
    if (bp.baseWeight == 0) return 0;
    final raw = bp.baseWeight + bp.weightStep * weekIndex;
    // Round to the nearest 0.5 kg for tidy display.
    return (raw * 2).roundToDouble() / 2;
  }
}
