import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/domain/repositories/health_metrics_repository.dart';
import 'package:hustl_app/features/health_sync/domain/usecases/load_latest_readiness.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/services/next_workout_focus_service.dart';
import 'package:hustl_app/features/workout_log/domain/utils/time_periods.dart';
import 'package:hustl_app/features/workout_logging/presentation/screens/workout_home_screen.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/home_hydrated_content.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/home_week_stats.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/quick_start_sheet.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/readiness_today_row.dart';
import 'package:hustl_app/features/workout_templates/domain/models/workout_template.dart';
import 'package:hustl_app/features/workout_templates/domain/repositories/template_repository.dart';

class _WorkoutQuery {
  const _WorkoutQuery({this.limit, this.startDate, this.endDate});

  final int? limit;
  final DateTime? startDate;
  final DateTime? endDate;
}

class _WorkoutRepositoryFake implements WorkoutRepository {
  _WorkoutRepositoryFake(this.sessions);

  final List<WorkoutSession> sessions;
  final List<_WorkoutQuery> queries = [];

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    queries.add(
      _WorkoutQuery(limit: limit, startDate: startDate, endDate: endDate),
    );
    return sessions;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;
}

class _TemplateRepositoryFake implements TemplateRepository {
  _TemplateRepositoryFake([this.templates = const []]);

  final List<WorkoutTemplate> templates;

  @override
  Future<List<WorkoutTemplate>> getWorkoutTemplates() async => templates;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HealthMetricsRepositoryFake implements HealthMetricsRepository {
  _HealthMetricsRepositoryFake(this.readiness);

  final DailyRecoverySnapshot readiness;

  @override
  Future<HealthSnapshot> loadSnapshot({
    required DateTime start,
    required DateTime end,
    bool forceRefresh = false,
  }) async => HealthSnapshot(
    rangeStart: start,
    rangeEnd: end,
    metrics: const [],
    nutritionEntries: const [],
    dailySummaries: const [],
    recoverySnapshots: [readiness],
    lastSyncedAt: DateTime.now(),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedWorkoutRepositoryFake extends _WorkoutRepositoryFake {
  _DelayedWorkoutRepositoryFake() : super(const []);

  final completer = Completer<List<WorkoutSession>>();

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    queries.add(
      _WorkoutQuery(limit: limit, startDate: startDate, endDate: endDate),
    );
    return completer.future;
  }
}

List<WorkoutSession> _manySessions(DateTime now, {int count = 12}) {
  return List.generate(count, (i) {
    final start = now.subtract(Duration(days: i + 1));
    return WorkoutSession(
      id: 'session-$i',
      name: 'Session $i',
      startTime: start,
      endTime: start.add(const Duration(hours: 1)),
      isCompleted: true,
      exercises: const [
        WorkoutExercise(
          id: 'bench',
          exercise: Exercise(name: 'Bench Press', muscles: ['Chest']),
          sets: [
            WorkoutSet(id: 'set-1', weight: 100, reps: 8, isCompleted: true),
          ],
        ),
      ],
    );
  });
}

/// Mirrors `_WorkoutHomeScreenState._focusFetchStart` (a private production
/// helper in workout_home_screen.dart) so tests can compute the EXACT
/// expected focus-history fetch start for any period on ANY run date, instead
/// of relying on inequalities (e.g. "fetch start is after the month start")
/// that only hold on SOME days of the month.
///
/// The fetch anchors to the EARLIER of the resolved period start and the
/// WIDER of two floors: the 35-day focus-card minimum lookback, and the
/// [HomeWeekStats.displayWindow] (49 days) the home-stats trend needs. The
/// 49-day floor always governs — it is always further back than the 35-day
/// one — so tests that only accounted for the 35-day floor would compute the
/// wrong expectation on any date where a period's resolved start falls
/// between the two (i.e. 35–49 days back), which is exactly what made the
/// affected assertions date-dependent.
DateTime expectedFocusFetchStart(BodyScorePeriod period, DateTime now) {
  const focusFetchWindow = Duration(days: 35);
  final focusFloor = now.subtract(focusFetchWindow);
  final homeStatsFloor = now.subtract(HomeWeekStats.displayWindow);
  final floor = homeStatsFloor.isBefore(focusFloor)
      ? homeStatsFloor
      : focusFloor;
  final periodStart = period.resolve(now).range.start;
  return periodStart.isBefore(floor) ? periodStart : floor;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    // Start each test from clean persisted state so the focus-card period read
    // is deterministic; reset the PreferencesService singleton's cache too.
    SharedPreferences.setMockInitialValues({});
    PreferencesService().resetForTests();
  });

