import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/widgets/app_chip.dart';
import 'package:hustl_app/core/widgets/staggered_entrance.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/exercise_library/presentation/screens/exercise_detail_screen.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';

class _FakeWorkoutRepo implements WorkoutRepository {
  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => const <WorkoutSession>[];

  @override
  Future<DateTime?> getLastPerformedDate(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;

  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    StaggeredEntrance.resetForTest();
    GetIt.I.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    GetIt.I.registerSingleton<PreferencesService>(prefs);
    GetIt.I.registerSingleton<WorkoutRepository>(_FakeWorkoutRepo());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('Details tab shows the exercise name exactly once', (
    tester,
  ) async {
    const ex = Exercise(name: 'Barbell Squat', muscles: ['quads', 'glutes']);

    await tester.pumpWidget(
      const MaterialApp(home: ExerciseDetailScreen(exercise: ex)),
    );
    await tester.pumpAndSettle();

    // Only the app-bar title carries the name; no duplicate hero heading.
    expect(find.text('Barbell Squat'), findsOneWidget);
  });

  testWidgets(
    'Hero defaults to the muscle figure (no grey dumbbell void) without media',
    (tester) async {
      const ex = Exercise(name: 'Barbell Squat', muscles: ['quads', 'glutes']);

      await tester.pumpWidget(
        const MaterialApp(home: ExerciseDetailScreen(exercise: ex)),
      );
      await tester.pumpAndSettle();

      // The hero media slot now routes through the muscle figure rather than
      // the old 96px fitness_center fallback void; that fallback icon is gone.
      expect(find.byIcon(Icons.fitness_center), findsNothing);
    },
  );

  testWidgets('Equipment and difficulty render as AppChips', (tester) async {
    const ex = Exercise(
      name: 'Barbell Squat',
      muscles: ['quads'],
      equipment: ['Barbell', 'Rack'],
      difficulty: 'Advanced',
    );

    await tester.pumpWidget(
      const MaterialApp(home: ExerciseDetailScreen(exercise: ex)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppChip), findsWidgets);
    // Difficulty status chip + equipment data chip both surface their text.
    expect(find.text('Advanced'), findsOneWidget);
    expect(find.text('Equipment'), findsOneWidget);
    expect(find.text('Barbell, Rack'), findsOneWidget);
  });

  testWidgets('Muscles worked section renders a chip per muscle', (
    tester,
  ) async {
    const ex = Exercise(name: 'Barbell Squat', muscles: ['quads', 'glutes']);

    await tester.pumpWidget(
      const MaterialApp(home: ExerciseDetailScreen(exercise: ex)),
    );
    await tester.pumpAndSettle();

    // Section heading present and mapped muscle labels surface exactly once.
    expect(find.text('Muscles worked'), findsOneWidget);
    expect(find.text('Quads'), findsOneWidget);
    expect(find.text('Glutes'), findsOneWidget);
  });
}
