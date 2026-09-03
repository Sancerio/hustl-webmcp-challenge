import '../models/workout_session.dart';
import '../models/workout_exercise.dart';
import '../models/workout_set.dart';

/// Lightweight value describing an exercise PR (best single set).
class ExercisePr {
  final double weight;
  final int reps;
  const ExercisePr({required this.weight, required this.reps});

  bool get isValid => weight.isFinite && reps >= 0;
}

class ReadOnlyWorkoutSnapshot {
  const ReadOnlyWorkoutSnapshot({
    required this.activeSession,
    required this.sessions,
  });

  final WorkoutSession? activeSession;
  final List<WorkoutSession> sessions;
}

/// Strictly non-persisting workout view for read-only integrations.
abstract interface class ReadOnlyWorkoutRepository {
  Future<ReadOnlyWorkoutSnapshot> getWorkoutSnapshotReadOnly({int? limit});
}

/// Repository interface for workout sessions management
abstract class WorkoutRepository {
  /// Create a new workout session
  Future<WorkoutSession> createWorkoutSession(WorkoutSession session);

  /// Get a workout session by ID
  Future<WorkoutSession?> getWorkoutSession(String id);

  /// Get the most recent active (non-completed) workout session if any
  Future<WorkoutSession?> getLatestActiveSession();

  /// Get all workout sessions (potentially with pagination/filtering)
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Update an existing workout session.
  ///
  /// [markDirty] controls whether the updated session should be flagged for
  /// sync with the backend. Callers that are hydrating data from the server
  /// should pass `false` to avoid re-uploading the imported session.
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession session, {
    bool markDirty = true,
  });

  /// Delete a workout session
  Future<void> deleteWorkoutSession(String id);

  /// Add an exercise to a workout session
  Future<WorkoutSession> addExerciseToSession(
    String sessionId,
    WorkoutExercise exercise,
  );

  /// Update an exercise in a workout session
  Future<WorkoutSession> updateExerciseInSession(
    String sessionId,
    String exerciseId,
    WorkoutExercise exercise,
  );

  /// Remove an exercise from a workout session
  Future<WorkoutSession> removeExerciseFromSession(
    String sessionId,
    String exerciseId,
  );

  /// Add a set to an exercise in a workout session
  Future<WorkoutExercise> addSetToExercise(
    String sessionId,
    String exerciseId,
    WorkoutSet set,
  );

  /// Update a set in an exercise in a workout session
  Future<WorkoutExercise> updateSetInExercise(
    String sessionId,
    String exerciseId,
    int setIndex,
    WorkoutSet set,
  );

  /// Complete a workout session
  Future<WorkoutSession> completeWorkoutSession(String sessionId);

  /// Get the previous workout containing a specific exercise
  Future<List<WorkoutSet>?> getPreviousExerciseSets(
    String exerciseName, {
    String? exerciseSlug,
  });

  /// Get the most recent session date that includes the specified exercise.
  Future<DateTime?> getLastPerformedDate(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    return null;
  }

  /// Check if a set is a personal record
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  });

  /// Get the current best PR (weight, reps) for an exercise.
  /// Returns null if there is no valid record yet.
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  });

  /// Recompute and persist PR flags across all stored sessions.
  ///
  /// Policy: A set is a PR if its weight is greater than any previous
  /// set for the same exercise, or if weight is equal and reps are higher.
  Future<void> recomputeAllPrFlags();
}
