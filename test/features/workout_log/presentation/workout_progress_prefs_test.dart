import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/widgets/hustl_menu_button.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/domain/usecases/load_recovery_trend.dart';
import 'package:hustl_app/features/workout_log/data/datasources/body_score_api.dart';
import 'package:hustl_app/features/workout_log/domain/services/body_score_service.dart';
import 'package:hustl_app/features/workout_log/domain/utils/time_periods.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/body_score_screen.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/workout_progress_screen.dart';
import 'package:hustl_app/features/workout_log/presentation/screens/workout_progress_utils.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/body_score_radar.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/body_score_summary_card.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/progress_charts.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/segmented_pill_selector.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/recovery_trend_card.dart';

class _BodyScoreApiStub implements BodyScoreApi {
  const _BodyScoreApiStub();

  @override
  Future<BodyScoreSummary?> fetchLatest({int windowDays = 28}) async => null;
}

/// Stubs the recovery-trend read with a fixed result so the Progress screen can
/// mount (or omit) the RecoveryTrendCard without a live health pipeline.
class _StubRecoveryTrend implements LoadRecoveryTrendUseCase {
  _StubRecoveryTrend(this._result);

  final List<DailyRecoverySnapshot> _result;

  @override
  Future<List<DailyRecoverySnapshot>> call() async => _result;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DailyRecoverySnapshot _recoveryDay(DateTime date) => DailyRecoverySnapshot(
  date: DateTime(date.year, date.month, date.day),
  sleepPerformanceScore: 80,
  hrvValue: 55,
  hrvKind: HrvKind.sdnn,
  restingHeartRateBpm: 54,
  readinessScore: 70,
  recoveryScore: 68,
  baselineCoverageDays: 21,
  flowBand: RecoveryFlowBand.ready,
);

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
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;
}

