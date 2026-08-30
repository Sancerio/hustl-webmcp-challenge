import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/token_storage.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/exercise_library/domain/repositories/exercise_repository.dart';
import 'package:hustl_app/features/exercise_library/presentation/screens/exercise_detail_screen.dart';
import 'package:hustl_app/features/exercise_library/presentation/widgets/exercise_card.dart';
import 'package:hustl_app/features/exercise_library/presentation/widgets/custom_exercise_form.dart';
import 'package:hustl_app/features/exercise_library/presentation/widgets/exercise_list_screen_base.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';

class _ExerciseRepoFake implements ExerciseRepository {
  Exercise? lastAdded;
  Exercise? lastRemoved;
  final List<Exercise> custom;
  final List<Exercise> allExercises;
  _ExerciseRepoFake(this.custom, {List<Exercise>? allExercises})
    : allExercises = allExercises ?? custom;

  @override
  Future<Exercise> addCustomExercise(Exercise exercise) async {
    lastAdded = exercise;
    // Replace in custom list by id if possible
    final idx = custom.indexWhere((e) => e.id == exercise.id);
    if (idx >= 0) {
      custom[idx] = exercise;
    } else {
      custom.add(exercise);
    }
    return exercise;
  }

  @override
  Future<void> removeCustomExercise(Exercise exercise) async {
    lastRemoved = exercise;
    custom.removeWhere(
      (e) =>
          (e.id != null && e.id == exercise.id) ||
          e.name.toLowerCase() == exercise.name.toLowerCase(),
    );
  }

  @override
  Future<List<Exercise>> getCustomExercises() async => List.of(custom);
  @override
  Future<List<Exercise>> getSharedExercises({String? search}) async => const [];

  // Unused in these tests
  @override
  Future<List<Exercise>> getAllExercises() async => List.of(allExercises);
  @override
  Future<List<Exercise>> getExercisesByMuscle(String muscle) async =>
      allExercises
          .where((exercise) => exercise.muscles.contains(muscle))
          .toList();
  @override
  Future<List<Exercise>> searchExercises(String query) async => allExercises
      .where(
        (exercise) => exercise.name.toLowerCase().contains(query.toLowerCase()),
      )
      .toList();
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

class _WorkoutRepoFake implements WorkoutRepository {
  @override
  Future<DateTime?> getLastPerformedDate(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => const <WorkoutSession>[];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;
}

class _TokenStorageFake extends TokenStorage {
  _TokenStorageFake(this.token);
  final String? token;

