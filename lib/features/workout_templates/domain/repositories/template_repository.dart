import '../models/workout_template.dart';

abstract class TemplateRepository {
  /// Get all workout templates
  Future<List<WorkoutTemplate>> getWorkoutTemplates();

  /// Get a single workout template by ID
  Future<WorkoutTemplate?> getWorkoutTemplate(String id);

  /// Create a new workout template
  Future<WorkoutTemplate> createWorkoutTemplate(WorkoutTemplate template);

  /// Update an existing workout template
  Future<WorkoutTemplate> updateWorkoutTemplate(WorkoutTemplate template);

  /// Delete a workout template
  Future<void> deleteWorkoutTemplate(String id);
}
