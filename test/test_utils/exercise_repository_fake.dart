import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/exercise_library/domain/repositories/exercise_repository.dart';

/// Minimal in-memory fake suitable for widget tests that need an
/// [ExerciseRepository] registered in GetIt but do not exercise exercise
/// search or retrieval flows.
class ExerciseRepositoryFake implements ExerciseRepository {
  final List<Exercise> _exercises;

  ExerciseRepositoryFake([List<Exercise>? exercises])
    : _exercises = exercises ?? const [];

  @override
  Future<List<Exercise>> getAllExercises() async => List.of(_exercises);

  @override
  Future<List<Exercise>> getExercisesByMuscle(String muscle) async =>
      _exercises.where((e) => e.muscles.contains(muscle)).toList();

  @override
  Future<List<Exercise>> searchExercises(String query) async {
    final lower = query.toLowerCase();
    return _exercises
        .where((e) => e.name.toLowerCase().contains(lower))
        .toList();
  }

  @override
  Future<List<Exercise>> getCustomExercises() async => const [];

  @override
  Future<List<Exercise>> getSharedExercises({String? search}) async => const [];

  @override
  Future<Exercise> addCustomExercise(Exercise exercise) async => exercise;

  @override
  Future<void> removeCustomExercise(Exercise exercise) async {}

  @override
  Future<String?> regenerateThumbnail(Exercise exercise) async => null;

  @override
  Future<String?> regenerateThumbnailDebug(
    Exercise exercise, {
    String? steerImageUrl,
    String? steerImageDataUrl,
  }) async => null;

  @override
  Future<Exercise> generateOverviewDebug(Exercise exercise) async => exercise;

  @override
  Future<Exercise> generateHowToDebug(Exercise exercise) async => exercise;
}
