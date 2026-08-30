import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/token_storage.dart' as token;
import 'package:hustl_app/core/widgets/hustl_inline_skeleton.dart';
import 'package:hustl_app/features/auth/domain/entities/auth_user.dart';
import 'package:hustl_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:hustl_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/workout_edit_screen.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/workout_history_screen.dart';
import 'package:hustl_app/features/workout_logging/data/datasources/hustl_backend_workout_history_api.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/rest_timer_widget.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';

class _AuthRepoFake implements AuthRepository {
  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<AuthUser?> getCurrentUser() async => null;

  @override
  Future<AuthUser> signInWithGoogle() => Future.error(UnimplementedError());

  @override
  Future<AuthUser> signInWithApple({
    required String identityToken,
    required String rawNonce,
    String? fullName,
  }) => Future.error(UnimplementedError());
}

class _TokenStorageFake implements token.TokenStorage {
  _TokenStorageFake(this._token, {this.delay = Duration.zero});

  String? _token;
  final Duration delay;

  @override
  Future<String?> getAccessToken() async {
    await Future<void>.delayed(delay);
    return _token;
  }

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<void> saveTokenPair({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
  }) async {
    _token = accessToken;
  }

  @override
  Future<void> clearAccessToken() async {
    _token = null;
  }

  @override
  Future<void> clearAll() async {
    _token = null;
  }
}

class _WorkoutRepoFake implements WorkoutRepository {
  _WorkoutRepoFake(this.sessions);

  final List<WorkoutSession> sessions;

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => sessions;

  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async {
    for (final session in sessions) {
      if (session.id == id) {
        return session;
      }
    }
    return null;
  }

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
  Future<void> recomputeAllPrFlags() async {}

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
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  }) async => false;

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
}

class _RepoSpy implements WorkoutRepository {
  _RepoSpy(this.session);

  WorkoutSession session;
  int updateCalls = 0;
  int recomputeCalls = 0;

  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async => session;

  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession updated, {
    bool markDirty = true,
  }) async {
    updateCalls += 1;
    session = updated.copyWith(dirty: markDirty ? true : updated.dirty);
    return session;
  }

  @override
  Future<void> recomputeAllPrFlags() async {
    recomputeCalls += 1;
  }

  @override
  Future<WorkoutSession?> getLatestActiveSession() async => null;

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
  }) async => null;

  @override
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  }) async => false;

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
}

class _HistoryApiSlow implements HustlBackendWorkoutHistoryApi {
  _HistoryApiSlow({required this.tokens, required this.listDelay});

  @override
  final token.TokenStorage tokens;

  final Duration listDelay;

  @override
  Future<({List<Map<String, dynamic>> items, String? nextCursor})> listHistory({
    int limit = 50,
    String? cursor,
    String status = 'completed',
  }) async {
    await Future<void>.delayed(listDelay);
    return (items: const <Map<String, dynamic>>[], nextCursor: null);
  }

  @override
  Future<Map<String, dynamic>> fetchWorkoutDetail(String workoutId) =>
      Future.error(UnimplementedError());
}

class _HistoryApiSequence implements HustlBackendWorkoutHistoryApi {
  _HistoryApiSequence(this.pages, {token.TokenStorage? tokens})
    : _tokens = tokens ?? _TokenStorageFake('token');

  final List<({List<Map<String, dynamic>> items, String? nextCursor})> pages;
  final token.TokenStorage _tokens;
  int calls = 0;

  @override
  token.TokenStorage get tokens => _tokens;

  @override
  Future<({List<Map<String, dynamic>> items, String? nextCursor})> listHistory({
    int limit = 50,
    String? cursor,
    String status = 'completed',
  }) async {
    final index = calls;
    calls += 1;
    if (index < pages.length) {
      return pages[index];
    }
    return (items: const <Map<String, dynamic>>[], nextCursor: null);
  }

  @override
  Future<Map<String, dynamic>> fetchWorkoutDetail(String workoutId) =>
      Future.error(UnimplementedError());
}

class _HistoryApiEmptyDetail implements HustlBackendWorkoutHistoryApi {
  _HistoryApiEmptyDetail(this.name);

  final String name;

  @override
  token.TokenStorage get tokens => _TokenStorageFake('token');

  @override
  Future<({List<Map<String, dynamic>> items, String? nextCursor})> listHistory({
    int limit = 50,
    String? cursor,
    String status = 'completed',
  }) async => (items: const <Map<String, dynamic>>[], nextCursor: null);

  @override
  Future<Map<String, dynamic>> fetchWorkoutDetail(String workoutId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return {
      'id': workoutId,
      'name': name,
      'start_time': DateTime(2024, 1, 1, 8).toUtc().toIso8601String(),
      'end_time': DateTime(2024, 1, 1, 9).toUtc().toIso8601String(),
      'status': 'completed',
      'exercises': const <Map<String, dynamic>>[],
    };
  }
}