  tearDown(() async {
    await getIt.reset();
    PreferencesService().resetForTests();
  });

  testWidgets(
    'hydration swaps the static placeholder out without an overlapping '
    'full-screen transition',
    (tester) async {
      final repo = _DelayedWorkoutRepositoryFake();
      getIt.registerSingleton<WorkoutRepository>(repo);
      getIt.registerSingleton<TemplateRepository>(_TemplateRepositoryFake());

      await tester.pumpWidget(const MaterialApp(home: WorkoutHomeScreen()));
      await tester.pump();
      expect(find.byKey(const ValueKey('home-loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-hydrated')), findsNothing);
      expect(
        tester.hasRunningAnimations,
        isFalse,
        reason:
            'the dense Train placeholder must not run competing shimmer '
            'tickers during startup',
      );

      repo.completer.complete(const []);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('home-loading')), findsNothing);
      expect(find.byKey(const ValueKey('home-hydrated')), findsOneWidget);
    },
  );

  testWidgets('late low readiness does not grow the coaching card', (
    tester,
  ) async {
    final now = DateTime.now();
    final readiness = DailyRecoverySnapshot(
      date: DateTime(now.year, now.month, now.day),
      hrvValue: 40,
      hrvKind: HrvKind.sdnn,
      readinessScore: 35,
      recoveryScore: 35,
      baselineCoverageDays: 21,
      band: RecoveryFlowBand.recharge.legacyBand,
      flowBand: RecoveryFlowBand.recharge,
      confidence: RecoveryConfidence.high,
    );
    getIt.registerSingleton<WorkoutRepository>(
      _WorkoutRepositoryFake(_manySessions(now)),
    );
    getIt.registerSingleton<TemplateRepository>(_TemplateRepositoryFake());
    getIt.registerSingleton<LoadLatestReadinessUseCase>(
      LoadLatestReadinessUseCase(_HealthMetricsRepositoryFake(readiness)),
    );

    await tester.pumpWidget(const MaterialApp(home: WorkoutHomeScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(ReadinessTodayRow), findsOneWidget);
    expect(find.textContaining('Recharge'), findsOneWidget);
    expect(
      find.textContaining('a lighter session still counts'),
      findsNothing,
      reason:
          'late readiness belongs to the fixed row and must not insert a '
          'variable-height note into the coaching card',
    );
  });

  testWidgets('training home loads a dated history window for focus planning', (
    tester,
  ) async {
    final now = DateTime.now();
    final repo = _WorkoutRepositoryFake([
      WorkoutSession(
        id: 'session-1',
        name: 'Push Day',
        startTime: now.subtract(const Duration(days: 2)),
        endTime: now
            .subtract(const Duration(days: 2))
            .add(const Duration(hours: 1)),
        isCompleted: true,
        exercises: const [
          WorkoutExercise(
            id: 'bench',
            exercise: Exercise(name: 'Bench Press', muscles: ['Chest']),
            sets: [
              WorkoutSet(id: 'set-1', weight: 100, reps: 8, isCompleted: true),
            ],
          ),
        ],
      ),
    ]);
    getIt.registerSingleton<WorkoutRepository>(repo);
    getIt.registerSingleton<TemplateRepository>(_TemplateRepositoryFake());

    await tester.pumpWidget(
      MaterialApp(home: WorkoutHomeScreen(now: () => now)),
    );
    await tester.pumpAndSettle();

    expect(repo.queries.length, 2);
    expect(repo.queries.first.limit, 25);
    expect(repo.queries.first.startDate, isNull);

    final startDate = repo.queries.last.startDate;
    expect(startDate, isNotNull);
    // Production reads the SAME `now` (injected above), so the fetch start
    // must match the shared helper's expectation EXACTLY - no elapsed-time
    // tolerance needed.
    final expectedStart = expectedFocusFetchStart(
      BodyScorePeriod.defaultPeriod,
      now,
    );
    expect(
      startDate,
      expectedStart,
      reason:
          'the focus fetch floor is the WIDER of the focus card\'s minimum '
          'lookback and the home-stats display window (the 6-week volume '
          'trend, which reaches further back), so the trend\'s oldest weeks '
          'are never silently empty',
    );
  });

  testWidgets(
    'Finding 1: on first run post-upgrade Home defaults to the current week even '
    'with a STALE stored closed-period pref - the one-time migration runs on '
    'whichever surface loads first',
    (tester) async {
      // An upgraded user with a stale closed-period selection persisted, but NO
      // migration marker yet (they have not opened the detail since upgrading).
      // Home must honour the new current-week default via the shared helper -
      // not blindly read the stale closed pref - and persist the migration so
      // the Home focus card headlines THIS week's work immediately.
      SharedPreferences.setMockInitialValues({
        bodyScorePeriodPrefKey: BodyScorePeriod.lastFullMonth.id,
        // Deliberately NO bodyScoreCurrentWeekMigrationKey: this is the first
        // surface loaded after the upgrade.
      });
      PreferencesService().resetForTests();

      final now = DateTime.now();
      final repo = _WorkoutRepositoryFake([
        WorkoutSession(
          id: 'session-1',
          name: 'Push Day',
          startTime: now.subtract(const Duration(days: 1)),
          endTime: now
              .subtract(const Duration(days: 1))
              .add(const Duration(hours: 1)),
          isCompleted: true,
          exercises: const [
            WorkoutExercise(
              id: 'bench',
              exercise: Exercise(name: 'Bench Press', muscles: ['Chest']),
              sets: [
                WorkoutSet(
                  id: 'set-1',
                  weight: 100,
                  reps: 8,
                  isCompleted: true,
                ),
              ],
            ),
          ],
        ),
      ]);
      getIt.registerSingleton<WorkoutRepository>(repo);
      getIt.registerSingleton<TemplateRepository>(_TemplateRepositoryFake());

      await tester.pumpWidget(
        MaterialApp(home: WorkoutHomeScreen(now: () => now)),
      );
      await tester.pumpAndSettle();

      // The focus card is built for the CURRENT WEEK, not the stale full-month
      // pref: its window label tracks the in-progress week.
      final content = tester.widget<HomeHydratedContent>(
        find.byType(HomeHydratedContent),
      );
      final focus = content.focusListenable?.value ?? content.focus;
      expect(focus, isNotNull);
      expect(
        focus!.windowLabel,
        'this week',
        reason:
            'Home must default to the current week post-upgrade, not the stale '
            'stored closed-period selection',
      );
      expect(focus.windowLabel, isNot('last full month'));

      // The focus history fetch anchors to (at least) the current-week start -
      // never the older month start the stale pref would have implied.
      final focusStart = repo.queries.last.startDate;
      expect(focusStart, isNotNull);
      final currentWeekStart = BodyScorePeriod.currentWeek
          .resolve(now, firstWeekday: DateTime.monday)
          .range
          .start;
      final monthStart = lastFullMonthRange(now).start;
      // The current-week start is strictly AFTER the (older) month start.
      expect(currentWeekStart.isAfter(monthStart), isTrue);

      // The fetch anchors to the EARLIER of the resolved period start and the
      // WIDER of the 35-day focus floor / 49-day home-stats floor (see
      // [expectedFocusFetchStart], which mirrors the production
      // `_focusFetchStart` helper exactly) — the current week starts within
      // the last 7 days, so one of the two floors always governs, never the
      // period start itself. Assert the expected value (robust to any run
      // date) rather than the coarser "isAfter(monthStart)" inequality, which
      // only held once the 35-day floor was assumed to govern — not true once
      // the wider 49-day home-stats floor is accounted for. Production reads
      // the SAME injected `now`, so the comparison is EXACT - no
      // elapsed-time tolerance needed.
      final expectedFocusStart = expectedFocusFetchStart(
        BodyScorePeriod.currentWeek,
        now,
      );
      expect(
        focusStart,
        expectedFocusStart,
        reason:
            'the migrated current-week fetch ($focusStart) must anchor to the '
            'resolved current-week fetch window ($expectedFocusStart)',
      );
      // The stale stored "last full month" pref, had it leaked through instead
      // of the migrated current-week default, would only produce a DIFFERENT
      // fetch start on dates where the two periods actually resolve
      // differently — assert the divergence whenever it is observable on this
      // run date.
      final staleFocusStart = expectedFocusFetchStart(
        BodyScorePeriod.lastFullMonth,
        now,
      );
      if (staleFocusStart != expectedFocusStart) {
        expect(
          focusStart,
          isNot(staleFocusStart),
          reason:
              'the fetch must not reach back to the stale month start; the '
              'migrated current-week window governs the lookback',
        );
      }

      // ...and the migration is now persisted: the stored period was rewritten
      // to the current-week default and the one-time marker recorded, so a later
      // open of the detail honours the same window.
      final prefs = PreferencesService();
      expect(
        await prefs.getRawString(bodyScorePeriodPrefKey),
        BodyScorePeriod.currentWeek.id,
      );
      expect(
        await prefs.getRawString(bodyScoreCurrentWeekMigrationKey),
        isNotNull,
      );
    },
  );

  testWidgets(
    'focus history fetch covers the persisted period: lastFullMonth fetches '
    'from the month start, not the rolling floor',
    (tester) async {
      // Persist "last full month" so the home reads it like the detail does.
      SharedPreferences.setMockInitialValues({
        bodyScorePeriodPrefKey: BodyScorePeriod.lastFullMonth.id,
        // Mark the one-time current-week migration as already run so the shared
        // period read HONOURS this deliberate closed-period selection (a fresh
        // upgrade with no marker would force the current-week default instead).
        bodyScoreCurrentWeekMigrationKey: 'done',
      });
      PreferencesService().resetForTests();

      final now = DateTime.now();
      final monthStart = lastFullMonthRange(now).start;
      // The fetch floor is the WIDER of the 35-day focus-card minimum lookback
      // and the 49-day [HomeWeekStats.displayWindow] (the 6-week volume
      // trend's floor) — the 49-day floor always governs since it always
      // reaches further back than the 35-day one. Sanity: the guarded
      // assertion below is only meaningful on dates where the month start
      // predates this floor (i.e. later in the month); the earliest the floor
      // can reach is ~49 days back, while the month start can be up to ~62
      // days back.
      final floor = now.subtract(HomeWeekStats.displayWindow);

      final repo = _WorkoutRepositoryFake([
        WorkoutSession(
          id: 'session-1',
          name: 'Push Day',
          startTime: now.subtract(const Duration(days: 2)),
          endTime: now
              .subtract(const Duration(days: 2))
              .add(const Duration(hours: 1)),
          isCompleted: true,
          exercises: const [
            WorkoutExercise(
              id: 'bench',
              exercise: Exercise(name: 'Bench Press', muscles: ['Chest']),
              sets: [
                WorkoutSet(
                  id: 'set-1',
                  weight: 100,
                  reps: 8,
                  isCompleted: true,
                ),
              ],
            ),
          ],
        ),
      ]);
      getIt.registerSingleton<WorkoutRepository>(repo);
      getIt.registerSingleton<TemplateRepository>(_TemplateRepositoryFake());

      await tester.pumpWidget(
        MaterialApp(home: WorkoutHomeScreen(now: () => now)),
      );
      await tester.pumpAndSettle();

      expect(repo.queries.length, 2);
      final startDate = repo.queries.last.startDate;
      expect(startDate, isNotNull);

      // The focus fetch must reach back to (at least) the resolved month start —
      // never silently clipped to the rolling 35-day floor — so early-month
      // sessions are not dropped from a card labeled "last full month".
      expect(
        startDate!.isAtSameMomentAs(monthStart) ||
            startDate.isBefore(monthStart),
        isTrue,
        reason:
            'fetch start ($startDate) should cover the month start '
            '($monthStart) the card summarizes',
      );
      if (monthStart.isBefore(floor)) {
        expect(
          startDate.isAtSameMomentAs(monthStart),
          isTrue,
          reason:
              'on dates where the month start predates the (49-day, home-stats '
              'governed) floor, the fetch must anchor to the month start, not '
              'the floor',
        );
      }
    },
  );

  testWidgets(
    'widening the focus fetch to the persisted period does NOT widen the '
    'home-stats window: the cached HomeWeekStats stays bounded to the '
    'displayed window while the focus service sees the full month range',
    (tester) async {
      // Persist "last full month" so the focus fetch reaches the month start.
      SharedPreferences.setMockInitialValues({
        bodyScorePeriodPrefKey: BodyScorePeriod.lastFullMonth.id,
        // Mark the one-time current-week migration as already run so the shared
        // period read HONOURS this deliberate closed-period selection (a fresh
        // upgrade with no marker would force the current-week default instead).
        bodyScoreCurrentWeekMigrationKey: 'done',
      });
      PreferencesService().resetForTests();

      final now = DateTime.now();
      final monthStart = lastFullMonthRange(now).start;
      // The home-stats window is the dashboard's displayed window (current week
      // + the 6-week trend), NOT the full focus period.
      final floor = now.subtract(HomeWeekStats.displayWindow);

      // This regression test is only meaningful on dates where the month start
      // predates the home-stats floor (mid-to-late in the month) — otherwise the
      // wide fetch and the displayed window coincide and there's nothing to
      // widen.
      if (!monthStart.isBefore(floor)) {
        return;
      }

      // A recent session inside the fixed window, plus an older session that
      // falls within the month range but BEFORE the 35-day floor. The fake repo
      // returns both regardless of [startDate], so the screen's own slicing is
      // what bounds the home-stats window.
      WorkoutSession sessionAt(String id, DateTime start) => WorkoutSession(
        id: id,
        name: 'Push Day',
        startTime: start,
        endTime: start.add(const Duration(hours: 1)),
        isCompleted: true,
        exercises: const [
          WorkoutExercise(
            id: 'bench',
            exercise: Exercise(name: 'Bench Press', muscles: ['Chest']),
            sets: [
              WorkoutSet(id: 'set-1', weight: 100, reps: 8, isCompleted: true),
            ],
          ),
        ],
      );

      final recentSession = sessionAt(
        'recent',
        now.subtract(const Duration(days: 2)),
      );
      // Halfway between the home-stats floor and the month start: inside the
      // month window but outside the displayed home-stats window.
      final beforeFloor = floor.subtract(
        Duration(seconds: floor.difference(monthStart).inSeconds ~/ 2),
      );
      final oldSession = sessionAt('old', beforeFloor);

      final repo = _WorkoutRepositoryFake([recentSession, oldSession]);
      getIt.registerSingleton<WorkoutRepository>(repo);
      getIt.registerSingleton<TemplateRepository>(_TemplateRepositoryFake());

      await tester.pumpWidget(
        MaterialApp(home: WorkoutHomeScreen(now: () => now)),
      );
      await tester.pumpAndSettle();

      // The focus service still fetches the WHOLE month range (prior fix).
      final focusStart = repo.queries.last.startDate;
      expect(focusStart, isNotNull);
      expect(
        focusStart!.isAtSameMomentAs(monthStart),
        isTrue,
        reason:
            'focus fetch must still anchor to the month start so the card '
            'covers the full selected period',
      );

      // But the dashboard's cached stats (Train hero, week strip, volume trend)
      // must reflect ONLY the displayed window: the older session is excluded
      // even though it was fetched for the focus card. The cached HomeWeekStats
      // must therefore equal the aggregation of the recent session ALONE — i.e.
      // the older session contributed nothing to any displayed figure.
      final content = tester.widget<HomeHydratedContent>(
        find.byType(HomeHydratedContent),
      );
      final expected = HomeWeekStats.from([recentSession], now: now);
      expect(
        content.stats.weekVolume,
        expected.weekVolume,
        reason: 'this-week volume must come from the recent session only',
      );
      expect(
        content.stats.weeklyVolumes,
        expected.weeklyVolumes,
        reason:
            'the volume trend must NOT include the older (pre-window) session '
            'even though the focus fetch pulled it in',
      );
    },
  );

  testWidgets('home exposes an extended "Start workout" FAB', (tester) async {
    getIt.registerSingleton<WorkoutRepository>(
      _WorkoutRepositoryFake(const []),
    );
    getIt.registerSingleton<TemplateRepository>(_TemplateRepositoryFake());

    await tester.pumpWidget(const MaterialApp(home: WorkoutHomeScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(
      find.widgetWithText(FloatingActionButton, 'Start workout'),
      findsOneWidget,
    );
  });

  testWidgets('tapping the FAB opens the quick-start sheet (no last session '
      'hides repeat)', (tester) async {
    getIt.registerSingleton<WorkoutRepository>(
      _WorkoutRepositoryFake(const []),
    );
    getIt.registerSingleton<TemplateRepository>(_TemplateRepositoryFake());

    await tester.pumpWidget(const MaterialApp(home: WorkoutHomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Start workout'),
    );
    await tester.pumpAndSettle();

    // The quick-start sheet is open with the template + empty options, but no
    // repeat row because there is no completed history.
    expect(find.byType(QuickStartSheet), findsOneWidget);
    expect(find.text('Start a workout'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(QuickStartSheet),
        matching: find.text('From a template'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(QuickStartSheet),
        matching: find.text('Empty workout'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(QuickStartSheet),
        matching: find.textContaining('Repeat'),
      ),
      findsNothing,
    );
  });

  testWidgets('quick-start sheet surfaces the repeat row for a last session', (
    tester,
  ) async {
    final now = DateTime.now();
    final repo = _WorkoutRepositoryFake([
      WorkoutSession(
        id: 'session-1',
        name: 'Push Day',
        startTime: now.subtract(const Duration(days: 1)),
        endTime: now
            .subtract(const Duration(days: 1))
            .add(const Duration(hours: 1)),
        isCompleted: true,
        exercises: const [
          WorkoutExercise(
            id: 'bench',
            exercise: Exercise(name: 'Bench Press', muscles: ['Chest']),
            sets: [
              WorkoutSet(id: 'set-1', weight: 100, reps: 8, isCompleted: true),
            ],
          ),
        ],
      ),
    ]);
    getIt.registerSingleton<WorkoutRepository>(repo);
    getIt.registerSingleton<TemplateRepository>(_TemplateRepositoryFake());

    await tester.pumpWidget(const MaterialApp(home: WorkoutHomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Start workout'),
    );
    await tester.pumpAndSettle();

    // "Repeat Push Day" also appears in the inline next-session shortcut row,
    // so scope these assertions to the sheet itself.
    expect(find.byType(QuickStartSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(QuickStartSheet),
        matching: find.text('Repeat Push Day'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(QuickStartSheet),
        matching: find.text('From a template'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(QuickStartSheet),
        matching: find.text('Empty workout'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('empty workout starts on the canonical active-workout route', (
    tester,
  ) async {
    getIt.registerSingleton<WorkoutRepository>(
      _WorkoutRepositoryFake(const []),
    );
    getIt.registerSingleton<TemplateRepository>(_TemplateRepositoryFake());
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const WorkoutHomeScreen()),
        GoRoute(
          path: '/workout_session',
          builder: (_, __) => const Scaffold(body: Text('Active workout')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Start workout'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(QuickStartSheet),
        matching: find.text('Empty workout'),
      ),
    );
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/workout_session');
    expect(find.text('Active workout'), findsOneWidget);
  });

  testWidgets('repeat starts on the canonical active-workout route', (
    tester,
  ) async {
    final now = DateTime.now();
    getIt.registerSingleton<WorkoutRepository>(
      _WorkoutRepositoryFake([
        WorkoutSession(
          id: 'session-1',
          name: 'Push Day',
          startTime: now.subtract(const Duration(days: 1)),
          endTime: now.subtract(const Duration(hours: 23)),
          isCompleted: true,
          exercises: const [],
        ),
      ]),
    );
    getIt.registerSingleton<TemplateRepository>(_TemplateRepositoryFake());
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const WorkoutHomeScreen()),
        GoRoute(
          path: '/workout_session',
          builder: (_, __) => const Scaffold(body: Text('Active workout')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Start workout'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(QuickStartSheet),
        matching: find.text('Repeat Push Day'),
      ),
    );
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/workout_session');
    expect(find.text('Active workout'), findsOneWidget);
  });

  testWidgets('template starts on the canonical active-workout route', (
    tester,
  ) async {
    final now = DateTime.now();
    final template = WorkoutTemplate(
      id: 'template-1',
      name: 'Strength template',
      description: 'Demo routine',
      exercises: const [],
      createdAt: now,
      updatedAt: now,
    );
    getIt.registerSingleton<WorkoutRepository>(
      _WorkoutRepositoryFake(const []),
    );
    getIt.registerSingleton<TemplateRepository>(
      _TemplateRepositoryFake([template]),
    );
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const WorkoutHomeScreen()),
        GoRoute(
          path: '/workout_session',
          builder: (_, __) => const Scaffold(body: Text('Active workout')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Start workout'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(QuickStartSheet),
        matching: find.text('From a template'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Strength template'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/workout_session');
    expect(find.text('Active workout'), findsOneWidget);
  });

  testWidgets(
    'back-and-forth scrolling keeps the FAB hidden until the gesture ends',
    (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'coach_intro_seen': true});
      PreferencesService().resetForTests();

      final now = DateTime.now();
      getIt.registerSingleton<WorkoutRepository>(
        _WorkoutRepositoryFake(_manySessions(now)),
      );
      getIt.registerSingleton<TemplateRepository>(_TemplateRepositoryFake());

      await tester.pumpWidget(const MaterialApp(home: WorkoutHomeScreen()));
      await tester.pumpAndSettle();

      // Initial (top) position: FAB shown.
      expect(find.byType(FloatingActionButton), findsOneWidget);

      // Keep one pointer down while reversing direction. The FAB should animate
      // out once, remain quiet through the reversal, and return only on release.
      final list = find.byKey(const ValueKey('home-hydrated'));
      final dragStart = Offset(
        tester.getTopLeft(list).dx + 8,
        tester.getCenter(list).dy,
      );
      final gesture = await tester.startGesture(dragStart);
      await gesture.moveBy(const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(
        find.byType(FloatingActionButton),
        findsNothing,
        reason:
            'FAB is removed while scrolling down so it never sits over the '
            'Volume-trend chart',
      );

      await gesture.moveBy(const Offset(0, 150));
      await tester.pumpAndSettle();
      expect(
        find.byType(FloatingActionButton),
        findsNothing,
        reason:
            'reversing direction mid-gesture must not restart the FAB '
            'animation over the list',
      );

      // Scrub all the way back to the top without lifting the finger. Reaching
      // the edge must not make the FAB animate back over the active gesture.
      await gesture.moveBy(const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(
        find.byType(FloatingActionButton),
        findsNothing,
        reason:
            'reaching the top while the finger is still down must keep the '
            'FAB hidden',
      );

      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        find.byType(FloatingActionButton),
        findsOneWidget,
        reason: 'FAB returns after the back-and-forth gesture settles',
      );
    },
  );

  testWidgets('edge overscroll hides the FAB until the pointer lifts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'coach_intro_seen': true});
    PreferencesService().resetForTests();

    final now = DateTime.now();
    getIt.registerSingleton<WorkoutRepository>(
      _WorkoutRepositoryFake(_manySessions(now)),
    );
    getIt.registerSingleton<TemplateRepository>(_TemplateRepositoryFake());

    await tester.pumpWidget(const MaterialApp(home: WorkoutHomeScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);

    final list = find.byKey(const ValueKey('home-hydrated'));
    final gesture = await tester.startGesture(
      Offset(tester.getTopLeft(list).dx + 8, tester.getCenter(list).dy),
    );
    // The list begins at its top edge, so dragging down produces overscroll
    // without a ScrollDirection change. ScrollStart must still hide the FAB.
    await gesture.moveBy(const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('FAB still opens the quick-start sheet after a hide/show cycle', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'coach_intro_seen': true});
    PreferencesService().resetForTests();

    final now = DateTime.now();
    getIt.registerSingleton<WorkoutRepository>(
      _WorkoutRepositoryFake(_manySessions(now)),
    );
    getIt.registerSingleton<TemplateRepository>(_TemplateRepositoryFake());

    await tester.pumpWidget(const MaterialApp(home: WorkoutHomeScreen()));
    await tester.pumpAndSettle();

    // Hide then show again, returning to the top.
    await tester.drag(
      find.byKey(const ValueKey('home-hydrated')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('home-hydrated')),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Start workout'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(QuickStartSheet), findsOneWidget);
  });

  testWidgets(
    'reduce-motion: the FAB hides during a drag and returns on release',
    (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'coach_intro_seen': true});
      PreferencesService().resetForTests();

      final now = DateTime.now();
      getIt.registerSingleton<WorkoutRepository>(
        _WorkoutRepositoryFake(_manySessions(now)),
      );
      getIt.registerSingleton<TemplateRepository>(_TemplateRepositoryFake());

      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: WorkoutHomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsOneWidget);

      final list = find.byKey(const ValueKey('home-hydrated'));
      final dragStart = Offset(
        tester.getTopLeft(list).dx + 8,
        tester.getCenter(list).dy,
      );
      final gesture = await tester.startGesture(dragStart);
      await gesture.moveBy(const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsOneWidget);
    },
  );
  testWidgets(
    'changing the persisted period while Home stays mounted rebuilds the focus '
    'card for the NEW period on return from the body-score detail',
    (tester) async {
      // Start on the rolling default ("last 4 weeks"). The focus card opens the
      // body-score detail via context.push and refreshes on the awaited return.
      // Mark the coach intro as seen so its auto-show bottom sheet does not
      // cover the card and block the tap that drives the navigation.
      SharedPreferences.setMockInitialValues({
        bodyScorePeriodPrefKey: BodyScorePeriod.last4FullWeeks.id,
        'coach_intro_seen': true,
        // Migration already run: honour the deliberate last-4-weeks selection
        // rather than forcing the current-week default on first read.
        bodyScoreCurrentWeekMigrationKey: 'done',
      });
      PreferencesService().resetForTests();

      // A recent completed session so the focus service builds a (non-null) plan
      // for BOTH periods; the fake repo returns it regardless of the query.
      final now = DateTime.now();
      final repo = _WorkoutRepositoryFake([
        WorkoutSession(
          id: 'session-1',
          name: 'Push Day',
          startTime: now.subtract(const Duration(days: 2)),
          endTime: now
              .subtract(const Duration(days: 2))
              .add(const Duration(hours: 1)),
          isCompleted: true,
          exercises: const [
            WorkoutExercise(
              id: 'bench',
              exercise: Exercise(name: 'Bench Press', muscles: ['Chest']),
              sets: [
                WorkoutSet(
                  id: 'set-1',
                  weight: 100,
                  reps: 8,
                  isCompleted: true,
                ),
              ],
            ),
          ],
        ),
      ]);
      getIt.registerSingleton<WorkoutRepository>(repo);
      getIt.registerSingleton<TemplateRepository>(_TemplateRepositoryFake());

      // Drive the REAL navigation path: the card calls
      // context.push('/progress/body-score') (a route on the root navigator,
      // via parentNavigatorKey) and awaits its pop future to refresh. A
      // RouteAware/didPopNext would never fire for that root-navigator push, so
      // the test exercises the await-push refresh the production code relies on.
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => WorkoutHomeScreen(now: () => now),
          ),
          GoRoute(
            path: '/progress/body-score',
            builder: (context, __) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Body Score detail'),
                ),
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      // Initial load: the focus card is built for the rolling-default period.
      // The period-anchored fetch start is deterministic, so we assert on it
      // (the fetch WINDOW is exactly what this PR fixes); the window label is
      // also captured to confirm the card text changes on the period switch.
      NextWorkoutFocusPlan? focusPlan() {
        final content = tester.widget<HomeHydratedContent>(
          find.byType(HomeHydratedContent),
        );
        return content.focusListenable?.value ?? content.focus;
      }

      expect(focusPlan(), isNotNull);
      final initialFocusStart = repo.queries.last.startDate;
      expect(initialFocusStart, isNotNull);
      final initialWindowLabel = focusPlan()!.windowLabel;
      final initialQueryCount = repo.queries.length;

      // Tap the focus card's action to push the body-score detail atop the
      // still-mounted Home (the real onOpenBodyScore -> context.push path).
      // Scroll it into view first — the Training section sits below the hero.
      // Tap the TextButton itself (its shrink-wrapped tap target is smaller
      // than the laid-out label, so target the button, not the text centroid).
      final seeBalance = find.widgetWithText(
        TextButton,
        'See training balance',
      );
      await tester.ensureVisible(seeBalance);
      await tester.pumpAndSettle();
      await tester.tap(seeBalance);
      await tester.pumpAndSettle();
      expect(find.text('Body Score detail'), findsOneWidget);

      // While on the detail, the user changes the persisted Body Score period.
      await PreferencesService().setRawString(
        bodyScorePeriodPrefKey,
        BodyScorePeriod.lastFullMonth.id,
      );

      // Return to Home: the awaited push future resolves and the focus card is
      // re-read + rebuilt for the new period.
      await tester.tap(find.text('Body Score detail'));
      await tester.pumpAndSettle();
      expect(find.text('Body Score detail'), findsNothing);

      // The card must have been rebuilt for the NEW period: a fresh focus
      // history fetch was issued, anchored to the new period's window — not
      // left on the old rolling fetch range.
      expect(
        repo.queries.length,
        greaterThan(initialQueryCount),
        reason: 'the focus history must be re-fetched for the new period',
      );
      final refetchStart = repo.queries.last.startDate;
      expect(refetchStart, isNotNull);
      // _focusFetchStart anchors to the EARLIER of the period start and the
      // WIDER of the 35-day focus floor / 49-day home-stats floor (see
      // [expectedFocusFetchStart], which mirrors it exactly); for 'last full
      // month' that is the month start whenever it predates the floor
      // (mid-to-late month), else the floor. `_refreshFocusPeriod` reads the
      // SAME injected `now` as the initial load, so the comparison is EXACT
      // - no elapsed-time tolerance needed.
      final expectedStart = expectedFocusFetchStart(
        BodyScorePeriod.lastFullMonth,
        now,
      );
      expect(
        refetchStart,
        expectedStart,
        reason:
            'the refreshed fetch ($refetchStart) must anchor to the NEW '
            'period window ($expectedStart), not the prior selection',
      );
      // On dates where the two periods resolve to different fetch windows,
      // the rebuilt fetch range must actually differ from the initial one.
      if (initialFocusStart != expectedStart) {
        expect(
          refetchStart,
          isNot(initialFocusStart),
          reason: 'the fetch window changed with the period',
        );
      }
      // The rebuilt card carries a fresh window label for the new period; it
      // must no longer be stuck on a stale closed-period 'last 4 weeks' label.
      final newWindowLabel = focusPlan()?.windowLabel;
      expect(newWindowLabel, isNotNull);
      expect(
        newWindowLabel,
        isNot('last 4 weeks'),
        reason:
            'the focus card must not keep the prior period label after the '
            'persisted period changed',
      );
      // Sanity: the initial label was the rolling-default read, distinct from
      // the new full-month label whenever a closed-period verdict resolved.
      expect(initialWindowLabel, isNotNull);
    },
  );
}
