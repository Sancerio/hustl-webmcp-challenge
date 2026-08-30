import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/exercise_library/domain/repositories/exercise_repository.dart';
import 'package:hustl_app/features/exercise_library/presentation/widgets/custom_exercise_form.dart';
import 'package:hustl_app/features/exercise_library/presentation/widgets/exercise_list_screen_base.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';

/// A single fake covering both catalog-load and custom-save failure paths.
///
/// [throwOnLoad] drives [getAllExercises]; flip it to `false` (e.g. from a
/// "Try again" tap) to simulate a recovered network. [throwOnSave] drives
/// [addCustomExercise].
class _ExerciseRepoFake implements ExerciseRepository {
  _ExerciseRepoFake({
    this.throwOnLoad = false,
    this.throwOnSave = false,
    List<Exercise>? loaded,
  }) : loaded = loaded ?? const [];

  bool throwOnLoad;
  bool throwOnSave;
  List<Exercise> loaded;
  Exercise? lastAdded;

  @override
  Future<List<Exercise>> getAllExercises() async {
    if (throwOnLoad) {
      throw Exception('Simulated network failure');
    }
    return List.of(loaded);
  }

  @override
  Future<List<Exercise>> getExercisesByMuscle(String muscle) async => const [];

  @override
  Future<List<Exercise>> searchExercises(String query) async => const [];

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
  Future<Exercise> addCustomExercise(Exercise exercise) async {
    if (throwOnSave) {
      throw Exception('Simulated save failure');
    }
    lastAdded = exercise;
    return exercise;
  }

  @override
  Future<void> removeCustomExercise(Exercise exercise) async {}
}

/// Minimal WorkoutRepository fake: the exercise picker only needs
/// [getWorkoutSessions] (via its own internal try/catch), so every other
/// member forwards to [noSuchMethod] rather than being stubbed out.
class _WorkoutRepoFake implements WorkoutRepository {
  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => const <WorkoutSession>[];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _registerPrefsAndWorkoutRepo() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = PreferencesService();
  await prefs.init();
  GetIt.I.registerSingleton<PreferencesService>(prefs);
  GetIt.I.registerSingleton<WorkoutRepository>(_WorkoutRepoFake());
}

void main() {
  setUp(() async {
    await GetIt.instance.reset(dispose: true);
  });

  testWidgets(
    'Catalog load failure shows an error state, not the "on its way" empty state',
    (tester) async {
      await _registerPrefsAndWorkoutRepo();
      final repo = _ExerciseRepoFake(throwOnLoad: true);
      GetIt.I.registerSingleton<ExerciseRepository>(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseListScreenBase(
              appBarTitle: 'Exercises',
              onExerciseTap: (_, __) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('We couldn\'t load your exercises'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Your exercise library is on its way'), findsNothing);
    },
  );

  testWidgets(
    'Tapping Try again after a load failure recovers and shows the catalog',
    (tester) async {
      await _registerPrefsAndWorkoutRepo();
      const exercises = [
        Exercise(name: 'Bench Press', muscles: ['Chest']),
        Exercise(name: 'Deadlift', muscles: ['Back']),
      ];
      final repo = _ExerciseRepoFake(throwOnLoad: true, loaded: exercises);
      GetIt.I.registerSingleton<ExerciseRepository>(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseListScreenBase(
              appBarTitle: 'Exercises',
              onExerciseTap: (_, __) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('We couldn\'t load your exercises'), findsOneWidget);

      // Let the load-failure snack finish its auto-dismiss timer (staged
      // pumps so the entrance animation, the 2s hold, and the exit
      // animation each get a chance to run) so it can't sit on top of (and
      // swallow the tap on) the "Try again" button below.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));

      repo.throwOnLoad = false;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('We couldn\'t load your exercises'), findsNothing);
      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.text('Deadlift'), findsOneWidget);
    },
  );

  testWidgets(
    'Custom exercise save failure keeps the sheet open and shows an error snack',
    (tester) async {
      final repo = _ExerciseRepoFake(throwOnSave: true);
      GetIt.I.registerSingleton<ExerciseRepository>(repo);

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      await showCustomExerciseForm(context);
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'My Move',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.text('We couldn\'t save this exercise. Please try again.'),
        findsOneWidget,
      );
      // The sheet did NOT pop: the form is still on screen.
      expect(find.widgetWithText(TextFormField, 'Name'), findsOneWidget);
      expect(repo.lastAdded, isNull);
    },
  );
}
