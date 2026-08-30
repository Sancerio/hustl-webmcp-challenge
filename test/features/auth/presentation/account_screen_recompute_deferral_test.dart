// Widget-level regression for the post-login web freeze on the Account screen.
//
// The legacy PR-flag migration (`recomputeAllPrFlags`) is O(all sessions) plus a
// full ~1.6MB persist and, on web (no isolates), runs inline on the single UI
// thread. The fix schedules it AFTER the screen's first frame so the UI paints
// first, and the migration is awaited off the stats critical path.
//
// This test proves the deferral contract at the widget level:
//  - The Account screen renders its stats content on the first pump.
//  - `recomputeAllPrFlags` is NOT called during initState/build — it only fires
//    after the first frame (post-frame callback), and at most once.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/navigation/current_route_service.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/auth/domain/entities/auth_user.dart';
import 'package:hustl_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:hustl_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hustl_app/features/auth/presentation/screens/account_screen.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/nutrition_target_plan.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';

class _RecordingWorkoutRepo implements WorkoutRepository {
  _RecordingWorkoutRepo(this._sessions);
  final List<WorkoutSession> _sessions;

  int recomputeCalls = 0;
  bool getSessionsCalledBeforeRecompute = false;
  bool _sawGetSessions = false;

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    _sawGetSessions = true;
    return List<WorkoutSession>.from(_sessions);
  }

  @override
  Future<void> recomputeAllPrFlags() async {
    recomputeCalls++;
    if (_sawGetSessions) getSessionsCalledBeforeRecompute = true;
  }

  // ---- Unused by the Account screen path: minimal stubs. ----
  WorkoutSession _empty() => WorkoutSession(
    id: 's',
    name: 'x',
    startTime: DateTime(2024),
    exercises: const [],
  );
  WorkoutExercise _emptyEx() => const WorkoutExercise(
    id: 'e',
    exercise: Exercise(name: 'x', muscles: []),
    sets: [],
  );

  @override
  Future<WorkoutSession> addExerciseToSession(
    String s,
    WorkoutExercise e,
  ) async => _empty();
  @override
  Future<WorkoutExercise> addSetToExercise(
    String s,
    String e,
    WorkoutSet x,
  ) async => _emptyEx();
  @override
  Future<WorkoutSession> completeWorkoutSession(String s) async => _empty();
  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession s) async => s;
  @override
  Future<void> deleteWorkoutSession(String id) async {}
  @override
  Future<bool> checkIfSetIsPR(
    String n,
    WorkoutSet s, {
    String? exerciseSlug,
  }) async => false;
  @override
  Future<ExercisePr?> getExercisePr(String n, {String? exerciseSlug}) async =>
      null;
  @override
  Future<DateTime?> getLastPerformedDate(
    String n, {
    String? exerciseSlug,
  }) async => null;
  @override
  Future<WorkoutSession?> getLatestActiveSession() async => null;
  @override
  Future<List<WorkoutSet>?> getPreviousExerciseSets(
    String n, {
    String? exerciseSlug,
  }) async => null;
  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async => null;
  @override
  Future<WorkoutSession> removeExerciseFromSession(String s, String e) async =>
      _empty();
  @override
  Future<WorkoutSession> updateExerciseInSession(
    String s,
    String e,
    WorkoutExercise x,
  ) async => _empty();
  @override
  Future<WorkoutExercise> updateSetInExercise(
    String s,
    String e,
    int i,
    WorkoutSet x,
  ) async => _emptyEx();
  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession s, {
    bool markDirty = true,
  }) async => s;
}

