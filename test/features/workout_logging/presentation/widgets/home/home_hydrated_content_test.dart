import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/core/widgets/app_progress_ring.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';
import 'package:hustl_app/core/widgets/staggered_entrance.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/services/next_workout_focus_service.dart';
import 'package:hustl_app/features/workout_log/domain/utils/time_periods.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/home_hydrated_content.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/home_volume_trend_chart.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/home_week_stats.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/next_session_row.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/readiness_today_row.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/readiness_today_slot.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/train_section_rows.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/week_training_widget.dart';

DailyRecoverySnapshot _readySnapshot() => DailyRecoverySnapshot(
  date: DateTime(2026, 6, 13),
  sleepPerformanceScore: 82,
  hrvValue: 58,
  hrvKind: HrvKind.sdnn,
  restingHeartRateBpm: 54,
  readinessScore: 74,
  recoveryScore: 71,
  baselineCoverageDays: 21,
  band: RecoveryFlowBand.ready.legacyBand,
  flowBand: RecoveryFlowBand.ready,
  confidence: RecoveryConfidence.high,
);

DailyRecoverySnapshot _rechargeSnapshot() => DailyRecoverySnapshot(
  date: DateTime(2026, 4, 6),
  hrvValue: 40,
  hrvKind: HrvKind.sdnn,
  baselineCoverageDays: 21,
  band: RecoveryFlowBand.recharge.legacyBand,
  flowBand: RecoveryFlowBand.recharge,
  confidence: RecoveryConfidence.high,
);

/// Builds a real focus plan (over a fixed anchor so the verdict is
/// deterministic), optionally carrying the readiness context line.
NextWorkoutFocusPlan? _focusPlan({DailyRecoverySnapshot? readiness}) {
  final anchor = DateTime.utc(2026, 4, 6, 12);
  final sessions = [
    _session('Bench Press', anchor.subtract(const Duration(days: 3))),
  ];
  return NextWorkoutFocusService(
    period: BodyScorePeriod.last4FullWeeks,
  ).build(sessions, anchor: anchor, readiness: readiness);
}

WorkoutSession _session(String name, DateTime start) => WorkoutSession(
  id: name,
  name: name,
  startTime: start,
  endTime: start.add(const Duration(hours: 1)),
  isCompleted: true,
  exercises: [
    WorkoutExercise(
      id: '$name-bench',
      exercise: const Exercise(name: 'Bench Press', muscles: ['Chest']),
      sets: const [
        WorkoutSet(id: 's', weight: 100, reps: 5, isCompleted: true),
      ],
    ),
  ],
);

/// Distinct in-week sessions so [HomeWeekStats] counts N workouts this week.
List<WorkoutSession> _sessionsThisWeek(int count) {
  // Monday of the current calendar week, so every session lands in-week.
  final now = DateTime.now();
  final monday = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: now.weekday - 1));
  return [
    for (var i = 0; i < count; i++)
      _session('Day $i', monday.add(Duration(days: i, hours: 9))),
  ];
}

