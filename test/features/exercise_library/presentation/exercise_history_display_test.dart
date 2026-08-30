import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/exercise_library/presentation/screens/exercise_detail_screen.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/widgets/app_progress_ring.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeWorkoutRepo implements WorkoutRepository {
  List<WorkoutSession> sessions;
  _FakeWorkoutRepo(this.sessions);

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => sessions;

  // Unused in these tests
  @override
  Future<WorkoutSession> addExerciseToSession(
    String sessionId,
    WorkoutExercise exercise,
  ) => throw UnimplementedError();
  @override
  Future<WorkoutExercise> addSetToExercise(
    String sessionId,
    String exerciseId,
    WorkoutSet set,
  ) => throw UnimplementedError();
  @override
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  }) => throw UnimplementedError();
  @override
  Future<WorkoutSession> completeWorkoutSession(String sessionId) =>
      throw UnimplementedError();
  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession session) =>
      throw UnimplementedError();
  @override
  Future<void> deleteWorkoutSession(String id) => throw UnimplementedError();
  @override
  Future<WorkoutSession?> getLatestActiveSession() =>
      throw UnimplementedError();
  @override
  Future<List<WorkoutSet>?> getPreviousExerciseSets(
    String exerciseName, {
    String? exerciseSlug,
  }) => throw UnimplementedError();
  @override
  Future<WorkoutSession?> getWorkoutSession(String id) =>
      throw UnimplementedError();
  @override
  Future<void> recomputeAllPrFlags() => throw UnimplementedError();
  @override
  Future<WorkoutSession> updateExerciseInSession(
    String sessionId,
    String exerciseId,
    WorkoutExercise exercise,
  ) => throw UnimplementedError();
  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession session, {
    bool markDirty = true,
  }) => throw UnimplementedError();
  @override
  Future<WorkoutExercise> updateSetInExercise(
    String sessionId,
    String exerciseId,
    int setIndex,
    WorkoutSet set,
  ) => throw UnimplementedError();
  @override
  Future<WorkoutSession> removeExerciseFromSession(
    String sessionId,
    String exerciseId,
  ) => throw UnimplementedError();

  @override
  Future<DateTime?> getLastPerformedDate(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    return null;
  }

  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;
}

