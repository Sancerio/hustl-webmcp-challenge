import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/widgets/hustl_inline_skeleton.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_log/data/datasources/body_score_api.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_service.dart';
import 'package:hustl_app/features/workout_log/domain/utils/time_periods.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/body_score_screen.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/body_score/this_week_by_region.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';

/// Guards the codex [P3] (PR #385, body_score_screen.dart:_onPeriodChanged):
/// switching INTO the in-progress current week used to flip the build into the
/// current-week branch on the SAME synchronous frame it changed the period,
/// BEFORE the (un-awaited) async recompute repopulated _currentWeekRegions /
/// _trendWeeks - so the surface rendered empty `[]` current-week fields (the
/// current-week empty state) for a frame. The fix raises a switching flag that
/// holds the loading skeleton until the recompute lands.
class _BodyScoreApiStub implements BodyScoreApi {
  const _BodyScoreApiStub();
  @override
  Future<BodyScoreSummary?> fetchLatest({int windowDays = 28}) async => null;
}

/// A [PreferencesService] whose period WRITE throws, to drive the period-switch
/// error path ([_onPeriodChanged]'s try/catch/finally). Reads used during
/// startup (period, migration marker, coach-explains) are stubbed so the screen
/// loads normally on the closed period; only the `bodyScorePeriodPrefKey` write
/// blows up - exactly the prefs-write failure the fix must recover from.
/// [PreferencesService] is a singleton with a private generative constructor,
/// so we mock via `implements` (mocktail) rather than subclassing.
class _MockPrefs extends Mock implements PreferencesService {}

