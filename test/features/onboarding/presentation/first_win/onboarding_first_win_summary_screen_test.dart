import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/auth/domain/entities/auth_user.dart';
import 'package:hustl_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:hustl_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/onboarding/domain/coach_readiness_service.dart';
import 'package:hustl_app/features/onboarding/presentation/first_win/connected_system_graph.dart';
import 'package:hustl_app/features/onboarding/presentation/first_win/onboarding_first_win_summary_screen.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';

WorkoutSession _fakeSession() {
  const exercise = Exercise(name: 'Bench Press', muscles: []);
  final sets = List<WorkoutSet>.generate(
    3,
    (i) => WorkoutSet(id: 'set$i', weight: 100, reps: 10, isCompleted: true),
  );
  return WorkoutSession(
    id: 'abc',
    name: 'Push Day',
    startTime: DateTime(2026, 6, 26, 9, 0, 0),
    endTime: DateTime(2026, 6, 26, 9, 24, 18),
    exercises: [WorkoutExercise(id: 'ex1', exercise: exercise, sets: sets)],
    isCompleted: true,
  );
}

const _snapshot = CoachReadinessSnapshot(
  readiness: 0.42,
  workouts: 1,
  meals: 0,
  healthConnected: false,
  approvedProposals: 0,
  filledCount: 1,
  note: 'Log meals + connect Health to sharpen your plan.',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = PreferencesService();
    prefs.resetForTests();
    await prefs.init();
  });

  Future<void> pump(
    WidgetTester tester, {
    CoachReadinessService? readinessService,
  }) async {
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (context, state) => OnboardingFirstWinSummaryScreen(
            sessionId: 'abc',
            workoutRepository: _FakeWorkoutRepo(_fakeSession()),
            readinessService:
                readinessService ?? _StubReadinessService(_snapshot),
            preferencesService: prefs,
            animate: false,
          ),
        ),
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('HOME'))),
        ),
      ],
    );
    // Signed-in (non-guest) auth so the value-timed upgrade block stays hidden
    // and these assertions exercise the summary content unchanged. Provided
    // above MaterialApp so any pushed sheet could still resolve AuthBloc.
    final authBloc = AuthBloc(
      _FakeAuthRepository(
        const AuthUser(id: 'u', provider: AuthProvider.google),
      ),
    )..add(AuthCheckRequested());
    addTearDown(authBloc.close);
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders real session stats and the readiness gauge', (
    tester,
  ) async {
    await pump(tester);

    // Real numbers from the loaded session.
    expect(find.text('3'), findsOneWidget); // sets
    expect(find.text('3,000'), findsOneWidget); // volume (3 x 100 x 10)
    expect(find.text('24:18'), findsOneWidget); // duration
    expect(find.text('sets'), findsOneWidget);
    expect(find.text('exercises'), findsOneWidget);

    // Readiness gauge rendered (not the skeleton) with its note.
    expect(find.text('Coach readiness'), findsOneWidget);
    expect(find.textContaining('sharpen your plan'), findsOneWidget);
  });

  testWidgets('Lock in my plan sets both flags and routes home', (
    tester,
  ) async {
    await pump(tester);

    expect(prefs.onboardingIntroSeen, isFalse);
    expect(prefs.onboardingFirstWinSeen, isFalse);

    final cta = find.text('Lock in my plan');
    await tester.ensureVisible(cta);
    await tester.pumpAndSettle();
    await tester.tap(cta);
    await tester.pumpAndSettle();

    expect(prefs.onboardingIntroSeen, isTrue);
    expect(prefs.onboardingFirstWinSeen, isTrue);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets(
    'a failed readiness read renders a neutral gauge instead of shimmering '
    'forever',
    (tester) async {
      await pump(
        tester,
        readinessService: _ThrowingReadinessService(_FakeWorkoutRepo(null)),
      );

      // No crash from the rejected future, and no permanent skeleton: the
      // gauge itself renders, quietly zeroed out — no error copy on a
      // celebration screen.
      expect(tester.takeException(), isNull);
      final graph = tester.widget<ConnectedSystemGraph>(
        find.byType(ConnectedSystemGraph),
      );
      expect(graph.readiness, 0);
      expect(graph.filledCount, 0);
      expect(graph.readinessNote, isNull);
      expect(find.text('Coach readiness'), findsOneWidget);
    },
  );
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._user);

  final AuthUser? _user;

  @override
  Future<AuthUser?> getCurrentUser() async => _user;

  @override
  Future<AuthUser> signInWithGoogle() async =>
      _user ?? (throw UnimplementedError());

  @override
  Future<void> signOut() async {}

  @override
  Future<AuthUser> signInWithApple({
    required String identityToken,
    required String rawNonce,
    String? fullName,
  }) async => _user ?? (throw UnimplementedError());

  @override
  Future<void> deleteAccount() async {}
}

class _FakeWorkoutRepo implements WorkoutRepository {
  _FakeWorkoutRepo(this.session);

  final WorkoutSession? session;

  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async => session;

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => session == null ? const [] : [session!];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubReadinessService extends CoachReadinessService {
  _StubReadinessService(this._snap)
    : super(workoutRepository: _FakeWorkoutRepo(null));

  final CoachReadinessSnapshot _snap;

  @override
  Future<CoachReadinessSnapshot> snapshot() async => _snap;
}

class _ThrowingReadinessService extends CoachReadinessService {
  _ThrowingReadinessService(WorkoutRepository workoutRepository)
    : super(workoutRepository: workoutRepository);

  @override
  Future<CoachReadinessSnapshot> snapshot() async =>
      throw Exception('readiness read failed');
}
