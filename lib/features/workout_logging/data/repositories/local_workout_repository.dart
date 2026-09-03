import '../../domain/models/exercise_timeline_event.dart';
import '../../domain/models/workout_exercise.dart';
import '../../domain/models/workout_set.dart';
import '../../domain/repositories/workout_repository.dart';

/// Compile-only compatibility seam. The public evaluator never registers this
/// persistent implementation; every workout uses DemoWorkoutRepository.
abstract class LocalWorkoutRepository implements WorkoutRepository {
  Future<WorkoutExercise> updateSetsInExercise(
    String sessionId,
    String exerciseId,
    Map<int, WorkoutSet> updatesByIndex, {
    List<ExerciseTimelineEvent> appendTimelineEvents = const [],
    bool markDirty = true,
  });
}

extension PublicGranularWorkoutCompatibility on WorkoutRepository {
  Future<WorkoutExercise> updateSetsInExercise(
    String sessionId,
    String exerciseId,
    Map<int, WorkoutSet> updatesByIndex, {
    List<ExerciseTimelineEvent> appendTimelineEvents = const [],
    bool markDirty = true,
  }) => throw UnsupportedError('Persistent granular writes are not available.');
}