class _Repo implements WorkoutRepository {
  final List<WorkoutSession> sessions;
  _Repo(this.sessions);
  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => sessions;
  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WorkoutSession _session(String muscle, int setCount, DateTime day) {
  return WorkoutSession(
    id: 'session-$muscle-${day.millisecondsSinceEpoch}',
    name: '$muscle day',
    startTime: day,
    endTime: day.add(const Duration(hours: 1)),
    isCompleted: true,
    exercises: [
      WorkoutExercise(
        id: 'ex-$muscle-${day.millisecondsSinceEpoch}',
        exercise: Exercise(name: '$muscle move', muscles: [muscle]),
        sets: [
          for (var i = 0; i < setCount; i++)
            WorkoutSet(
              id: 'set-$muscle-$i-${day.millisecondsSinceEpoch}',
              weight: 100,
              reps: 8,
              isCompleted: true,
            ),
        ],
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: BodyScoreScreen()));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final getIt = GetIt.instance;

  void resetGetIt() {
    if (getIt.isRegistered<WorkoutRepository>()) {
      getIt.unregister<WorkoutRepository>();
    }
    if (getIt.isRegistered<PreferencesService>()) {
      getIt.unregister<PreferencesService>();
    }
    if (getIt.isRegistered<BodyScoreApi>()) {
      getIt.unregister<BodyScoreApi>();
    }
  }

  setUp(() {
    // Start on a CLOSED period (last full week): seed the migration marker so the
    // one-time current-week default does NOT override, and the stored period.
    SharedPreferences.setMockInitialValues({
      bodyScoreCurrentWeekMigrationKey: 'done',
      bodyScorePeriodPrefKey: BodyScorePeriod.lastFullWeek.id,
    });
    resetGetIt();
    getIt.registerSingleton<PreferencesService>(PreferencesService());
    getIt.registerSingleton<BodyScoreApi>(const _BodyScoreApiStub());
  });

  tearDown(() {
    // Clear the one-shot recompute-failure hook so a test that armed it can
    // never leak the injected throw into a later test.
    debugBodyScoreRecomputeFailureForTest = null;
    resetGetIt();
  });

  testWidgets(
    'switching into the current week never renders empty current-week fields',
    (tester) async {
      final now = DateTime.now();
      final weekStart = startOfWeek(now);
      final lastWeekStart = weekStart.subtract(const Duration(days: 7));
      // Work in BOTH last week (closed view has content) and this week (the IA
      // has content), so neither view is legitimately empty.
      final sessions = [
        _session('Chest', 8, lastWeekStart.add(const Duration(days: 2))),
        _session('Lats', 6, lastWeekStart.add(const Duration(days: 3))),
        _session('Abs', 5, weekStart.add(const Duration(days: 1))),
        _session('Obliques', 5, weekStart.add(const Duration(days: 1))),
        _session('Quads', 3, weekStart.add(const Duration(days: 2))),
        _session('Chest', 8, weekStart.add(const Duration(days: 3))),
      ];
      getIt.registerSingleton<WorkoutRepository>(_Repo(sessions));

      await _pump(tester);

      // We start on the closed period: the current-week IA is NOT shown.
      expect(find.byType(ThisWeekByRegion), findsNothing);
      expect(find.text('This week, by region'), findsNothing);

      // Open the period popup and pick "This week". The closed-period view has a
      // looping radar entrance animation, so pumpAndSettle would never return -
      // drive discrete pumps to open the menu instead.
      await tester.tap(find.byTooltip('Change period'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('This week').last);

      // Drive the switch frame-by-frame. The fix holds the loading skeleton
      // (driven by the switching flag) until the recompute repopulates the
      // current-week fields, so at NO point during the switch does the surface
      // render the current-week branch with empty `[]` fields (its empty state).
      // Without the fix, the synchronous `setState(_selectedPeriod=...)` flips
      // the build into the current-week branch a frame before the recompute,
      // surfacing "Your balance score starts here" for that frame.
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.text('Your balance score starts here'),
          findsNothing,
          reason:
              'the current-week empty state must never render mid-switch '
              '(stale/empty frame regression)',
        );
      }

      // The switch has settled on the fully-populated current-week IA.
      expect(find.byType(HustlInlineSkeleton), findsNothing);
      expect(find.byType(ThisWeekByRegion), findsOneWidget);
      expect(find.text('This week, by region'), findsOneWidget);
    },
  );

  testWidgets(
    'a period-switch prefs-write/recompute failure recovers to the error UI '
    '(not a permanent skeleton)',
    (tester) async {
      // Swap in a PreferencesService whose period WRITE throws. The screen
      // reads the service in a field initializer during pumpWidget, so it must
      // be registered BEFORE the first pump.
      final prefs = _MockPrefs();
      // Startup reads: on a closed period, no current-week migration override.
      when(() => prefs.getRawString(bodyScoreCurrentWeekMigrationKey))
          .thenAnswer((_) async => 'done');
      when(() => prefs.getRawString(bodyScorePeriodPrefKey))
          .thenAnswer((_) async => BodyScorePeriod.lastFullWeek.id);
      when(() => prefs.getCoachExplainsEnabled()).thenAnswer((_) async => false);
      // The period switch WRITE throws - the failure the fix must recover from.
      when(() => prefs.setRawString(bodyScorePeriodPrefKey, any()))
          .thenThrow(StateError('simulated period prefs write failure'));
      if (getIt.isRegistered<PreferencesService>()) {
        getIt.unregister<PreferencesService>();
      }
      getIt.registerSingleton<PreferencesService>(prefs);

      final now = DateTime.now();
      final weekStart = startOfWeek(now);
      final lastWeekStart = weekStart.subtract(const Duration(days: 7));
      final sessions = [
        _session('Chest', 8, lastWeekStart.add(const Duration(days: 2))),
        _session('Lats', 6, lastWeekStart.add(const Duration(days: 3))),
        _session('Abs', 5, weekStart.add(const Duration(days: 1))),
        _session('Quads', 3, weekStart.add(const Duration(days: 2))),
      ];
      getIt.registerSingleton<WorkoutRepository>(_Repo(sessions));

      await _pump(tester);

      // Loaded on the closed period with content, no skeleton, no error.
      expect(find.byType(HustlInlineSkeleton), findsNothing);
      expect(find.text('Unable to switch period'), findsNothing);

      // Switch to "This week" - the period write throws inside the awaited
      // sequence, exercising the try/catch/finally error-recovery branch.
      await tester.tap(find.byTooltip('Change period'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('This week').last);
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // The surface RECOVERED: the error UI is shown and the loading skeleton
      // is GONE. Without the finally, `_switchingPeriod` would stay true and
      // the skeleton would be stuck forever (a permanent unrecoverable state).
      expect(
        find.byType(HustlInlineSkeleton),
        findsNothing,
        reason:
            'a throwing period switch must clear _switchingPeriod via the '
            'finally - never strand a permanent skeleton',
      );
      expect(find.text('Unable to switch period'), findsOneWidget);
      // The error UI offers a retry, and the current-week IA is NOT rendered
      // (the error path short-circuits before any period content).
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(ThisWeekByRegion), findsNothing);
    },
  );

  testWidgets(
    'a successful pref WRITE followed by a recompute THROW keeps the displayed '
    'period and the persisted pref CONSISTENT (no silent next-load jump)',
    (tester) async {
      // The [P2] fix-introduced desync: _onPeriodChanged awaited the period
      // pref WRITE and THEN the (throw-prone) recompute inside ONE try; the old
      // catch UNCONDITIONALLY snapped _selectedPeriod back to the previous
      // period. So when the WRITE succeeded but the recompute THREW, the
      // persisted pref held the NEW period while the screen showed the OLD one -
      // and on the next app load readPersistedBodyScorePeriod read the NEW
      // period, silently jumping the surface to the period the user was just
      // told failed to switch.
      //
      // We use the REAL PreferencesService (genuine SharedPreferences persistence)
      // so the WRITE truly lands, and arm the one-shot recompute-failure hook so
      // the recompute - and ONLY the recompute - throws after that write.
      final prefs = PreferencesService();
      if (getIt.isRegistered<PreferencesService>()) {
        getIt.unregister<PreferencesService>();
      }
      getIt.registerSingleton<PreferencesService>(prefs);
      // Pin the starting state through the LIVE service the screen will read, so
      // this test is hermetic regardless of order (an earlier test that switched
      // to the current week leaves that persisted in the shared mock store). We
      // start CLOSED (last full week) with the migration already done, so the
      // switch to "This week" below is a genuine change.
      await prefs.setRawString(bodyScoreCurrentWeekMigrationKey, 'done');
      await prefs.setRawString(
        bodyScorePeriodPrefKey,
        BodyScorePeriod.lastFullWeek.id,
      );

      final now = DateTime.now();
      final weekStart = startOfWeek(now);
      final lastWeekStart = weekStart.subtract(const Duration(days: 7));
      final sessions = [
        _session('Chest', 8, lastWeekStart.add(const Duration(days: 2))),
        _session('Lats', 6, lastWeekStart.add(const Duration(days: 3))),
        _session('Abs', 5, weekStart.add(const Duration(days: 1))),
        _session('Quads', 3, weekStart.add(const Duration(days: 2))),
        _session('Chest', 8, weekStart.add(const Duration(days: 3))),
      ];
      getIt.registerSingleton<WorkoutRepository>(_Repo(sessions));

      await _pump(tester);

      // Loaded on the closed (last-full-week) period with content, and that is
      // what is persisted going in.
      expect(find.byType(HustlInlineSkeleton), findsNothing);
      expect(find.text('Unable to switch period'), findsNothing);
      // Confirm we genuinely loaded on the CLOSED period (the current-week IA is
      // not shown), and that closed period is what is persisted going in.
      expect(find.byType(ThisWeekByRegion), findsNothing);
      expect(
        await prefs.getRawString(bodyScorePeriodPrefKey),
        BodyScorePeriod.lastFullWeek.id,
      );

      // Arm the one-shot hook: the NEXT recompute (the one the period switch
      // kicks off, AFTER the successful pref write) throws. The initial-load
      // recompute already ran during _pump, so it is unaffected.
      debugBodyScoreRecomputeFailureForTest = StateError(
        'simulated recompute failure after a successful period pref write',
      );

      // Switch to "This week": the pref write SUCCEEDS, then the recompute THROWS.
      await tester.tap(find.byTooltip('Change period'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('This week').last);
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // The surface RECOVERED to the error UI (no permanent skeleton).
      expect(find.byType(HustlInlineSkeleton), findsNothing);
      expect(find.text('Unable to switch period'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      // CONSISTENCY INVARIANT: the WRITE succeeded, so the persisted pref now
      // holds the NEW (current-week) period. The fix must NOT snap the displayed
      // period back to last-full-week, or the persisted pref and the display
      // would desync and the next load would silently jump.
      expect(
        await prefs.getRawString(bodyScorePeriodPrefKey),
        BodyScorePeriod.currentWeek.id,
        reason:
            'the successful pref write must remain persisted on the new period',
      );
      // What the NEXT app load would read: the current week - matching what the
      // surface now displays, so there is NO silent jump.
      expect(
        await readPersistedBodyScorePeriod(prefs),
        BodyScorePeriod.currentWeek,
        reason:
            'next-load read must match the displayed period (no silent jump to '
            'a period the user was told failed to switch)',
      );

      // Behavioral proof the in-memory _selectedPeriod is ALSO the current week
      // (not snapped back): the hook is one-shot and now cleared, so tapping the
      // error UI's retry re-runs the recompute on _selectedPeriod. If the display
      // were (wrongly) snapped to last-full-week, the retry would rebuild the
      // CLOSED view; instead it settles on the current-week IA, which only renders
      // when _selectedPeriod is the current week - so display == persisted pref.
      await tester.tap(find.text('Try again'));
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(HustlInlineSkeleton), findsNothing);
      expect(find.text('Unable to switch period'), findsNothing);
      expect(find.byType(ThisWeekByRegion), findsOneWidget);
      expect(find.text('This week, by region'), findsOneWidget);
    },
  );

  group('bodyScoreShowSkeletonForTest (period-switch guard)', () {
    test('switching period holds the skeleton even with prior data loaded', () {
      // The regression: when switching INTO the current week, the prior closed
      // period's summary + region data are still loaded (hasPrimarySummary /
      // hasRegionSummaries true), so the legacy `loading && !data` predicate
      // would NOT show the skeleton and the build would render the new period's
      // branch against the stale/empty current-week fields. The switching term
      // forces the skeleton across the async recompute.
      expect(
        bodyScoreShowSkeletonForTest(
          switchingPeriod: true,
          loading: false,
          hasPrimarySummary: true,
          hasRegionSummaries: true,
          hasError: false,
        ),
        isTrue,
      );
    });

    test('settled (not switching) with data shows content, not the skeleton', () {
      expect(
        bodyScoreShowSkeletonForTest(
          switchingPeriod: false,
          loading: false,
          hasPrimarySummary: true,
          hasRegionSummaries: true,
          hasError: false,
        ),
        isFalse,
      );
    });

    test('first load with no data yet shows the skeleton', () {
      expect(
        bodyScoreShowSkeletonForTest(
          switchingPeriod: false,
          loading: true,
          hasPrimarySummary: false,
          hasRegionSummaries: false,
          hasError: false,
        ),
        isTrue,
      );
    });

    test('an error suppresses the skeleton, even mid-switch', () {
      expect(
        bodyScoreShowSkeletonForTest(
          switchingPeriod: true,
          loading: true,
          hasPrimarySummary: false,
          hasRegionSummaries: false,
          hasError: true,
        ),
        isFalse,
      );
    });
  });
}