void main() {
  setUp(StaggeredEntrance.resetForTest);

  Widget host({
    required List<WorkoutSession> recent,
    DailyRecoverySnapshot? readiness,
    NextWorkoutFocusPlan? focus,
    int weeklyWorkoutGoal = 3,
  }) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: HomeHydratedContent(
          recent: recent,
          stats: HomeWeekStats.from(recent),
          templates: const [],
          focus: focus,
          readiness: readiness,
          weeklyWorkoutGoal: weeklyWorkoutGoal,
          onStartEmptyWorkout: () {},
          onRepeatSession: (_) {},
          onOpenTemplates: () {},
          onOpenBodyScore: () {},
        ),
      ),
    ),
  );

  AppProgressRing ring(WidgetTester tester) =>
      tester.widget<AppProgressRing>(find.byType(AppProgressRing));

  testWidgets('new user sees the first-workout next-session card', (
    tester,
  ) async {
    await tester.pumpWidget(host(recent: const []));
    await tester.pumpAndSettle();

    // First-workout variant of the next-session card with a FilledButton CTA.
    expect(find.text('Start your first workout'), findsOneWidget);
    expect(find.byType(NextSessionRow), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NextSessionRow),
        matching: find.widgetWithText(FilledButton, 'Start'),
      ),
      findsOneWidget,
    );
    expect(find.text('Repeat'), findsNothing);
  });

  testWidgets('returning user sees the Wave I dashboard column', (
    tester,
  ) async {
    final recent = [_session('Push Day', DateTime.now())];
    await tester.pumpWidget(host(recent: recent));
    await tester.pumpAndSettle();

    // Train hero card: a blue week ring with the workouts count big in its
    // centre and the 7-day bars (WeekTrainingWidget) below.
    expect(find.byType(AppProgressRing), findsOneWidget);
    expect(find.byType(WeekTrainingWidget), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);

    // Next session is now a CARD with a FilledButton "Start" (not a text link).
    expect(find.byType(NextSessionRow), findsOneWidget);
    expect(find.text('Repeat Push Day'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NextSessionRow),
        matching: find.widgetWithText(FilledButton, 'Start'),
      ),
      findsOneWidget,
    );

    // Sentence-case section headers (no UPPERCASE, no "Insights" ledger).
    expect(find.text('Training'), findsOneWidget);
    expect(find.text('Volume trend'), findsOneWidget);
    expect(find.text('TRAINING'), findsNothing);
    expect(find.text('Insights'), findsNothing);

    // "Training" is a grouped card (SectionList card:true) of two nav rows.
    expect(find.byType(TrainNavRow), findsNWidgets(2));
    expect(find.text('Templates'), findsOneWidget);
    expect(find.text('Training balance'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(3));

    // The redundant "This week" Volume/Workouts/Sets ledger was deleted.
    expect(find.byType(TrainStatRow), findsNothing);
    expect(find.text('THIS WEEK'), findsNothing);
    expect(find.text('Volume'), findsNothing);
  });

  testWidgets('brand-new user (no history) sees the first-workout hero copy', (
    tester,
  ) async {
    await tester.pumpWidget(host(recent: const []));
    await tester.pumpAndSettle();

    expect(find.text('Your first workout starts here'), findsOneWidget);
    expect(find.text('Log your first workout'), findsOneWidget);
    expect(find.text('New week, fresh start'), findsNothing);
  });

  testWidgets('returning user with an empty current week sees the "fresh week" '
      'hero, not first-workout copy', (tester) async {
    // A completed session three weeks ago: the user HAS history, but the
    // current calendar week is empty. The hero must not call this their first
    // workout.
    final recent = [
      _session('Push Day', DateTime.now().subtract(const Duration(days: 21))),
    ];
    await tester.pumpWidget(host(recent: recent));
    await tester.pumpAndSettle();

    expect(find.text('New week, fresh start'), findsOneWidget);
    expect(find.text('No workouts logged yet this week'), findsOneWidget);
    expect(find.text('Your first workout starts here'), findsNothing);
    expect(find.text('Log your first workout'), findsNothing);
  });

  testWidgets('hero ring tracks the weekly workout goal and stays blue below '
      'it', (tester) async {
    // 2 workouts logged this week against a goal of 3 → 2/3 progress, blue.
    await tester.pumpWidget(
      host(recent: _sessionsThisWeek(2), weeklyWorkoutGoal: 3),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(HomeHydratedContent));
    final colors = Theme.of(context).colorScheme;

    final r = ring(tester);
    expect(r.progress, closeTo(2 / 3, 0.0001));
    expect(r.color, colors.primary); // blue while below goal

    // The ring (2/3) and the centre numeral (2 of 3) read as the same thing.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('of 3'), findsOneWidget);
  });

  testWidgets('hero ring turns emerald once the weekly goal is met', (
    tester,
  ) async {
    // 3 workouts this week against a goal of 3 → full ring, emerald goal-met.
    await tester.pumpWidget(
      host(recent: _sessionsThisWeek(3), weeklyWorkoutGoal: 3),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(HomeHydratedContent));
    final colors = Theme.of(context).colorScheme;

    final r = ring(tester);
    expect(r.progress, 1.0);
    expect(r.color, colors.tertiary); // emerald success/goal-met tone
    expect(r.color, isNot(colors.primary));
  });

  testWidgets('hero ring caps at full and stays emerald when goal is '
      'exceeded', (tester) async {
    // 4 workouts against a goal of 3 → clamped to 1.0 and still emerald.
    await tester.pumpWidget(
      host(recent: _sessionsThisWeek(4), weeklyWorkoutGoal: 3),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(HomeHydratedContent));
    final colors = Theme.of(context).colorScheme;

    final r = ring(tester);
    expect(r.progress, 1.0);
    expect(r.color, colors.tertiary);
  });

  testWidgets('renders the readiness row when a snapshot is present', (
    tester,
  ) async {
    final recent = [_session('Push Day', DateTime.now())];
    await tester.pumpWidget(host(recent: recent, readiness: _readySnapshot()));
    await tester.pumpAndSettle();

    expect(find.byType(ReadinessTodayRow), findsOneWidget);
    expect(find.text('Readiness'), findsOneWidget);
    expect(find.textContaining('Ready'), findsOneWidget);
  });

  testWidgets('renders a stable unavailable row when readiness is null', (
    tester,
  ) async {
    final recent = [_session('Push Day', DateTime.now())];
    await tester.pumpWidget(host(recent: recent));
    await tester.pumpAndSettle();

    // No snapshot resolves to a quiet, fixed-height state that still links to
    // Health instead of collapsing the list.
    expect(find.byType(ReadinessTodayRow), findsNothing);
    expect(find.byType(ReadinessTodaySlot), findsOneWidget);
    expect(find.text('Readiness'), findsOneWidget);
    expect(find.text('Not available yet'), findsOneWidget);
    expect(find.byType(NextSessionRow), findsOneWidget);
  });

  testWidgets(
    'focus card shows the readiness context line on a low-readiness day',
    (tester) async {
      final recent = [_session('Push Day', DateTime.now())];
      final focus = _focusPlan(readiness: _rechargeSnapshot());
      expect(
        focus?.readinessNote,
        'Recovery is low today — a lighter session still counts.',
        reason: 'a Recharge-band snapshot should map to the lighter note',
      );

      await tester.pumpWidget(host(recent: recent, focus: focus));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('a lighter session still counts'),
        findsOneWidget,
      );
    },
  );

  testWidgets('focus card renders no readiness line when readiness is absent', (
    tester,
  ) async {
    final recent = [_session('Push Day', DateTime.now())];
    final focus = _focusPlan();
    expect(focus?.readinessNote, isNull);

    await tester.pumpWidget(host(recent: recent, focus: focus));
    await tester.pumpAndSettle();

    // The coach card still renders its verdict, but carries no readiness line.
    expect(find.textContaining('lighter session'), findsNothing);
    expect(find.textContaining('a good day to push'), findsNothing);
  });

  testWidgets(
    'late readiness and goal hydration preserve the volume-chart element',
    (tester) async {
      final recent = _sessionsThisWeek(2);
      final liveFocus = ValueNotifier<NextWorkoutFocusPlan?>(_focusPlan());
      final liveReadiness = ValueNotifier<ReadinessTodayState>(
        const ReadinessTodayState.loading(),
      );
      final liveGoal = ValueNotifier<int>(3);
      addTearDown(liveFocus.dispose);
      addTearDown(liveReadiness.dispose);
      addTearDown(liveGoal.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HomeHydratedContent(
                recent: recent,
                stats: HomeWeekStats.from(recent),
                templates: const [],
                focusListenable: liveFocus,
                readinessStateListenable: liveReadiness,
                weeklyWorkoutGoalListenable: liveGoal,
                onStartEmptyWorkout: () {},
                onRepeatSession: (_) {},
                onOpenTemplates: () {},
                onOpenBodyScore: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chartBefore = tester.element(find.byType(HomeVolumeTrendChart));
      final nextSessionTopBefore = tester.getTopLeft(
        find.byType(NextSessionRow),
      );
      final slotSizeBefore = tester.getSize(find.byType(ReadinessTodaySlot));
      expect(slotSizeBefore.height, ReadinessTodaySlot.height);
      final readinessSkeletons = find.descendant(
        of: find.byType(ReadinessTodaySlot),
        matching: find.byType(AppSkeleton),
      );
      expect(readinessSkeletons, findsNWidgets(4));
      for (final skeleton in tester.widgetList<AppSkeleton>(
        readinessSkeletons,
      )) {
        expect(skeleton.animate, isFalse);
      }

      // Exercise the low-readiness state that carries an optional coach note
      // in the domain model. The screen deliberately keeps the already-built
      // focus card unchanged so late Health data cannot grow that card.
      liveReadiness.value = ReadinessTodayState.available(_rechargeSnapshot());
      liveGoal.value = 4;
      await tester.pump();

      expect(find.byType(ReadinessTodayRow), findsOneWidget);
      expect(
        tester
            .widget<AnimatedSwitcher>(
              find.descendant(
                of: find.byType(ReadinessTodaySlot),
                matching: find.byType(AnimatedSwitcher),
              ),
            )
            .duration,
        AppMotion.fast,
      );
      expect(
        tester.getTopLeft(find.byType(NextSessionRow)),
        nextSessionTopBefore,
        reason: 'late readiness must not move the next-session row',
      );
      expect(tester.getSize(find.byType(ReadinessTodaySlot)), slotSizeBefore);
      expect(find.textContaining('lighter session still counts'), findsNothing);
      expect(ring(tester).progress, closeTo(0.5, 0.0001));
      expect(
        identical(
          chartBefore,
          tester.element(find.byType(HomeVolumeTrendChart)),
        ),
        isTrue,
        reason:
            'late annotations must not rebuild the static chart or scroll '
            'content while the user is dragging',
      );
    },
  );

  testWidgets('lays out without overflow on a 360px-wide screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // A large week volume exercises the tightest rows.
    final recent = [_session('Full Body Strength Session', DateTime.now())];
    await tester.pumpWidget(host(recent: recent));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AppProgressRing), findsOneWidget);
    expect(find.text('Training'), findsOneWidget);
  });
}