class _FakeNutritionTargetsRepo implements NutritionTargetsRepository {
  @override
  Future<NutritionTargetPlan?> getCurrentPlan(
    DateTime date, {
    bool readOnly = false,
  }) async => null;
  @override
  Future<Map<String, dynamic>> getWeightTrend(
    DateTime start,
    DateTime end,
  ) async => <String, dynamic>{'samples': <dynamic>[]};
  @override
  Future<void> addWeightSample(DateTime date, double weightKg) async {}
  @override
  Future<Map<String, dynamic>> getWeeklyAdherence(DateTime weekStart) async =>
      {};
  @override
  Future<Map<String, dynamic>> getWeeklyCheckIn(DateTime date) async => {};
  @override
  Future<NutritionTargetPlan?> applyWeeklyCheckIn(DateTime date) async => null;
  @override
  Future<void> skipWeeklyCheckIn(DateTime date) async {}
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuthedAuthRepo implements AuthRepository {
  _AuthedAuthRepo({this.failDelete = false});

  final bool failDelete;

  @override
  Future<AuthUser?> getCurrentUser() async =>
      const AuthUser(id: '1', provider: AuthProvider.google);
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteAccount() async {
    if (failDelete) throw Exception('network unavailable');
  }

  @override
  Future<AuthUser> signInWithGoogle() => throw UnimplementedError();
  @override
  Future<AuthUser> signInWithApple({
    required String identityToken,
    required String rawNonce,
    String? fullName,
  }) => throw UnimplementedError();
}

List<WorkoutSession> _seed(int count) {
  const ex = Exercise(
    name: 'Bench Press',
    slug: 'bench-press',
    muscles: ['Chest'],
  );
  final base = DateTime(2023, 1, 1, 9);
  return [
    for (int i = 0; i < count; i++)
      WorkoutSession(
        id: 'session-$i',
        name: 'Workout $i',
        startTime: base.add(Duration(hours: i * 30)),
        endTime: base.add(Duration(hours: i * 30 + 1)),
        isCompleted: true,
        exercises: [
          WorkoutExercise(
            id: 'ex-$i',
            exercise: ex,
            sets: [
              WorkoutSet(
                id: 's-$i',
                weight: 60.0 + i,
                reps: 5,
                isCompleted: true,
              ),
            ],
          ),
        ],
      ),
  ];
}

Future<void> _pump(
  WidgetTester tester, {
  AuthRepository? authRepository,
}) async {
  final authBloc = AuthBloc(authRepository ?? _AuthedAuthRepo())
    ..add(AuthCheckRequested());
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (c, s) => const AccountScreen()),
      GoRoute(path: '/progress', builder: (c, s) => const SizedBox()),
      GoRoute(path: '/settings', builder: (c, s) => const SizedBox()),
    ],
  );
  await tester.pumpWidget(
    BlocProvider<AuthBloc>.value(
      value: authBloc,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

void main() {
  late _RecordingWorkoutRepo repo;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    GetIt.instance.registerSingleton<PreferencesService>(prefs);
    repo = _RecordingWorkoutRepo(_seed(455));
    GetIt.instance.registerSingleton<WorkoutRepository>(repo);
    GetIt.instance.registerSingleton<NutritionTargetsRepository>(
      _FakeNutritionTargetsRepo(),
    );
    GetIt.instance.registerSingleton<CurrentRouteService>(
      CurrentRouteService(),
    );
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets(
    'legacy PR-flag migration is deferred via a post-frame callback and does '
    'not block stats/paint',
    (tester) async {
      // Schedule a synchronous probe in the SAME post-frame slot the screen uses
      // for the migration. addPostFrameCallback runs callbacks in registration
      // order, and the screen registers its callback in initState (before the
      // first frame), so this later-registered probe observes the migration's
      // synchronous lead-in: the migration starts only AFTER the first frame, so
      // when the probe runs the migration has not yet *completed* a full call.
      var probedRecomputeCalls = -1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        probedRecomputeCalls = repo.recomputeCalls;
      });

      await _pump(tester);

      // The migration is gated behind a pref read (await) inside a post-frame
      // callback, so it cannot have completed synchronously before other
      // post-frame work ran in the first frame.
      expect(
        probedRecomputeCalls,
        0,
        reason:
            'recomputeAllPrFlags must be deferred (post-frame + awaited pref '
            'gate), not run synchronously during the first frame',
      );

      // Drain the post-frame callback + stats/compute futures. Cannot use
      // pumpAndSettle here: the loading skeletons shimmer on a repeating
      // animation that never settles, so we pump fixed frames instead.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // The screen renders its content (the "This week" stats section).
      expect(find.text('This week'), findsOneWidget);

      // The migration ran exactly once, after the first frame.
      expect(repo.recomputeCalls, 1);
      expect(
        repo.getSessionsCalledBeforeRecompute,
        isTrue,
        reason:
            'stats load (getWorkoutSessions) must not be blocked behind the '
            'migration — it runs first so the screen can paint',
      );
    },
  );

  testWidgets('migration runs at most once across rebuilds', (tester) async {
    await _pump(tester);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Force extra rebuilds; the pref gate must keep the migration to one run.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(repo.recomputeCalls, 1);
  });

  testWidgets('delete account failure is surfaced on Account screen', (
    tester,
  ) async {
    await _pump(tester, authRepository: _AuthedAuthRepo(failDelete: true));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.ensureVisible(find.text('Delete account').last);
    await tester.tap(find.text('Delete account').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining("Couldn't delete account."), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
  });
}