Future<void> _pumpProgressScreen(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: WorkoutProgressScreen()));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final getIt = GetIt.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    if (getIt.isRegistered<WorkoutRepository>()) {
      getIt.unregister<WorkoutRepository>();
    }
    if (getIt.isRegistered<PreferencesService>()) {
      getIt.unregister<PreferencesService>();
    }
    if (getIt.isRegistered<BodyScoreApi>()) {
      getIt.unregister<BodyScoreApi>();
    }
    if (getIt.isRegistered<LoadRecoveryTrendUseCase>()) {
      getIt.unregister<LoadRecoveryTrendUseCase>();
    }
    getIt.registerSingleton<PreferencesService>(PreferencesService());
    getIt.registerSingleton<BodyScoreApi>(const _BodyScoreApiStub());
  });

  tearDown(() {
    if (getIt.isRegistered<WorkoutRepository>()) {
      getIt.unregister<WorkoutRepository>();
    }
    if (getIt.isRegistered<PreferencesService>()) {
      getIt.unregister<PreferencesService>();
    }
    if (getIt.isRegistered<BodyScoreApi>()) {
      getIt.unregister<BodyScoreApi>();
    }
    if (getIt.isRegistered<LoadRecoveryTrendUseCase>()) {
      getIt.unregister<LoadRecoveryTrendUseCase>();
    }
  });

  WorkoutSession makeSession(DateTime t, double w) => WorkoutSession(
    id: 'id${t.millisecondsSinceEpoch}',
    name: 'S',
    startTime: t,
    exercises: [
      WorkoutExercise(
        id: 'e',
        exercise: const Exercise(name: 'Bench', muscles: ['Chest']),
        sets: [WorkoutSet(id: 's', weight: w, reps: 5, isCompleted: true)],
      ),
    ],
    isCompleted: true,
  );

  WorkoutSession makeEmptySession(DateTime t) => WorkoutSession(
    id: 'empty${t.millisecondsSinceEpoch}',
    name: 'Empty',
    startTime: t,
    endTime: t.add(const Duration(hours: 1)),
    exercises: const [],
    isCompleted: true,
  );

  WorkoutSession makeRegionSession({
    required DateTime start,
    required String region,
    double weight = 100,
  }) => WorkoutSession(
    id: 'session-${start.millisecondsSinceEpoch}-$region',
    name: '$region session',
    startTime: start,
    endTime: start.add(const Duration(hours: 1)),
    isCompleted: true,
    exercises: [
      WorkoutExercise(
        id: 'exercise-$region',
        exercise: Exercise(name: '$region move', muscles: [region]),
        sets: [
          WorkoutSet(
            id: 'set-$region',
            weight: weight,
            reps: 8,
            isCompleted: true,
          ),
        ],
      ),
    ],
  );

  testWidgets('progress screen loads global group preference', (tester) async {
    final now = DateTime.now();
    final sessions = [
      makeSession(now.subtract(const Duration(days: 1)), 100),
      makeSession(now.subtract(const Duration(days: 8)), 100),
    ];
    getIt.registerSingleton<WorkoutRepository>(_Repo(sessions));

    // Persist group = month and quick range = last 1 month
    final prefs = getIt<PreferencesService>();
    await prefs.setRecordTimeGroupIndex(TimeGroup.month.index);
    await prefs.setRecordQuickRangeIndex(QuickDateRange.last1Month.index);

    await _pumpProgressScreen(tester);
    final segFinder = find.byKey(const ValueKey('progress_time_group_toggle'));
    await tester.dragUntilVisible(
      segFinder,
      find.byType(ListView),
      const Offset(0, -300),
      maxIteration: 12,
    );
    expect(segFinder, findsOneWidget);
    final seg = tester.widget<SegmentedPillSelector<TimeGroup>>(segFinder);
    expect(seg.selected, TimeGroup.month);
  });

  testWidgets('progress screen shows weekly consistency card', (tester) async {
    final now = DateTime.now();
    final sessions = [
      makeSession(now.subtract(const Duration(days: 1)), 90),
      makeSession(now.subtract(const Duration(days: 8)), 95),
    ];
    getIt.registerSingleton<WorkoutRepository>(_Repo(sessions));

    await _pumpProgressScreen(tester);

    // Wave I: shared SectionHeader renders sentence-case titles.
    expect(find.text('Weekly consistency'), findsOneWidget);
    // Hero ring caption names the goal window: "of 12 weeks".
    expect(find.textContaining('of 12 weeks'), findsWidgets);
    expect(find.text('Goal: 3/wk'), findsOneWidget);
  });

  testWidgets(
    'progress mounts the recovery trend card when the read returns data',
    (tester) async {
      final now = DateTime.now();
      final sessions = [
        makeSession(now.subtract(const Duration(days: 1)), 100),
      ];
      getIt.registerSingleton<WorkoutRepository>(_Repo(sessions));
      getIt.registerSingleton<LoadRecoveryTrendUseCase>(
        _StubRecoveryTrend([
          _recoveryDay(now.subtract(const Duration(days: 3))),
          _recoveryDay(now.subtract(const Duration(days: 2))),
          _recoveryDay(now.subtract(const Duration(days: 1))),
        ]),
      );

      await _pumpProgressScreen(tester);
      await tester.dragUntilVisible(
        find.byType(RecoveryTrendCard),
        find.byType(ListView),
        const Offset(0, -300),
        maxIteration: 12,
      );

      expect(find.byType(RecoveryTrendCard), findsOneWidget);
      expect(find.text('Recovery trend'), findsOneWidget);
    },
  );

  testWidgets(
    'progress omits the recovery trend card when the read is unregistered',
    (tester) async {
      final now = DateTime.now();
      final sessions = [
        makeSession(now.subtract(const Duration(days: 1)), 100),
      ];
      getIt.registerSingleton<WorkoutRepository>(_Repo(sessions));
      // LoadRecoveryTrendUseCase intentionally NOT registered — the screen must
      // build with no card and no exception (pixel-identical to today).

      await _pumpProgressScreen(tester);

      expect(find.byType(RecoveryTrendCard), findsNothing);
      expect(find.text('Weekly consistency'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('progress hero shows the goal-oriented metric', (tester) async {
    final now = DateTime.now();
    final sessions = [
      makeSession(now.subtract(const Duration(days: 1)), 100),
      makeSession(now.subtract(const Duration(days: 8)), 90),
    ];
    getIt.registerSingleton<WorkoutRepository>(_Repo(sessions));

    await _pumpProgressScreen(tester);

    // Wave I hero: blue goal ring labelled "Weekly goal hit" with the
    // goal-hit count BIG inside, captioned "of 12 weeks".
    expect(find.text('Weekly goal hit'), findsOneWidget);
    expect(find.textContaining('of 12 weeks'), findsWidgets);
  });

  testWidgets('progress drops the Health clutter for a Training balance card', (
    tester,
  ) async {
    final now = DateTime.now();
    final sessions = [makeSession(now.subtract(const Duration(days: 1)), 100)];
    getIt.registerSingleton<WorkoutRepository>(_Repo(sessions));

    await _pumpProgressScreen(tester);

    // The 'More' / Health entry was pure nav clutter on a stats screen — gone.
    expect(find.text('Health'), findsNothing);
    expect(find.text('Recovery, sleep and daily readiness'), findsNothing);
    // The Training-balance card now surfaces the muscle data (previously hidden
    // on /progress/body-score, which Progress had no link to).
    expect(find.text('Training balance'), findsOneWidget);
  });

  testWidgets('progress screen does not show body score teaser text', (
    tester,
  ) async {
    final now = DateTime.now();
    final sessions = [
      makeSession(now.subtract(const Duration(days: 1)), 100),
      makeSession(now.subtract(const Duration(days: 8)), 90),
    ];
    getIt.registerSingleton<WorkoutRepository>(_Repo(sessions));

    await _pumpProgressScreen(tester);

    expect(find.text('Body score'), findsNothing);
    expect(find.text('Open Menu > Body Score for details'), findsNothing);
  });

  testWidgets('progress content still renders with empty completed sessions', (
    tester,
  ) async {
    final now = DateTime.now();
    getIt.registerSingleton<WorkoutRepository>(
      _Repo([makeEmptySession(now.subtract(const Duration(days: 2)))]),
    );

    await _pumpProgressScreen(tester);

    expect(find.text('Weekly consistency'), findsOneWidget);
    expect(find.text('Your progress starts here'), findsNothing);
  });

  testWidgets('date filter remains visible when no sessions in range', (
    tester,
  ) async {
    final now = DateTime.now();
    final sessions = [makeSession(now.subtract(const Duration(days: 30)), 100)];
    getIt.registerSingleton<WorkoutRepository>(_Repo(sessions));

    final prefs = getIt<PreferencesService>();
    await prefs.setRecordQuickRangeIndex(QuickDateRange.last2Weeks.index);

    await _pumpProgressScreen(tester);

    expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
    expect(find.text('No workouts in this period'), findsOneWidget);
  });

  testWidgets('simple horizontal bars render labels and values', (
    tester,
  ) async {
    const data = {'Upper': 100.0, 'Lower': 50.0};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SimpleHorizontalBars(
            data: data,
            formatValue: (value) => value.toStringAsFixed(0),
          ),
        ),
      ),
    );

    expect(find.text('Upper'), findsOneWidget);
    expect(find.text('Lower'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
  });

  testWidgets('time series charts render points and date labels', (
    tester,
  ) async {
    const weeklyData = {'2023-W52': 100.0, '2024-W01': 150.0};
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LineChartTimeSeries(data: weeklyData, group: TimeGroup.week),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.first.spots.length, 2);
    expect(chart.data.maxY, 150);
    expect(find.text('Dec 2023'), findsOneWidget);
    expect(find.text('Jan 2024'), findsOneWidget);
  });

  testWidgets('time series charts hide empty data and clamp negative ranges', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LineChartTimeSeries(data: {}, group: TimeGroup.week),
        ),
      ),
    );
    expect(find.byType(LineChart), findsNothing);

    const dailyData = {'2024-01-01': -40.0, '2024-01-05': -25.0};
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LineChartTimeSeries(data: dailyData, group: TimeGroup.day),
        ),
      ),
    );

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.minY, lessThan(0));
    expect(chart.data.maxY, equals(0));
  });

  testWidgets('body score summary card shows radar when summary provided', (
    tester,
  ) async {
    final now = DateTime.now();
    final lastWeek = lastFullWeekRange(now);
    final summary = BodyScoreService().summarize([
      makeRegionSession(
        start: lastWeek.start.add(const Duration(days: 2)),
        region: 'Chest',
      ),
    ], range: lastWeek)!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // The card renders inside a scrollable list in production, so give
          // it the same unbounded-height context here (it is taller than one
          // test viewport now that it includes the trend sparkline).
          body: SingleChildScrollView(
            child: BodyScoreSummaryCard(
              summary: summary,
              loading: false,
              periodWindow: BodyScorePeriod.lastFullWeek.resolve(now),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BodyScoreRadar), findsOneWidget);
    expect(find.textContaining('Training balance'), findsOneWidget);
  });

  testWidgets('empty body score summary card shows unlock hint', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BodyScoreSummaryCard(
            summary: null,
            loading: false,
            error: 'Log workouts to unlock your body score',
          ),
        ),
      ),
    );

    expect(find.textContaining('Log workouts'), findsOneWidget);
    expect(find.byType(BodyScoreRadar), findsNothing);
  });

  testWidgets(
    'body score screen title matches nav label and hides back arrow',
    (tester) async {
      getIt.registerSingleton<WorkoutRepository>(_Repo(const []));

      await tester.pumpWidget(const MaterialApp(home: BodyScoreScreen()));
      // Drain the screen's async init (incl. the one-time current-week
      // migration) so its pref writes complete within this test's scope.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('Training balance'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
      expect(find.byType(HustlMenuButton), findsOneWidget);
    },
  );

  testWidgets(
    'progress tab root puts the account avatar in actions (right) with '
    'a left-aligned title — the canonical tab-root rule',
    (tester) async {
      getIt.registerSingleton<WorkoutRepository>(_Repo(const []));
      await _pumpProgressScreen(tester);

      // The app bar title is left-aligned (centerTitle: false) on a tab root.
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.centerTitle, isFalse);
      // No back affordance / leading on a tab root.
      expect(appBar.leading, isNull);
      // The account avatar (HustlMenuButton) lives in actions, i.e. top-right,
      // matching Train/History/Library — never in leading.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(HustlMenuButton),
        ),
        findsOneWidget,
      );
      // It must NOT be in the leading slot: the only HustlMenuButton on the
      // screen is the one we just found in actions.
      expect(find.byType(HustlMenuButton), findsOneWidget);
    },
  );

  testWidgets('body score screen shows exercises mapped to Other callout', (
    tester,
  ) async {
    // This case seeds LAST full week data, so pin the surface to the last-full-
    // week period (the default is now the in-progress current week, Phase 1) and
    // mark the one-time current-week migration as already done so it is not
    // forced back to the current week on first run. Write through the registered
    // service so the values survive into the screen's own pref reads regardless
    // of test ordering.
    final prefs = getIt<PreferencesService>();
    await prefs.setRawString('body_score_current_week_default_v1', 'done');
    await prefs.setRawString(
      'body_score_period',
      BodyScorePeriod.lastFullWeek.id,
    );
    final now = DateTime.now();
    final lastWeek = lastFullWeekRange(now);
    getIt.registerSingleton<WorkoutRepository>(
      _Repo([
        makeRegionSession(
          start: lastWeek.start.add(const Duration(days: 3)),
          region: 'Chest',
        ),
        makeRegionSession(
          start: lastWeek.start,
          region: 'Mobility',
          weight: 80,
        ),
      ]),
    );

    await tester.pumpWidget(const MaterialApp(home: BodyScoreScreen()));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    for (var i = 0; i < 3; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(find.text('Exercises mapped to Other'), findsOneWidget);
    expect(find.textContaining('Mobility move'), findsOneWidget);
  });
}
