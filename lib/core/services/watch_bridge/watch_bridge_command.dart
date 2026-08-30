enum WatchCommandType {
  restStart,
  restStop,
  navNextExercise,
  navPrevExercise,
  endWorkout,
  discardWorkout,
  startWorkout,
  startWorkoutFromTemplate,
  startWorkoutFromRecent,
  markSetComplete,
  logSet,
  // Watch -> phone: append an empty set to the current exercise (increase the set
  // count) so the user can keep logging past the planned sets, then log it.
  addSet,
  addExercise,
  // Watch -> phone: ask the phone for a bounded slice of the exercise library to
  // populate the on-watch picker. Optionally carries a free-text `searchQuery`
  // (from the `.searchable` field / dictation) to filter server-side.
  exerciseCatalogRequest,
}

class WatchCommand {
  const WatchCommand({
    required this.id,
    required this.type,
    this.sessionId,
    this.durationSec,
    this.templateId,
    this.workoutId,
    this.exerciseId,
    this.exerciseName,
    this.exerciseSlug,
    this.searchQuery,
    this.weight,
    this.reps,
    this.rpe,
    this.clearRpe = false,
    this.setCount,
  });

  final String id;
  final WatchCommandType type;
  final String? sessionId;
  final int? durationSec;
  final String? templateId;
  final String? workoutId;
  final String? exerciseId;
  // The exact library name chosen in the on-watch picker (e.g. "Pull Up"). When
  // present the phone adds THIS exercise instead of a blank "Exercise N".
  final String? exerciseName;
  // Optional canonical slug so the phone can match history/previous sets even
  // when the display name differs slightly.
  final String? exerciseSlug;
  // Free-text query for an exercise_catalog_request (search/dictation).
  final String? searchQuery;
  final double? weight;
  final int? reps;

  /// User-entered set effort. Watch UI emits whole-number RPE 4-10
  /// (the persisted equivalent of its user-facing RIR 6+ through 0 scale).
  final int? rpe;

  /// Explicitly clears a prefilled RPE. Kept separate because WatchConnectivity
  /// payloads cannot represent a property-list null reliably.
  final bool clearRpe;
  final int? setCount;

  static WatchCommand? tryParse(Map<String, dynamic> map) {
    final typeRaw = map['type'];
    final idRaw = map['id'];
    if (typeRaw is! String || idRaw is! String) return null;

    final type = switch (typeRaw) {
      'rest_start' => WatchCommandType.restStart,
      'rest_stop' => WatchCommandType.restStop,
      'nav_next_exercise' => WatchCommandType.navNextExercise,
      'nav_prev_exercise' => WatchCommandType.navPrevExercise,
      'end_workout' => WatchCommandType.endWorkout,
      'discard_workout' => WatchCommandType.discardWorkout,
      'start_workout' => WatchCommandType.startWorkout,
      'start_workout_from_template' =>
        WatchCommandType.startWorkoutFromTemplate,
      'start_workout_from_recent' => WatchCommandType.startWorkoutFromRecent,
      'mark_set_complete' => WatchCommandType.markSetComplete,
      'log_set' => WatchCommandType.logSet,
      'add_set' => WatchCommandType.addSet,
      'add_exercise' => WatchCommandType.addExercise,
      'exercise_catalog_request' => WatchCommandType.exerciseCatalogRequest,
      _ => null,
    };
    if (type == null) return null;

    return WatchCommand(
      id: idRaw,
      type: type,
      sessionId: map['sessionId'] as String?,
      durationSec: (map['durationSec'] as num?)?.toInt(),
      templateId: map['templateId'] as String?,
      workoutId: map['workoutId'] as String?,
      exerciseId: map['exerciseId'] as String?,
      exerciseName: (map['exerciseName'] as String?),
      exerciseSlug: (map['exerciseSlug'] as String?),
      searchQuery: (map['searchQuery'] as String?),
      weight: (map['weight'] as num?)?.toDouble(),
      reps: (map['reps'] as num?)?.toInt(),
      rpe: (map['rpe'] as num?)?.toInt(),
      clearRpe: map['clearRpe'] == true,
      setCount: (map['setCount'] as num?)?.toInt(),
    );
  }
}

/// A single set captured on the watch while the phone was absent.
class WatchSessionSet {
  const WatchSessionSet({
    required this.weight,
    required this.reps,
    this.rpe,
    bool? rpeKnown,
    this.isCompleted = true,
    this.completedAtMs,
  }) : rpeKnown = rpeKnown ?? rpe != null;

  final double weight;
  final int reps;
  final int? rpe;