void main() {
  setUp(() {
    GetIt.I.reset();
  });

  Future<void> registerPrefs() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    GetIt.I.registerSingleton<PreferencesService>(prefs);
  }

  testWidgets(
    'Exercise history shows completed sets as chips and time format',
    (tester) async {
      // Arrange a session with completed and incomplete sets
      const ex = Exercise(name: 'Bench Press', muscles: ['Chest']);
      const wex = WorkoutExercise(
        id: 'e1',
        exercise: ex,
        sets: [
          WorkoutSet(id: 's1', weight: 100, reps: 5, isCompleted: true),
          WorkoutSet(id: 's2', weight: 105, reps: 3, isCompleted: true),
          WorkoutSet(id: 's3', weight: 110, reps: 2, isCompleted: false),
        ],
      );
      final startUtc = DateTime.utc(2024, 8, 18, 18, 45); // 6:45 PM UTC
      final session = WorkoutSession(
        id: 'sess1',
        name: 'Push Day',
        startTime: startUtc,
        endTime: startUtc.add(const Duration(hours: 1)),
        exercises: [wex],
        isCompleted: true,
      );
      GetIt.I.registerSingleton<WorkoutRepository>(_FakeWorkoutRepo([session]));
      await registerPrefs();

      // Pump the details screen and navigate to History tab
      await tester.pumpWidget(
        const MaterialApp(home: ExerciseDetailScreen(exercise: ex)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      // Assert only completed sets appear as chips (Wave I uses the × glyph)
      expect(find.text('100 kg × 5'), findsOneWidget);
      expect(find.text('105 kg × 3'), findsOneWidget);
      expect(find.text('110 kg × 2'), findsNothing); // incomplete hidden

      // Assert time format includes h:mm a
      // Look for a title containing a bullet with time in AM/PM format
      final timeMatcher = find.byWidgetPredicate((w) {
        if (w is Text) {
          final s = w.data ?? '';
          return s.contains('•') &&
              RegExp(r'\b\d{1,2}:\d{2} (AM|PM)\b').hasMatch(s);
        }
        return false;
      });
      expect(timeMatcher, findsWidgets);
    },
  );

  testWidgets('Exercise history excludes sessions without completed sets', (
    tester,
  ) async {
    const ex = Exercise(name: 'Leg Extension (Machine)', muscles: ['Quads']);
    const skippedExercise = WorkoutExercise(
      id: 'ex-skipped',
      exercise: ex,
      sets: [
        WorkoutSet(id: 'set-skipped', weight: 0, reps: 0, isCompleted: false),
      ],
    );
    const completedExercise = WorkoutExercise(
      id: 'ex-complete',
      exercise: ex,
      sets: [
        WorkoutSet(id: 'set-finished', weight: 75, reps: 10, isCompleted: true),
      ],
    );

    final sessions = [
      WorkoutSession(
        id: 'aborted',
        name: 'Aborted Leg Day',
        startTime: DateTime(2025, 9, 15, 11, 22),
        endTime: DateTime(2025, 9, 15, 11, 30),
        exercises: const [skippedExercise],
        isCompleted: true,
      ),
      WorkoutSession(
        id: 'completed',
        name: 'Leg Day',
        startTime: DateTime(2025, 9, 12, 11, 13),
        endTime: DateTime(2025, 9, 12, 12, 0),
        exercises: const [completedExercise],
        isCompleted: true,
      ),
    ];

    GetIt.I.registerSingleton<WorkoutRepository>(_FakeWorkoutRepo(sessions));
    await registerPrefs();

    await tester.pumpWidget(
      const MaterialApp(home: ExerciseDetailScreen(exercise: ex)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    // Only the completed session should render (one grouped surface card).
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('75 kg × 10'), findsOneWidget);
    expect(find.textContaining('kg × 0'), findsNothing);
  });

  testWidgets('Cardio history uses distance + duration chips', (tester) async {
    const cardio = Exercise(
      name: 'Running (Treadmill)',
      muscles: ['Cardio'],
      kind: ExerciseKind.cardio,
      loggingMode: ExerciseLoggingMode.distanceDuration,
    );
    const wex = WorkoutExercise(
      id: 'run1',
      exercise: cardio,
      sets: [
        WorkoutSet(id: 's1', weight: 1.0, reps: 480, isCompleted: true),
        WorkoutSet(id: 's2', weight: 1.4, reps: 620, isCompleted: true),
      ],
    );
    final session = WorkoutSession(
      id: 'sess-run',
      name: 'Easy Run',
      startTime: DateTime(2024, 5, 12, 7, 30),
      exercises: const [wex],
      isCompleted: true,
    );
    GetIt.I.registerSingleton<WorkoutRepository>(_FakeWorkoutRepo([session]));
    await registerPrefs();

    await tester.pumpWidget(
      const MaterialApp(home: ExerciseDetailScreen(exercise: cardio)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('1 km × 08:00'), findsOneWidget);
    expect(find.text('1.4 km × 10:20'), findsOneWidget);
    // Cardio chips never fall back to the weight unit.
    expect(find.textContaining('kg ×'), findsNothing);
  });

  testWidgets('record tab quick ranges filter chart data and persist metric', (
    tester,
  ) async {
    final now = DateTime.now();
    Exercise exercise(String name) =>
        Exercise(name: name, muscles: const ['Chest']);

    final repo = _FakeWorkoutRepo([
      WorkoutSession(
        id: 's1',
        name: 'A',
        startTime: now.subtract(const Duration(days: 1)),
        exercises: [
          WorkoutExercise(
            id: 'e1',
            exercise: exercise('Bench'),
            sets: const [
              WorkoutSet(id: 'a', weight: 100, reps: 5, isCompleted: true),
            ],
          ),
        ],
        isCompleted: true,
      ),
      WorkoutSession(
        id: 's2',
        name: 'B',
        startTime: now.subtract(const Duration(days: 10)),
        exercises: [
          WorkoutExercise(
            id: 'e1',
            exercise: exercise('Bench'),
            sets: const [
              WorkoutSet(id: 'b', weight: 105, reps: 3, isCompleted: true),
            ],
          ),
        ],
        isCompleted: true,
      ),
      WorkoutSession(
        id: 's3',
        name: 'C',
        startTime: now.subtract(const Duration(days: 40)),
        exercises: [
          WorkoutExercise(
            id: 'e1',
            exercise: exercise('Bench'),
            sets: const [
              WorkoutSet(id: 'c', weight: 110, reps: 1, isCompleted: true),
            ],
          ),
        ],
        isCompleted: true,
      ),
    ]);
    GetIt.I.registerSingleton<WorkoutRepository>(repo);
    await registerPrefs();

    await tester.pumpWidget(
      MaterialApp(home: ExerciseDetailScreen(exercise: exercise('Bench'))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();

    // Wave I PR hero: a blue progress ring with the personal-record value as a
    // big numeral, plus the "Next target" suggestion below.
    expect(find.byType(AppProgressRing), findsOneWidget);
    expect(find.text('Personal record'), findsOneWidget);
    expect(find.text('Best set on record'), findsOneWidget);
    expect(find.textContaining('Next target'), findsOneWidget);

    await tester.tap(find.text('2w'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Next target'), findsOneWidget);

    await tester.tap(find.text('Est. 1RM'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Next target · est. 1RM'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(home: ExerciseDetailScreen(exercise: exercise('Bench'))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();

    // The Est. 1RM metric choice persists across screen recreation.
    expect(find.textContaining('Next target · est. 1RM'), findsOneWidget);
  });

  testWidgets('history list navigates to workout summary with highlight', (
    tester,
  ) async {
    const exercise = Exercise(name: 'Bench', muscles: ['Chest']);
    final session = WorkoutSession(
      id: 'summary-session',
      name: 'Bench Day',
      startTime: DateTime.now().subtract(const Duration(days: 1)),
      exercises: const [
        WorkoutExercise(
          id: 'e1',
          exercise: exercise,
          sets: [WorkoutSet(id: 's1', weight: 100, reps: 5, isCompleted: true)],
        ),
      ],
      isCompleted: true,
    );
    GetIt.I.registerSingleton<WorkoutRepository>(_FakeWorkoutRepo([session]));
    await registerPrefs();

    Object? receivedExtra;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const ExerciseDetailScreen(exercise: exercise),
        ),
        GoRoute(
          path: '/summary/:id',
          builder: (_, state) {
            receivedExtra = state.extra;
            return const Scaffold(body: Text('Workout Complete'));
          },
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    expect(find.text('Workout Complete'), findsOneWidget);
    expect(receivedExtra, {
      'highlightExerciseKey':
          exercise.canonicalKey ?? exercise.name.toLowerCase(),
    });
  });
}