void main() {
  setUp(() async {
    await GetIt.instance.reset(dispose: true);
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    GetIt.instance.registerSingleton<PreferencesService>(prefs);
  });

  testWidgets('tapping Edit on a history entry opens WorkoutEditScreen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final sessions = [
      WorkoutSession(
        id: 's1',
        name: 'Upper Body',
        startTime: DateTime(2024, 8, 1, 9, 0),
        endTime: DateTime(2024, 8, 1, 10, 0),
        notes: 'Felt strong',
        exercises: const [
          WorkoutExercise(
            id: 'e1',
            exercise: Exercise(name: 'Bench Press', muscles: []),
            sets: [WorkoutSet(id: 'set1', weight: 80, reps: 5, isPr: true)],
          ),
        ],
      ),
    ];
    GetIt.instance.registerSingleton<WorkoutRepository>(
      _WorkoutRepoFake(sessions),
    );

    final authBloc = AuthBloc(_AuthRepoFake())..add(AuthCheckRequested());
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => BlocProvider<AuthBloc>.value(
            value: authBloc,
            child: const WorkoutHistoryScreen(),
          ),
        ),
        GoRoute(
          path: '/summary/:id',
          builder: (context, state) => Scaffold(
            appBar: AppBar(title: const Text('Summary')),
            body: const Text('Summary Screen'),
          ),
        ),
        GoRoute(
          path: '/workout_edit/:id',
          builder: (context, state) =>
              WorkoutEditScreen(sessionId: state.pathParameters['id']!),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Upper Body'), findsOneWidget);

    final ink = find.ancestor(
      of: find.text('Upper Body'),
      matching: find.byType(InkWell),
    );

    // Tapping a card now opens the summary directly.
    await tester.tap(ink);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Summary Screen'), findsOneWidget);

    // Back to history and long-press to reveal the action menu.
    await tester.pageBack();
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.longPress(ink);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.widgetWithText(ListTile, 'Edit workout'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'View summary'), findsOneWidget);

    final editTile = find.widgetWithText(ListTile, 'Edit workout');
    await tester.ensureVisible(editTile);
    await tester.tap(editTile, warnIfMissed: false);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(WorkoutEditScreen), findsOneWidget);
  });

  testWidgets('swiping a history card prompts a delete confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final prefs = GetIt.instance<PreferencesService>();
    await prefs.dismissSyncBanner();

    final sessions = [
      WorkoutSession(
        id: 's1',
        name: 'Leg Day',
        startTime: DateTime(2024, 8, 1, 9, 0),
        endTime: DateTime(2024, 8, 1, 10, 0),
        exercises: const [
          WorkoutExercise(
            id: 'e1',
            exercise: Exercise(name: 'Squat', muscles: []),
            sets: [WorkoutSet(id: 'set1', weight: 100, reps: 5)],
          ),
        ],
      ),
    ];
    GetIt.instance.registerSingleton<WorkoutRepository>(
      _WorkoutRepoFake(sessions),
    );

    final authBloc = AuthBloc(_AuthRepoFake())..add(AuthCheckRequested());
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => BlocProvider<AuthBloc>.value(
            value: authBloc,
            child: const WorkoutHistoryScreen(),
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Leg Day'), findsOneWidget);
    expect(find.byType(Dismissible), findsOneWidget);

    await tester.drag(find.text('Leg Day'), const Offset(-500, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Delete workout'), findsOneWidget);
    // Cancelling keeps the card in place.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Leg Day'), findsOneWidget);
  });

  testWidgets('WorkoutHistoryScreen does not setState after dispose', (
    tester,
  ) async {
    final prefs = GetIt.instance<PreferencesService>();
    await prefs.dismissSyncBanner();
    GetIt.instance.registerSingleton<WorkoutRepository>(
      _WorkoutRepoFake(const []),
    );

    final authBloc = AuthBloc(_AuthRepoFake())..add(AuthCheckRequested());
    final api = _HistoryApiSlow(
      tokens: _TokenStorageFake(
        'token',
        delay: const Duration(milliseconds: 50),
      ),
      listDelay: const Duration(milliseconds: 100),
    );

    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp(home: WorkoutHistoryScreen(historyApiOverride: api)),
      ),
    );

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });

  testWidgets('filters server history items by local workout tombstones', (
    tester,
  ) async {
    final prefs = GetIt.instance<PreferencesService>();
    await prefs.addWorkoutsDeletedId('w1');
    await prefs.dismissSyncBanner();

    GetIt.instance.registerSingleton<WorkoutRepository>(
      _WorkoutRepoFake(const []),
    );
    GetIt.instance.registerSingleton<token.TokenStorage>(
      _TokenStorageFake('token'),
    );

    final api = _HistoryApiSequence([
      (
        items: [
          {
            'id': 'w1',
            'name': 'Deleted Workout',
            'start_time': DateTime(2024, 1, 1, 8).toUtc().toIso8601String(),
            'end_time': DateTime(2024, 1, 1, 9).toUtc().toIso8601String(),
            'status': 'completed',
            'exercises': const [],
          },
          {
            'id': 'w2',
            'name': 'Kept Workout',
            'start_time': DateTime(2024, 1, 2, 8).toUtc().toIso8601String(),
            'end_time': DateTime(2024, 1, 2, 9).toUtc().toIso8601String(),
            'status': 'completed',
            'exercises': const [],
          },
        ],
        nextCursor: null,
      ),
    ]);

    final authBloc = AuthBloc(_AuthRepoFake())..add(AuthCheckRequested());
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp(home: WorkoutHistoryScreen(historyApiOverride: api)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Deleted Workout'), findsNothing);
    expect(find.text('Kept Workout'), findsOneWidget);
  });

  testWidgets('start-from-history works when remote detail has no exercises', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final prefs = GetIt.instance<PreferencesService>();
    await prefs.dismissSyncBanner();
    GetIt.instance.registerSingleton<token.TokenStorage>(
      _TokenStorageFake('token'),
    );

    final session = WorkoutSession(
      id: 'w-empty',
      name: 'Empty Workout',
      startTime: DateTime(2024, 1, 1, 8),
      endTime: DateTime(2024, 1, 1, 9),
      exercises: const [],
    );
    GetIt.instance.registerSingleton<WorkoutRepository>(
      _WorkoutRepoFake([session]),
    );

    final authBloc = AuthBloc(_AuthRepoFake())..add(AuthCheckRequested());
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => BlocProvider<AuthBloc>.value(
            value: authBloc,
            child: WorkoutHistoryScreen(
              historyApiOverride: _HistoryApiEmptyDetail(session.name),
            ),
          ),
        ),
        GoRoute(
          path: '/workout_session',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            final initialExercises =
                (extra?['initialExercises'] as List<dynamic>? ?? const []);
            return Scaffold(
              body: Text('workout_session:${initialExercises.length}'),
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Empty Workout'), findsOneWidget);

    final ink = find
        .ancestor(
          of: find.text('Empty Workout'),
          matching: find.byType(InkWell),
        )
        .first;
    await tester.longPress(ink);
    await tester.pump(const Duration(milliseconds: 300));

    final startTile = find.widgetWithText(ListTile, 'Repeat this workout');
    expect(startTile, findsOneWidget);
    final startAction = tester.widget<ListTile>(startTile).onTap;
    expect(startAction, isNotNull);
    startAction!.call();
    await tester.pump();

    expect(find.byType(HustlInlineSkeleton), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(HustlInlineSkeleton), findsOneWidget);

    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('workout_session:0'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/workout_session');
  });

  testWidgets('save triggers update and PR recompute in edit mode', (
    tester,
  ) async {
    final initial = WorkoutSession(
      id: 's1',
      name: 'Original',
      startTime: DateTime(2024, 8, 1, 9, 0),
      endTime: DateTime(2024, 8, 1, 10, 0),
      notes: 'n1',
      exercises: [
        const WorkoutExercise(
          id: 'e1',
          exercise: Exercise(name: 'Bench', muscles: []),
          sets: [WorkoutSet(id: 'set1', weight: 60, reps: 5)],
        ),
      ],
    );
    final repo = _RepoSpy(initial);
    GetIt.instance.registerSingleton<WorkoutRepository>(repo);

    await tester.pumpWidget(
      const MaterialApp(home: WorkoutEditScreen(sessionId: 's1')),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(RestTimerWidget), findsNothing);

    final nameField = find.byType(TextFormField).first;
    await tester.enterText(nameField, 'Edited');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.save));
    await tester.pump();

    expect(find.text('Workout saved.'), findsOneWidget);
    expect(repo.updateCalls, 1);
    expect(repo.recomputeCalls, 1);
    // The save toast offers an Undo action (now a HustlSnack action button).
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('edit screen guards a back-out with unsaved changes', (
    tester,
  ) async {
    final initial = WorkoutSession(
      id: 's1',
      name: 'Original',
      startTime: DateTime(2024, 8, 1, 9, 0),
      endTime: DateTime(2024, 8, 1, 10, 0),
      exercises: const [
        WorkoutExercise(
          id: 'e1',
          exercise: Exercise(name: 'Bench', muscles: []),
          sets: [WorkoutSet(id: 'set1', weight: 60, reps: 5)],
        ),
      ],
    );
    GetIt.instance.registerSingleton<WorkoutRepository>(_RepoSpy(initial));

    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Text('History root')),
        GoRoute(
          path: '/workout_edit/:id',
          builder: (context, state) =>
              WorkoutEditScreen(sessionId: state.pathParameters['id']!),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    router.push('/workout_edit/s1');
    await tester.pumpAndSettle();

    // Make the form dirty.
    await tester.enterText(find.byType(TextFormField).first, 'Edited');
    await tester.pump();

    // Attempt to leave via the system back button: the PopScope guard surfaces
    // a discard confirmation instead of silently dropping the edits.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.byType(WorkoutEditScreen), findsOneWidget);

    // Keep editing dismisses the dialog without leaving.
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutEditScreen), findsOneWidget);
  });
}