  /// True when the sending Watch understands the RPE field. When true, a null
  /// [rpe] is an explicit clear; false means a legacy payload omitted the field
  /// and phone data must be preserved.
  final bool rpeKnown;
  final bool isCompleted;
  final int? completedAtMs;

  static WatchSessionSet? tryParse(Map<String, dynamic> map) {
    final weight = (map['weight'] as num?)?.toDouble();
    final reps = (map['reps'] as num?)?.toInt();
    if (weight == null || reps == null) return null;
    return WatchSessionSet(
      weight: weight,
      reps: reps,
      rpe: (map['rpe'] as num?)?.toInt(),
      rpeKnown: map['rpeKnown'] == true || map.containsKey('rpe'),
      isCompleted: map['isCompleted'] is bool
          ? map['isCompleted'] as bool
          : true,
      completedAtMs: (map['completedAtMs'] as num?)?.toInt(),
    );
  }
}

/// A single exercise (with its completed sets) captured on the watch.
class WatchSessionExercise {
  const WatchSessionExercise({
    required this.name,
    this.exerciseId,
    this.exerciseLoggingMode,
    this.sets = const [],
  });

  final String name;
  final String? exerciseId;
  final String? exerciseLoggingMode;
  final List<WatchSessionSet> sets;

  static WatchSessionExercise? tryParse(Map<String, dynamic> map) {
    final name = (map['name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;
    final loggingModeRaw = map['exerciseLoggingMode'] ?? map['loggingMode'];
    final setsRaw = map['sets'];
    final sets = <WatchSessionSet>[];
    if (setsRaw is List) {
      for (final raw in setsRaw) {
        if (raw is! Map) continue;
        final set = WatchSessionSet.tryParse(Map<String, dynamic>.from(raw));
        if (set != null) sets.add(set);
      }
    }
    return WatchSessionExercise(
      name: name,
      exerciseId: (map['exerciseId'] as String?),
      exerciseLoggingMode: loggingModeRaw is String ? loggingModeRaw : null,
      sets: sets,
    );
  }
}

/// A full, self-contained workout the watch recorded while the phone was
/// absent. Reconciled into the phone's repository idempotently (by [id] or
/// [hkWorkoutUuid]) when connectivity is restored.
class WatchSession {
  const WatchSession({
    required this.id,
    required this.startedAtMs,
    this.endedAtMs,
    this.inProgress = false,
    this.snapshotMs,
    this.activityType,
    this.hkWorkoutUuid,
    this.avgHr,
    this.maxHr,
    this.activeEnergyKcal,
    this.durationSec,
    this.exercises = const [],
  });

  final String id;
  final int startedAtMs;
  // Null while the workout is still in progress on the watch (live handoff).
  final int? endedAtMs;
  final bool inProgress;
  // Snapshot time (last-writer-wins when the phone reconciles an in-progress session).
  final int? snapshotMs;
  final String? activityType;
  final String? hkWorkoutUuid;
  final double? avgHr;
  final double? maxHr;
  final double? activeEnergyKcal;
  final int? durationSec;
  final List<WatchSessionExercise> exercises;

  static WatchSession? tryParse(Map<String, dynamic> map) {
    if (map['type'] != 'watch_session') return null;
    final id = map['id'];
    final startedAtMs = (map['startedAtMs'] as num?)?.toInt();
    final endedAtMs = (map['endedAtMs'] as num?)?.toInt();
    if (id is! String || id.isEmpty) return null;
    if (startedAtMs == null) return null;
    final inProgress = map['inProgress'] == true || endedAtMs == null;

    final exercisesRaw = map['exercises'];
    final exercises = <WatchSessionExercise>[];
    if (exercisesRaw is List) {
      for (final raw in exercisesRaw) {
        if (raw is! Map) continue;
        final exercise = WatchSessionExercise.tryParse(
          Map<String, dynamic>.from(raw),
        );
        if (exercise != null) exercises.add(exercise);
      }
    }

    return WatchSession(
      id: id,
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
      inProgress: inProgress,
      snapshotMs: (map['ts'] as num?)?.toInt(),
      activityType: map['activityType'] as String?,
      hkWorkoutUuid: map['hkWorkoutUuid'] as String?,
      avgHr: (map['avgHr'] as num?)?.toDouble(),
      maxHr: (map['maxHr'] as num?)?.toDouble(),
      activeEnergyKcal: (map['activeEnergyKcal'] as num?)?.toDouble(),
      durationSec: (map['durationSec'] as num?)?.toInt(),
      exercises: exercises,
    );
  }
}
