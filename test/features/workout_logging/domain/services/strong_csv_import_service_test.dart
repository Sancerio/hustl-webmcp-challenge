import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/workout_logging/domain/services/strong_csv_import_service.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/exercise_library/domain/repositories/exercise_repository.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';

class _FakeExerciseRepo implements ExerciseRepository {
  @override
  Future<List<Exercise>> getAllExercises() async => [];

  @override
  Future<List<Exercise>> getExercisesByMuscle(String muscle) async => [];

  @override
  Future<List<Exercise>> searchExercises(String query) async => [];
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
  @override
  Future<List<Exercise>> getCustomExercises() async => const [];
  @override
  Future<List<Exercise>> getSharedExercises({String? search}) async => const [];
  @override
  Future<Exercise> addCustomExercise(Exercise exercise) async => exercise;
  @override
  Future<void> removeCustomExercise(Exercise exercise) async {}
}

void main() {
  test('parses set type markers from Strong CSV', () async {
    const csv =
        'Date,Workout Name,Exercise Name,Set Order,Reps,Weight\n'
        '2023-01-01,Workout,Bench,F,5,100\n'
        '2023-01-01,Workout,Bench,W,5,100\n'
        '2023-01-01,Workout,Bench,SS,5,100\n'
        '2023-01-01,Workout,Bench,xyz,5,100\n';

    final service = StrongCsvImportService(
      exerciseRepository: _FakeExerciseRepo(),
    );
    final result = await service.parse(csv);

    final sets = result.sessions.single.exercises.single.sets;
    expect(sets.length, 4);
    expect(sets[0].setType, SetType.failure);
    expect(sets[1].setType, SetType.warmup);
    expect(sets[2].setType, SetType.superset);
    expect(sets[3].setType, SetType.regular);
  });

  test('parses Strong Android CSV with semicolons and alt headers', () async {
    // Uses semicolon delimiter and headers like Weight (kg), Duration (sec)
    const csv =
        '"Workout #";"Date";"Workout Name";"Duration (sec)";"Exercise Name";"Set Order";"Weight (kg)";"Reps";"RPE";"Notes";"Workout Notes"\n'
        '"1";"2023-09-01 10:34:00";"Morning Workout";"4440";"Bicep Curl (Dumbbell)";"1";"10.0";"15";"";"";""\n'
        '"1";"2023-09-01 10:34:00";"Morning Workout";"4440";"Bicep Curl (Dumbbell)";"2";"8.0";"15";"";"";""\n';

    final service = StrongCsvImportService(
      exerciseRepository: _FakeExerciseRepo(),
    );
    final result = await service.parse(csv);

    expect(result.sessions.length, 1);
    final session = result.sessions.first;
    expect(session.name, 'Morning Workout');
    expect(session.exercises.length, 1);
    final sets = session.exercises.first.sets;
    expect(sets.length, 2);
    expect(sets[0].reps, 15);
    expect(sets[0].weight, 10.0);
    expect(sets[1].weight, 8.0);
  });

  test('resolves exercise kind from repository (cardio)', () async {
    // Repository contains a cardio exercise that should be matched by name
    final repo = _FakeExerciseRepoWithItems([
      const Exercise(
        name: 'Rowing (Machine)',
        muscles: ['Back'],
        kind: ExerciseKind.cardio,
      ),
    ]);

    const csv =
        'Date,Workout Name,Exercise Name,Set Order,Reps,Weight\n'
        '2024-03-10,Cardio Day,Rowing (Machine),1,600,2.5\n';

    final service = StrongCsvImportService(exerciseRepository: repo);
    final result = await service.parse(csv);
    expect(result.sessions.length, 1);
    final wex = result.sessions.first.exercises.first;
    expect(wex.exercise.name, 'Rowing (Machine)');
    expect(wex.exercise.kind, ExerciseKind.cardio);
  });

  test(
    'exports Strong-compatible CSV with fixed header and stable ordering',
    () async {
      final exporter = StrongCsvExportService();

      const strength = Exercise(
        name: 'Bench Press',
        muscles: ['Chest'],
        loggingMode: ExerciseLoggingMode.weightReps,
      );
      const cardio = Exercise(
        name: 'Rowing (Machine)',
        muscles: ['Back'],
        loggingMode: ExerciseLoggingMode.distanceDuration,
      );
      const timed = Exercise(
        name: 'Plank',
        muscles: ['Core'],
        loggingMode: ExerciseLoggingMode.durationOnly,
      );

      final later = WorkoutSession(
        id: 'b',
        name: 'Later Workout',
        startTime: DateTime(2023, 9, 2, 10, 0, 0),
        endTime: DateTime(2023, 9, 2, 11, 14, 30),
        notes: 'workout notes',
        isCompleted: true,
        exercises: [
          const WorkoutExercise(
            id: 'ex1',
            exercise: strength,
            sets: [
              WorkoutSet(
                id: 's1',
                weight: 100.0,
                reps: 5,
                rpe: 8,
                notes: 'set notes',
                isCompleted: true,
              ),
            ],
          ),
        ],
      );

      final earlier = WorkoutSession(
        id: 'a',
        name: 'Earlier Workout',
        startTime: DateTime(2023, 9, 1, 10, 34, 0),
        endTime: DateTime(2023, 9, 1, 11, 19, 0),
        exercises: [
          const WorkoutExercise(
            id: 'ex2',
            exercise: cardio,
            sets: [
              WorkoutSet(id: 's2', weight: 2.5, reps: 600, isCompleted: true),
            ],
          ),
          const WorkoutExercise(
            id: 'ex3',
            exercise: timed,
            sets: [
              WorkoutSet(id: 's3', weight: 0, reps: 90, isCompleted: true),
            ],
          ),
        ],
        isCompleted: true,
      );

      final csvText = exporter.buildCsv([later, earlier]);
      final rows = const CsvToListConverter(eol: '\n')
          .convert(csvText, shouldParseNumbers: false)
          .map((r) => r.map((c) => (c ?? '').toString()).toList())
          .toList();

      expect(rows.first, StrongCsvExportService.header);

      // First data row should be the earlier session due to stable sorting.
      expect(rows[1][0], '2023-09-01 10:34:00');
      expect(rows[1][1], 'Earlier Workout');
      expect(rows[1][2], '45m');

      // Cardio mapping: set.weight -> Distance (km); reps -> duration seconds.
      expect(rows[1][3], 'Rowing (Machine)');
      expect(rows[1][5], ''); // Weight (kg)
      expect(rows[1][6], '600'); // Reps (duration seconds)
      expect(rows[1][7], '2.5'); // Distance
      expect(rows[1][8], 'km'); // Distance Unit

      // Duration-only mapping: reps populated, weight/distance blank.
      expect(rows[2][3], 'Plank');
      expect(rows[2][5], '');
      expect(rows[2][6], '90');
      expect(rows[2][7], '');
      expect(rows[2][8], '');

      // Later session row should include duration in Strong format.
      expect(rows[3][0], '2023-09-02 10:00:00');
      expect(rows[3][2], '1h 14m');
      expect(rows[3][3], 'Bench Press');
      expect(rows[3][4], '1'); // Set Order
      expect(rows[3][5], '100'); // Weight (kg)
      expect(rows[3][6], '5');
      expect(rows[3][9], '8'); // RPE
      expect(rows[3][10], 'set notes');
      expect(rows[3][11], 'workout notes');
    },
  );
}

class _FakeExerciseRepoWithItems implements ExerciseRepository {
  final List<Exercise> _items;
  _FakeExerciseRepoWithItems(this._items);

  @override
  Future<List<Exercise>> getAllExercises() async => _items;

  @override
  Future<List<Exercise>> getExercisesByMuscle(String muscle) async => _items;

  @override
  Future<List<Exercise>> searchExercises(String query) async => _items;

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
  @override
  Future<List<Exercise>> getCustomExercises() async => const [];
  @override
  Future<List<Exercise>> getSharedExercises({String? search}) async => const [];
  @override
  Future<Exercise> addCustomExercise(Exercise exercise) async => exercise;
  @override
  Future<void> removeCustomExercise(Exercise exercise) async {}
}
