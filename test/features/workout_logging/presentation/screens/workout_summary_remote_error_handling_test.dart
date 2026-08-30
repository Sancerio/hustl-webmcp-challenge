import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/token_storage.dart';
import 'package:hustl_app/core/widgets/hustl_inline_skeleton.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/data/datasources/hustl_backend_workout_history_api.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/presentation/screens/workout_summary_screen.dart';
import 'package:hustl_app/features/workout_templates/domain/models/workout_template.dart';
import 'package:hustl_app/features/workout_templates/domain/repositories/template_repository.dart';

class _TemplateRepoFake implements TemplateRepository {
  @override
  Future<List<WorkoutTemplate>> getWorkoutTemplates() async => const [];

  @override
  Future<void> deleteWorkoutTemplate(String id) async {}

  @override
  Future<WorkoutTemplate?> getWorkoutTemplate(String id) async => null;

  @override
  Future<WorkoutTemplate> createWorkoutTemplate(
    WorkoutTemplate template,
  ) async => template;

  @override
  Future<WorkoutTemplate> updateWorkoutTemplate(
    WorkoutTemplate template,
  ) async => template;
}

class _WorkoutRepoDelayed implements WorkoutRepository {
  _WorkoutRepoDelayed(this.session, {required this.delay});

  final WorkoutSession session;
  final Duration delay;

  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async {
    await Future<void>.delayed(delay);
    return session;
  }

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => [session];

  @override
  Future<WorkoutSession?> getLatestActiveSession() async => null;

  @override
  Future<void> deleteWorkoutSession(String id) async {}

  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession session) async =>
      session;

  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession session, {
    bool markDirty = true,
  }) async => session;

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
  Future<List<WorkoutSet>?> getPreviousExerciseSets(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;

  @override
  Future<void> recomputeAllPrFlags() async {}

  @override
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  }) async => false;

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
  Future<WorkoutSession> removeExerciseFromSession(
    String sessionId,
    String exerciseId,
  ) => Future.error(UnimplementedError());
}

class _WorkoutRepoMissing implements WorkoutRepository {
  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async => null;

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => const [];

  @override
  Future<WorkoutSession?> getLatestActiveSession() async => null;

  @override
  Future<void> deleteWorkoutSession(String id) async {}

  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession session) async =>
      session;

  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession session, {
    bool markDirty = true,
  }) async => session;

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
  Future<List<WorkoutSet>?> getPreviousExerciseSets(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;

  @override
  Future<void> recomputeAllPrFlags() async {}

  @override
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  }) async => false;

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
  Future<WorkoutSession> removeExerciseFromSession(
    String sessionId,
    String exerciseId,
  ) => Future.error(UnimplementedError());
}

/// Throws on the first `getWorkoutSession` call (simulating a transient load
/// failure), then succeeds on every subsequent call — exercising the
/// "Try again" retry path.
class _WorkoutRepoFailsOnce implements WorkoutRepository {
  _WorkoutRepoFailsOnce(this.session);

  final WorkoutSession session;
  int _callCount = 0;

  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async {
    _callCount++;
    if (_callCount == 1) {
      throw Exception('boom');
    }
    return session;
  }

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => [session];

  @override
  Future<WorkoutSession?> getLatestActiveSession() async => null;

  @override
  Future<void> deleteWorkoutSession(String id) async {}

  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession session) async =>
      session;

  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession session, {
    bool markDirty = true,
  }) async => session;

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
  Future<List<WorkoutSet>?> getPreviousExerciseSets(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;

  @override
  Future<void> recomputeAllPrFlags() async {}

  @override
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  }) async => false;

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
  Future<WorkoutSession> removeExerciseFromSession(
    String sessionId,
    String exerciseId,
  ) => Future.error(UnimplementedError());
}

class _HistoryApiThrows500 implements HustlBackendWorkoutHistoryApi {
  _HistoryApiThrows500(this.tokens);

  @override
  final TokenStorage tokens;

  @override
  Future<({List<Map<String, dynamic>> items, String? nextCursor})> listHistory({
    int limit = 50,
    String? cursor,
    String status = 'completed',
  }) => Future.error(UnimplementedError());

  @override
  Future<Map<String, dynamic>> fetchWorkoutDetail(String workoutId) async {
    throw HustlBackendWorkoutHistoryApiException(
      statusCode: 500,
      code: 'server_error',
      message: 'Server exploded',
    );
  }
}

