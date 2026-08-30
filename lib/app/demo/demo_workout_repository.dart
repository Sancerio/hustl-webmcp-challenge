import '../../features/workout_logging/domain/models/workout_exercise.dart';
import '../../features/workout_logging/domain/models/workout_session.dart';
import '../../features/workout_logging/domain/models/workout_set.dart';
import '../../features/workout_logging/domain/repositories/workout_repository.dart';
import 'demo_workout_seed.dart';

/// Deterministic in-memory [WorkoutRepository] for demo mode.
///
/// Seeded with Alex's 12-week push/pull/legs/upper history (48 completed
/// sessions, progressive overload, 3 PRs in the newest session). Mutations
/// (start/complete/edit a session in demo) operate on the in-memory list so the
/// live logging flow still works, but seed data is never persisted.
class DemoWorkoutRepository
    implements WorkoutRepository, ReadOnlyWorkoutRepository {
  DemoWorkoutRepository({required DateTime anchor})
    : _sessions = DemoWorkoutSeed(anchor: anchor).buildSessions();

  final List<WorkoutSession> _sessions;

  List<WorkoutSession> _sorted() {
    final copy = List<WorkoutSession>.from(_sessions);
    copy.sort((a, b) => b.startTime.compareTo(a.startTime));
    return copy;
  }

  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession session) async {
    _sessions.add(session);
    return session;
  }

  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async {
    for (final session in _sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  @override
  Future<WorkoutSession?> getLatestActiveSession() async {
    for (final session in _sorted()) {
      if (!session.isCompleted) return session;
    }
    return null;
  }

  @override
  Future<ReadOnlyWorkoutSnapshot> getWorkoutSnapshotReadOnly({
    int? limit,
  }) async {
    final sessions = await getWorkoutSessions(limit: limit);
    final active = await getLatestActiveSession();
    return ReadOnlyWorkoutSnapshot(
      activeSession: active,
      sessions: List.unmodifiable(sessions),
    );
  }

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    var result = _sorted();
    if (startDate != null) {
      result = result
          .where((s) => !s.startTime.isBefore(startDate))
          .toList(growable: false);
    }
    if (endDate != null) {
      result = result
          .where((s) => !s.startTime.isAfter(endDate))
          .toList(growable: false);
    }
    if (limit != null && result.length > limit) {
      result = result.sublist(0, limit);
    }
    return result;
  }

  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession session, {
    bool markDirty = true,
  }) async {
    final index = _sessions.indexWhere((s) => s.id == session.id);
    if (index >= 0) {
      _sessions[index] = session;
    } else {
      _sessions.add(session);
    }
    return session;
  }

  @override
  Future<void> deleteWorkoutSession(String id) async {
    _sessions.removeWhere((s) => s.id == id);
  }

  @override
  Future<WorkoutSession> completeWorkoutSession(String sessionId) async {
    final index = _sessions.indexWhere((s) => s.id == sessionId);
    if (index < 0) {
      throw StateError('Demo session $sessionId not found');
    }
    final completed = _sessions[index].copyWith(
      isCompleted: true,
      endTime: _sessions[index].endTime ?? DateTime.now(),
    );
    _sessions[index] = completed;
    return completed;
  }

  @override
  Future<WorkoutSession> addExerciseToSession(
    String sessionId,
    WorkoutExercise exercise,
  ) async {
    final session = await _requireSession(sessionId);
    final updated = session.copyWith(
      exercises: [...session.exercises, exercise],
    );
    return updateWorkoutSession(updated);
  }

  @override
  Future<WorkoutSession> updateExerciseInSession(
    String sessionId,
    String exerciseId,
    WorkoutExercise exercise,
  ) async {
    final session = await _requireSession(sessionId);
    final exercises = session.exercises
        .map((e) => e.id == exerciseId ? exercise : e)
        .toList();
    return updateWorkoutSession(session.copyWith(exercises: exercises));
  }

  @override
  Future<WorkoutSession> removeExerciseFromSession(
    String sessionId,
    String exerciseId,
  ) async {
    final session = await _requireSession(sessionId);
    final exercises = session.exercises
        .where((e) => e.id != exerciseId)
        .toList();
    return updateWorkoutSession(session.copyWith(exercises: exercises));
  }

  @override
  Future<WorkoutExercise> addSetToExercise(
    String sessionId,
    String exerciseId,
    WorkoutSet set,
  ) async {
    final session = await _requireSession(sessionId);
    final exercise = session.exercises.firstWhere((e) => e.id == exerciseId);
    final updatedExercise = exercise.copyWith(sets: [...exercise.sets, set]);
    await updateExerciseInSession(sessionId, exerciseId, updatedExercise);
    return updatedExercise;
  }

  @override
  Future<WorkoutExercise> updateSetInExercise(
    String sessionId,
    String exerciseId,
    int setIndex,
    WorkoutSet set,
  ) async {
    final session = await _requireSession(sessionId);
    final exercise = session.exercises.firstWhere((e) => e.id == exerciseId);
    final sets = List<WorkoutSet>.from(exercise.sets);
    if (setIndex >= 0 && setIndex < sets.length) {
      sets[setIndex] = set;
    } else {
      sets.add(set);
    }
    final updatedExercise = exercise.copyWith(sets: sets);
    await updateExerciseInSession(sessionId, exerciseId, updatedExercise);
    return updatedExercise;
  }

  @override
  Future<List<WorkoutSet>?> getPreviousExerciseSets(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    for (final session in _sorted()) {
      if (!session.isCompleted) continue;
      for (final exercise in session.exercises) {
        if (_matches(exercise, exerciseName, exerciseSlug)) {
          return exercise.sets;
        }
      }
    }
    return null;
  }

  @override
  Future<DateTime?> getLastPerformedDate(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    for (final session in _sorted()) {
      if (!session.isCompleted) continue;
      for (final exercise in session.exercises) {
        if (_matches(exercise, exerciseName, exerciseSlug)) {
          return session.endTime ?? session.startTime;
        }
      }
    }
    return null;
  }

  @override
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  }) async {
    final pr = await getExercisePr(exerciseName, exerciseSlug: exerciseSlug);
    if (pr == null) return set.reps > 0 && set.weight > 0;
    if (set.weight > pr.weight) return true;
    return set.weight == pr.weight && set.reps > pr.reps;
  }

  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    double bestWeight = 0;
    int bestReps = 0;
    var found = false;
    for (final session in _sessions) {
      if (!session.isCompleted) continue;
      for (final exercise in session.exercises) {
        if (!_matches(exercise, exerciseName, exerciseSlug)) continue;
        for (final set in exercise.sets) {
          if (!set.isCompleted || set.weight <= 0) continue;
          if (set.weight > bestWeight ||
              (set.weight == bestWeight && set.reps > bestReps)) {
            bestWeight = set.weight;
            bestReps = set.reps;
            found = true;
          }
        }
      }
    }
    if (!found) return null;
    return ExercisePr(weight: bestWeight, reps: bestReps);
  }

  @override
  Future<void> recomputeAllPrFlags() async {
    // Demo seed already carries correct PR flags; nothing to recompute.
  }

  Future<WorkoutSession> _requireSession(String id) async {
    final session = await getWorkoutSession(id);
    if (session == null) {
      throw StateError('Demo session $id not found');
    }
    return session;
  }

  bool _matches(
    WorkoutExercise exercise,
    String exerciseName,
    String? exerciseSlug,
  ) {
    if (exerciseSlug != null && exerciseSlug.isNotEmpty) {
      if (exercise.exercise.slug == exerciseSlug) return true;
    }
    return exercise.exercise.name.toLowerCase() == exerciseName.toLowerCase();
  }
}
