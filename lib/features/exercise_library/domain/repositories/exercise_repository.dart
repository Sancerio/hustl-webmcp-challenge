import '../models/exercise.dart';

/// Repository interface for exercise-related operations
abstract class ExerciseRepository {
  /// Get all available exercises
  Future<List<Exercise>> getAllExercises();

  /// Get exercises filtered by muscle group
  Future<List<Exercise>> getExercisesByMuscle(String muscle);

  /// Search exercises by name
  Future<List<Exercise>> searchExercises(String query);

  /// Regenerate exercise thumbnail and return new URL
  Future<String?> regenerateThumbnail(Exercise exercise) async {
    throw UnimplementedError();
  }

  /// Debug-only: regenerate thumbnail with an optional steering image.
  ///
  /// By default this falls back to [regenerateThumbnail] so fakes/tests don't
  /// need to implement it unless they use the debug flow.
  Future<String?> regenerateThumbnailDebug(
    Exercise exercise, {
    String? steerImageUrl,
    String? steerImageDataUrl,
  }) async {
    return regenerateThumbnail(exercise);
  }

  /// Debug-only: generate and persist an updated "Overview" (description).
  Future<Exercise> generateOverviewDebug(Exercise exercise) async {
    throw UnimplementedError();
  }

  /// Debug-only: generate and persist updated "How To" steps and cues.
  Future<Exercise> generateHowToDebug(Exercise exercise) async {
    throw UnimplementedError();
  }

  /// Return locally saved custom exercises
  Future<List<Exercise>> getCustomExercises() async {
    throw UnimplementedError();
  }

  /// Return shared (public) exercises from other users.
  ///
  /// This endpoint requires authentication.
  Future<List<Exercise>> getSharedExercises({String? search}) async {
    throw UnimplementedError();
  }

  /// Add a locally saved custom exercise and return the saved instance
  Future<Exercise> addCustomExercise(Exercise exercise) async {
    throw UnimplementedError();
  }

  /// Remove a locally saved custom exercise. Implementations should prefer
  /// removing by id when available, and fall back to name match if needed.
  Future<void> removeCustomExercise(Exercise exercise) async {
    throw UnimplementedError();
  }
}

/// Debug-only exercise operations. These should only be invoked when debug mode
/// is enabled in user preferences.
abstract class ExerciseRepositoryDebug {
  /// Regenerate exercise thumbnail and return new URL.
  ///
  /// Use [steerImageUrl] for a remote reference image, or [steerImageDataUrl]
  /// for an uploaded file encoded as a `data:<mime>;base64,...` URL.
  Future<String?> regenerateThumbnailDebug(
    Exercise exercise, {
    String? steerImageUrl,
    String? steerImageDataUrl,
  }) async {
    throw UnimplementedError();
  }

  /// Generate and persist an "Overview" for this exercise.
  Future<Exercise> generateOverviewDebug(Exercise exercise) async {
    throw UnimplementedError();
  }

  /// Generate and persist "How To" steps + coaching cues for this exercise.
  Future<Exercise> generateHowToDebug(Exercise exercise) async {
    throw UnimplementedError();
  }
}