void main() {
  testWidgets(
    'WorkoutSummaryScreen does not treat non-404 remote failures as not found',
    (tester) async {
      await GetIt.instance.reset(dispose: true);
      SharedPreferences.setMockInitialValues({});

      final prefs = PreferencesService();
      await prefs.init();
      GetIt.instance.registerSingleton<PreferencesService>(prefs);
      GetIt.instance.registerSingleton<TemplateRepository>(_TemplateRepoFake());
      GetIt.instance.registerSingleton<WorkoutRepository>(
        _WorkoutRepoMissing(),
      );

      final tokens = TokenStorage();
      await tokens.saveTokenPair(accessToken: 'token', expiresIn: 3600);
      GetIt.instance.registerSingleton<TokenStorage>(tokens);

      final historyApi = _HistoryApiThrows500(tokens);

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, __) {
              return Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => context.push('/summary'),
                    child: const Text('Go'),
                  ),
                ),
              );
            },
          ),
          GoRoute(
            path: '/summary',
            builder: (_, __) => WorkoutSummaryScreen(
              sessionId: 's1',
              historyApiOverride: historyApi,
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();

      await tester.tap(find.text('Go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Workout summary'), findsOneWidget);
      expect(find.text('Workout session not found'), findsNothing);
      expect(
        find.textContaining('We couldn\'t load this workout'),
        findsAtLeastNWidgets(1),
      );
      // The raw exception text must never leak into user-facing copy.
      expect(find.textContaining('Server exploded'), findsNothing);
    },
  );

  testWidgets(
    'WorkoutSummaryScreen shows a retryable error state instead of an '
    'endless skeleton on load failure, and Try again recovers',
    (tester) async {
      await GetIt.instance.reset(dispose: true);
      SharedPreferences.setMockInitialValues({});

      final prefs = PreferencesService();
      await prefs.init();
      GetIt.instance.registerSingleton<PreferencesService>(prefs);
      GetIt.instance.registerSingleton<TemplateRepository>(_TemplateRepoFake());

      final session = WorkoutSession(
        id: 's1',
        name: 'Session',
        startTime: DateTime(2024, 1, 1, 8),
        endTime: DateTime(2024, 1, 1, 9),
        exercises: const [
          WorkoutExercise(
            id: 'e1',
            exercise: Exercise(name: 'Bench', muscles: []),
            sets: [
              WorkoutSet(id: 'set1', weight: 100, reps: 5, isCompleted: true),
            ],
          ),
        ],
      );
      GetIt.instance.registerSingleton<WorkoutRepository>(
        _WorkoutRepoFailsOnce(session),
      );

      await tester.pumpWidget(
        const MaterialApp(home: WorkoutSummaryScreen(sessionId: 's1')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(HustlInlineSkeleton), findsNothing);
      expect(find.text('We couldn\'t load this workout'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('We couldn\'t load this workout'), findsNothing);
      expect(find.byType(HustlInlineSkeleton), findsNothing);
      expect(find.text('Workout complete'), findsOneWidget);
    },
  );

  testWidgets('WorkoutSummaryScreen does not setState after dispose', (
    tester,
  ) async {
    await GetIt.instance.reset(dispose: true);
    SharedPreferences.setMockInitialValues({});

    final prefs = PreferencesService();
    await prefs.init();
    GetIt.instance.registerSingleton<PreferencesService>(prefs);
    GetIt.instance.registerSingleton<TemplateRepository>(_TemplateRepoFake());

    final session = WorkoutSession(
      id: 's1',
      name: 'Session',
      startTime: DateTime(2024, 1, 1, 8),
      endTime: DateTime(2024, 1, 1, 9),
      exercises: const [
        WorkoutExercise(
          id: 'e1',
          exercise: Exercise(name: 'Bench', muscles: []),
          sets: [
            WorkoutSet(id: 'set1', weight: 100, reps: 5, isCompleted: true),
          ],
        ),
      ],
    );
    GetIt.instance.registerSingleton<WorkoutRepository>(
      _WorkoutRepoDelayed(session, delay: const Duration(milliseconds: 80)),
    );

    await tester.pumpWidget(
      const MaterialApp(home: WorkoutSummaryScreen(sessionId: 's1')),
    );
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpWidget(const SizedBox.shrink());

    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });
}