  @override
  Future<String?> getAccessToken() async => token;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Fresh DI and SharedPreferences for each test
    GetIt.I.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    GetIt.I.registerSingleton<PreferencesService>(prefs);
    GetIt.I.registerSingleton<WorkoutRepository>(_WorkoutRepoFake());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('Edit custom exercise updates name and saves via repo', (
    tester,
  ) async {
    const original = Exercise(
      id: 'custom-123',
      name: 'My Move',
      muscles: ['Custom'],
      visibility: ExerciseVisibility.private,
    );
    final repo = _ExerciseRepoFake([original]);
    GetIt.I.registerSingleton<ExerciseRepository>(repo);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const ExerciseDetailScreen(
            exercise: original,
            initialTabIndex: 0,
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // Edit button should be visible for custom item
    expect(find.byIcon(Icons.edit), findsOneWidget);

    // Open editor
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    // Change the name
    final nameField = find.widgetWithText(TextFormField, 'Name');
    expect(nameField, findsOneWidget);
    await tester.enterText(nameField, 'Renamed Move');

    // Save
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    // App bar should reflect the new name
    expect(find.text('Renamed Move'), findsWidgets);
    // Repo should have been called with the updated exercise keeping same id
    expect(repo.lastAdded, isNotNull);
    expect(repo.lastAdded!.name, 'Renamed Move');
    expect(repo.lastAdded!.id, original.id);
  });

  testWidgets('Shared exercise can be copied into My Exercises', (
    tester,
  ) async {
    const shared = Exercise(
      id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      name: 'Shared Move',
      muscles: ['Custom'],
      visibility: ExerciseVisibility.public,
    );
    final repo = _ExerciseRepoFake([]);
    GetIt.I.registerSingleton<ExerciseRepository>(repo);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const ExerciseDetailScreen(exercise: shared, initialTabIndex: 0),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // Shared item should not show edit/delete controls.
    expect(find.byIcon(Icons.edit), findsNothing);
    expect(find.byIcon(Icons.delete), findsNothing);

    // Offer copy-on-add into My Exercises.
    expect(find.text('Add to My Exercises'), findsOneWidget);

    await tester.tap(find.text('Add to My Exercises'));
    await tester.pumpAndSettle();

    // Now we're viewing the user's private copy.
    expect(repo.lastAdded, isNotNull);
    expect(repo.lastAdded!.visibility, ExerciseVisibility.private);
    expect(repo.lastAdded!.name, shared.name);
    expect(repo.lastAdded!.id, isNotEmpty);
    expect(repo.lastAdded!.id, isNot(shared.id));
    expect(find.byIcon(Icons.edit), findsOneWidget);
    expect(find.byIcon(Icons.delete), findsOneWidget);
  });

  testWidgets('Delete custom exercise confirms, calls repo, and pops', (
    tester,
  ) async {
    const original = Exercise(
      id: 'custom-xyz',
      name: 'To Delete',
      muscles: ['Custom'],
      visibility: ExerciseVisibility.private,
    );
    final repo = _ExerciseRepoFake([original]);
    GetIt.I.registerSingleton<ExerciseRepository>(repo);

    // The detail screen is pushed under GoRouter in the real app, and its
    // delete dialog dismisses via context.pop (go_router), so drive it through
    // a GoRouter harness with an opener route to pop back to.
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/detail'),
                child: const Text('Open Detail'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/detail',
          builder: (context, state) => const ExerciseDetailScreen(
            exercise: original,
            initialTabIndex: 0,
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // Navigate to detail
    await tester.tap(find.text('Open Detail'));
    await tester.pumpAndSettle();

    // Delete icon visible
    expect(find.byIcon(Icons.delete), findsOneWidget);

    // Tap delete and confirm
    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    expect(find.text('Delete Custom Exercise?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // We should be back on the opener screen
    expect(find.text('Open Detail'), findsOneWidget);
    // Repo called
    expect(repo.lastRemoved, isNotNull);
    expect(repo.custom.any((e) => e.id == original.id), isFalse);
  });

  testWidgets('Delete legacy custom (no id) removes stored entry', (
    tester,
  ) async {
    const legacy = Exercise(
      id: null,
      name: 'Legacy Custom',
      muscles: ['Custom'],
    );
    final repo = _ExerciseRepoFake([legacy]);
    GetIt.I.registerSingleton<ExerciseRepository>(repo);

    // Pushed under GoRouter (matching the app) so the delete dialog's
    // context.pop dismissal and the screen pop-back resolve.
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/detail'),
                child: const Text('Open Detail'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/detail',
          builder: (context, state) => const ExerciseDetailScreen(
            exercise: legacy,
            initialTabIndex: 0,
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Detail'));
    await tester.pumpAndSettle();

    // Delete icon must be visible due to name-based custom detection
    expect(find.byIcon(Icons.delete), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Back to opener and item removed from fake storage
    expect(find.text('Open Detail'), findsOneWidget);
    expect(repo.custom.any((e) => e.name == legacy.name), isFalse);
  });

  testWidgets(
    'Edit legacy custom (no id) replaces by name and assigns new id',
    (tester) async {
      const legacy = Exercise(
        id: null,
        name: 'Legacy Move',
        muscles: ['Custom'],
      );
      final repo = _ExerciseRepoFake([legacy]);
      GetIt.I.registerSingleton<ExerciseRepository>(repo);

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const ExerciseDetailScreen(
              exercise: legacy,
              initialTabIndex: 0,
            ),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      // Tap edit
      expect(find.byIcon(Icons.edit), findsOneWidget);
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();

      // Rename and save
      final nameField = find.widgetWithText(TextFormField, 'Name');
      await tester.enterText(nameField, 'Legacy Renamed');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      // UI updated
      expect(find.text('Legacy Renamed'), findsWidgets);
      // Storage contains a single updated entry with a generated id
      expect(repo.custom.length, 1);
      expect(repo.custom.first.name, 'Legacy Renamed');
      expect(repo.custom.first.id, isNotNull);
    },
  );

  testWidgets('exercise card shows refresh button when enabled', (
    tester,
  ) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 260,
              child: ExerciseCard(
                exerciseName: 'Squat',
                muscleGroup: 'Legs',
                showRefresh: true,
                onRefresh: () {
                  pressed = true;
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.refresh), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(pressed, isTrue);
  });

  testWidgets('exercise card hides refresh button when disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 260,
              child: ExerciseCard(exerciseName: 'Squat', muscleGroup: 'Legs'),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.refresh), findsNothing);
  });

  testWidgets('favorites filter shows only favorited exercises and toggles', (
    tester,
  ) async {
    const exercises = [
      Exercise(name: 'Bench Press', muscles: ['Chest']),
      Exercise(name: 'Deadlift', muscles: ['Back']),
      Exercise(name: 'Squat', muscles: ['Legs']),
    ];
    final repo = _ExerciseRepoFake(const [], allExercises: exercises);
    GetIt.I.registerSingleton<ExerciseRepository>(repo);

    final prefs = GetIt.I<PreferencesService>();
    await prefs.toggleFavoriteExercise('Bench Press');
    await prefs.toggleFavoriteExercise('Squat');

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
    await tester.pumpAndSettle();

    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Deadlift'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);

    // The favorites toggle is now a direct star icon button in the search header.
    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();

    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('Deadlift'), findsNothing);

    // Tap the filled star to turn off favorites-only mode.
    await tester.tap(find.byIcon(Icons.star));
    await tester.pumpAndSettle();

    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Deadlift'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);
  });

  testWidgets('custom exercise form saves a minimal valid custom exercise', (
    tester,
  ) async {
    final repo = _ExerciseRepoFake([]);
    GetIt.I.registerSingleton<ExerciseRepository>(repo);

    Exercise? result;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showCustomExerciseForm(context);
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
    await tester.pumpAndSettle();

    expect(repo.lastAdded, isNotNull);
    expect(result, isNotNull);
    expect(result!.name, 'My Move');
    expect(result!.muscles, ['Custom']);
    expect(result!.loggingMode, ExerciseLoggingMode.weightReps);
    expect(result!.id, isNotNull);
    expect(
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(result!.id!),
      isTrue,
    );
    expect(result!.visibility, ExerciseVisibility.private);
  });

  testWidgets('custom exercise form allows selecting Public when signed in', (
    tester,
  ) async {
    GetIt.I.registerSingleton<ExerciseRepository>(_ExerciseRepoFake([]));
    GetIt.I.registerSingleton<TokenStorage>(_TokenStorageFake('token'));

    Exercise? result;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showCustomExerciseForm(context);
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
      'My Public Move',
    );
    await tester.pump();
    await tester.tap(find.text('Public'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.visibility, ExerciseVisibility.public);
  });

  testWidgets('custom exercise form allows selecting logging mode', (
    tester,
  ) async {
    GetIt.I.registerSingleton<ExerciseRepository>(_ExerciseRepoFake([]));

    Exercise? result;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showCustomExerciseForm(context);
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
      'My Timed Move',
    );
    await tester.pump();

    final dropdown = find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField<ExerciseLoggingMode>,
    );
    expect(dropdown, findsOneWidget);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duration Only').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.loggingMode, ExerciseLoggingMode.durationOnly);
  });
}
