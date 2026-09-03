import '../../domain/models/exercise.dart';
import '../../domain/repositories/exercise_repository.dart';
import '../datasources/exercise_seed_datasource.dart';

/// Credential-free exercise repository for the public evaluator build.
///
/// The bundled seed is the only catalog source. Custom exercises live only in
/// this repository instance, so evaluator actions cannot read or mutate device
/// storage, account state, or the Hustl backend.
class EvaluatorExerciseRepository implements ExerciseRepository {
  EvaluatorExerciseRepository({required ExerciseSeedDataSource seed})
    : _seed = seed;

  final ExerciseSeedDataSource _seed;
  final List<Exercise> _customExercises = <Exercise>[];
  Future<List<Exercise>>? _catalogLoad;

  Future<List<Exercise>> _loadCatalog() {
    return _catalogLoad ??= _seed.loadSeed().then(_filterInvalid);
  }

  List<Exercise> _filterInvalid(List<Exercise> exercises) {
    return exercises
        .where(
          (exercise) =>
              exercise.name.trim().isNotEmpty &&
              exercise.muscles.any((muscle) => muscle.trim().isNotEmpty),
        )
        .toList(growable: false);
  }

  String _normalizedName(Exercise exercise) =>
      exercise.name.trim().toLowerCase();

  @override
  Future<List<Exercise>> getAllExercises() async {
    final catalog = await _loadCatalog();
    final customNames = _customExercises.map(_normalizedName).toSet();
    return <Exercise>[
      ..._customExercises,
      ...catalog.where(
        (exercise) => !customNames.contains(_normalizedName(exercise)),
      ),
    ];
  }

  @override
  Future<List<Exercise>> getExercisesByMuscle(String muscle) async {
    final normalizedMuscle = muscle.trim().toLowerCase();
    final exercises = await getAllExercises();
    return exercises
        .where(
          (exercise) => exercise.muscles.any(
            (candidate) => candidate.toLowerCase().contains(normalizedMuscle),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<Exercise>> searchExercises(String query) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return getAllExercises();

    final exercises = await getAllExercises();
    return exercises
        .where(
          (exercise) =>
              exercise.name.toLowerCase().contains(normalizedQuery) ||
              exercise.muscles.any(
                (muscle) => muscle.toLowerCase().contains(normalizedQuery),
              ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<Exercise>> getCustomExercises() async {
    return List<Exercise>.unmodifiable(_customExercises);
  }

  @override
  Future<List<Exercise>> getSharedExercises({String? search}) async {
    return const <Exercise>[];
  }

  @override
  Future<Exercise> addCustomExercise(Exercise exercise) async {
    final id = exercise.id;
    final existingIndex = id == null || id.isEmpty
        ? -1
        : _customExercises.indexWhere((candidate) => candidate.id == id);
    if (existingIndex >= 0) {
      _customExercises[existingIndex] = exercise;
    } else {
      _customExercises.add(exercise);
    }
    return exercise;
  }

  @override
  Future<void> removeCustomExercise(Exercise exercise) async {
    final id = exercise.id;
    if (id != null && id.isNotEmpty) {
      _customExercises.removeWhere((candidate) => candidate.id == id);
      return;
    }

    final normalizedName = _normalizedName(exercise);
    _customExercises.removeWhere(
      (candidate) => _normalizedName(candidate) == normalizedName,
    );
  }

  @override
  Future<String?> regenerateThumbnail(Exercise exercise) {
    return Future<String?>.error(_unsupportedMutation());
  }

  @override
  Future<String?> regenerateThumbnailDebug(
    Exercise exercise, {
    String? steerImageUrl,
    String? steerImageDataUrl,
  }) {
    return Future<String?>.error(_unsupportedMutation());
  }

  @override
  Future<Exercise> generateOverviewDebug(Exercise exercise) {
    return Future<Exercise>.error(_unsupportedMutation());
  }

  @override
  Future<Exercise> generateHowToDebug(Exercise exercise) {
    return Future<Exercise>.error(_unsupportedMutation());
  }

  UnsupportedError _unsupportedMutation() => UnsupportedError(
    'Remote exercise generation is unavailable in evaluator mode.',
  );
}
