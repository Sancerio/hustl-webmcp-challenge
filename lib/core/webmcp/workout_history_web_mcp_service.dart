abstract interface class WorkoutHistoryWebMcpReader {
  Future<Map<String, Object?>> loadWorkoutHistory({
    required int limit,
    String? cursor,
  });

  Future<Map<String, Object?>> loadExerciseHistory({
    required int limit,
    required int sinceDays,
  });
}

/// Compatibility type retained for the upstream evaluator test doubles. The
/// public runtime registers only DemoWorkoutHistoryWebMcpService.
abstract class WorkoutHistoryWebMcpService
    implements WorkoutHistoryWebMcpReader {}
