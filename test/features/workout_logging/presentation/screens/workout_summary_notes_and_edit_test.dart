import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/workout_edit_screen.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/presentation/screens/workout_summary_screen.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/workout_notes_sheet.dart';
import 'package:hustl_app/features/workout_templates/domain/models/workout_template.dart';
import 'package:hustl_app/features/workout_templates/domain/repositories/template_repository.dart';

class _RepoFake implements WorkoutRepository {
  WorkoutSession session;
  _RepoFake(this.session);

  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async => session;

  @override
  Future<WorkoutSession?> getLatestActiveSession() async => null; // avoid banner ticker effects

  // Unused
  @override
  Future<WorkoutSession> addExerciseToSession(
    String sessionId,
    WorkoutExercise exercise,
  ) => Future.error(UnimplementedError());
  @override
  Future<WorkoutExercise> addSetToExercise(
    String sessionId,
    String exerciseId,
    WorkoutSet set,
  ) => Future.error(UnimplementedError());
  @override
  Future<WorkoutSession> completeWorkoutSession(String sessionId) =>
      Future.error(UnimplementedError());
  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession session) =>
      Future.error(UnimplementedError());
  @override
  Future<void> deleteWorkoutSession(String id) =>
      Future.error(UnimplementedError());
  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) => Future.error(UnimplementedError());
  @override
  Future<List<WorkoutSet>?> getPreviousExerciseSets(
    String exerciseName, {
    String? exerciseSlug,
  }) => Future.value(null);
  @override
  Future<void> recomputeAllPrFlags() async {}
  @override
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  }) => Future.value(false);
  @override
  Future<WorkoutSession> updateExerciseInSession(
    String sessionId,
    String exerciseId,
    WorkoutExercise exercise,
  ) => Future.error(UnimplementedError());
  @override
  Future<WorkoutExercise> updateSetInExercise(
    String sessionId,
    String exerciseId,
    int setIndex,
    WorkoutSet set,
  ) => Future.error(UnimplementedError());
  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession session, {
    bool markDirty = true,
  }) => Future.value(session);
  @override
  Future<WorkoutSession> removeExerciseFromSession(
    String sessionId,
    String exerciseId,
  ) => Future.error(UnimplementedError());

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

class _TemplateRepoFake implements TemplateRepository {
  List<WorkoutTemplate> store;
  _TemplateRepoFake(this.store);

  @override
  Future<List<WorkoutTemplate>> getWorkoutTemplates() async => store;

  @override
  Future<WorkoutTemplate?> getWorkoutTemplate(String id) async =>
      store.firstWhere((t) => t.id == id);

  @override
  Future<WorkoutTemplate> createWorkoutTemplate(
    WorkoutTemplate template,
  ) async {
    final created = template.copyWith(id: 't_${store.length + 1}');
    store = [...store, created];
    return created;
  }

  @override
  Future<WorkoutTemplate> updateWorkoutTemplate(
    WorkoutTemplate template,
  ) async {
    store = [
      for (final t in store)
        if (t.id == template.id) template else t,
    ];
    return template;
  }

  @override
  Future<void> deleteWorkoutTemplate(String id) async {
    store = store.where((t) => t.id != id).toList();
  }
}

void main() {
  setUp(() async {
    final gi = GetIt.instance;
    await gi.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    gi.registerSingleton<PreferencesService>(prefs);
    await prefs.init();
  });

  tearDown(() async {
    await GetIt.instance.reset(dispose: true);
  });

  testWidgets('Shows notes and Edit opens WorkoutEditScreen', (tester) async {
    final session = WorkoutSession(
      id: 's1',
      name: 'Leg Day',
      startTime: DateTime(2024, 8, 2, 7, 30),
      endTime: DateTime(2024, 8, 2, 8, 40),
      notes: 'Go easy on knees',
      exercises: const [
        WorkoutExercise(
          id: 'e1',
          exercise: Exercise(name: 'Squat', muscles: []),
          sets: [
            WorkoutSet(id: 's1', weight: 100, reps: 5, isPr: false),
            WorkoutSet(id: 's2', weight: 100, reps: 5, isPr: true),
          ],
        ),
      ],
    );

    GetIt.instance.registerSingleton<WorkoutRepository>(_RepoFake(session));
    GetIt.instance.registerSingleton<TemplateRepository>(
      _TemplateRepoFake(const []),
    );

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const WorkoutSummaryScreen(sessionId: 's1'),
        ),
        GoRoute(
          path: '/workout_edit/:id',
          builder: (context, state) =>
              WorkoutEditScreen(sessionId: state.pathParameters['id']!),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    // Initial loading
    await tester.pump(const Duration(milliseconds: 200));

    // Notes section shows (sentence-case header).
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Go easy on knees'), findsOneWidget);

    // Tap Edit (app bar action) to navigate to edit screen. pumpAndSettle so
    // the edit screen's StaggeredEntrance timers complete before teardown.
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    expect(find.byType(WorkoutEditScreen), findsOneWidget);
  });

  testWidgets('notes sheet enables Save only on change', (tester) async {
    String? saved;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: Scaffold(
          body: WorkoutNotesSheet(
            initialText: 'Hello',
            onSave: (text) => saved = text,
            onClose: () {},
          ),
        ),
      ),
    );

    final saveFinder = find.byKey(const Key('notesSaveButton'));
    expect(saveFinder, findsOneWidget);
    expect(tester.widget<FilledButton>(saveFinder).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Hello world');
    await tester.pump();

    expect(tester.widget<FilledButton>(saveFinder).onPressed, isNotNull);
    await tester.tap(saveFinder);
    await tester.pump();
    expect(saved, 'Hello world');
  });

  testWidgets('notes suggestion chips append text and enable Save', (
    tester,
  ) async {
    String? saved;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: Scaffold(
          body: WorkoutNotesSheet(
            initialText: '',
            onSave: (text) => saved = text,
            onClose: () {},
          ),
        ),
      ),
    );

    const chipText = 'Felt strong today';
    await tester.tap(find.text(chipText));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.contains(chipText), isTrue);

    final saveFinder = find.byKey(const Key('notesSaveButton'));
    expect(tester.widget<FilledButton>(saveFinder).onPressed, isNotNull);
    await tester.tap(saveFinder);
    await tester.pump();

    expect(saved, isNotNull);
    expect(saved!.contains(chipText), isTrue);
  });
}
