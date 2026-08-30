import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/home_week_stats.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/week_training_widget.dart';

WorkoutSession _session(
  String id,
  DateTime start, {
  double weight = 100,
  int reps = 5,
  int sets = 2,
}) => WorkoutSession(
  id: id,
  name: id,
  startTime: start,
  endTime: start.add(const Duration(hours: 1)),
  isCompleted: true,
  exercises: [
    WorkoutExercise(
      id: '$id-bench',
      exercise: const Exercise(name: 'Bench Press', muscles: ['Chest']),
      sets: [
        for (var i = 0; i < sets; i++)
          WorkoutSet(
            id: '$id-s$i',
            weight: weight,
            reps: reps,
            isCompleted: true,
          ),
      ],
    ),
  ],
);

void main() {
  group('HomeWeekStats', () {
    test('aggregates the current calendar week per day', () {
      // A fixed Thursday so the week window is deterministic.
      final now = DateTime(2026, 6, 11, 18); // Thursday
      final monday = DateTime(2026, 6, 8, 9);
      final tuesday = DateTime(2026, 6, 9, 9);
      final lastFriday = DateTime(2026, 6, 5, 9);

      final stats = HomeWeekStats.from([
        _session('mon', monday), // 2 sets x 100 x 5 = 1000 kg
        _session('tue', tuesday),
        _session('prev-fri', lastFriday),
      ], now: now);

      expect(stats.days.length, 7);
      expect(stats.days.first.date.weekday, DateTime.monday);
      expect(stats.days[0].volume, 1000);
      expect(stats.days[0].sets, 2);
      expect(stats.days[1].volume, 1000);
      expect(stats.days[3].isToday, isTrue);
      // Last Friday's session belongs to the prior week.
      expect(stats.days[4].volume, 0);
      expect(stats.weekVolume, 2000);
      expect(stats.weekWorkouts, 2);
      expect(stats.weekSets, 4);
    });

    test('derives quiet targets from prior weeks', () {
      final now = DateTime(2026, 6, 11, 18); // Thursday
      // One prior week with two training days of 1000 kg / 2 sets each.
      final stats = HomeWeekStats.from([
        _session('prev-mon', DateTime(2026, 6, 1, 9)),
        _session('prev-wed', DateTime(2026, 6, 3, 9)),
        _session('mon', DateTime(2026, 6, 8, 9)),
      ], now: now);

      expect(stats.weekVolumeTarget, 2000);
      expect(stats.dayVolumeTarget, 1000);
      expect(stats.daySetsTarget, 2);
      // Weekly series ends with the current week and includes the prior one.
      expect(stats.weeklyVolumes, [2000, 1000]);
    });

    test('has no targets without history', () {
      final stats = HomeWeekStats.from([
        _session('mon', DateTime(2026, 6, 8, 9)),
      ], now: DateTime(2026, 6, 11));

      expect(stats.weekVolumeTarget, 0);
      expect(stats.dayVolumeTarget, 0);
      expect(stats.weeklyVolumes, [1000]);
    });
  });

  group('WeekTrainingWidget', () {
    Widget host(HomeWeekStats stats, {bool showSummary = true}) => MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: WeekTrainingWidget(stats: stats, showSummary: showSummary),
        ),
      ),
    );

    // Mon=0 is the only trained day (volume 1200 / 10 sets); the rest are
    // rest days. Exactly one day is marked today via [todayIndex].
    HomeWeekStats stats({int todayIndex = 0}) {
      final monday = DateTime(2026, 6, 8); // a Monday
      return HomeWeekStats(
        days: [
          for (var i = 0; i < 7; i++)
            HomeDayTraining(
              date: monday.add(Duration(days: i)),
              volume: i == 0 ? 1200 : 0,
              sets: i == 0 ? 10 : 0,
              isToday: i == todayIndex,
            ),
        ],
        weekVolume: 1200,
        weekWorkouts: 1,
        weekSets: 10,
        dayVolumeTarget: 0,
        daySetsTarget: 0,
        weekVolumeTarget: 0,
        weeklyVolumes: const [1000, 1200],
      );
    }

    // Two trained days with very different volumes (Mon: heavy 4000 kg, Wed:
    // light 500 kg) plus a sets-only day (Fri) and rest days — so we can prove
    // the bars are BINARY (full vs none) and never volume-proportional.
    HomeWeekStats binaryStats() {
      final monday = DateTime(2026, 6, 8);
      const volumes = [4000.0, 0.0, 500.0, 0.0, 0.0, 0.0, 0.0];
      const sets = [20, 0, 4, 0, 6, 0, 0]; // Fri is sets-only (no volume)
      return HomeWeekStats(
        days: [
          for (var i = 0; i < 7; i++)
            HomeDayTraining(
              date: monday.add(Duration(days: i)),
              volume: volumes[i],
              sets: sets[i],
              isToday: i == 6,
            ),
        ],
        weekVolume: 4500,
        weekWorkouts: 3,
        weekSets: 30,
        dayVolumeTarget: 0,
        daySetsTarget: 0,
        weekVolumeTarget: 0,
        weeklyVolumes: const [4500],
      );
    }

    // The heightFactor of every trained-day fill, in render order.
    List<double> fillFactors(WidgetTester tester) => tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .map((b) => b.heightFactor ?? 0)
        .toList();

    // The day-letter Texts beneath each bar, in render order (Mon–Sun).
    List<Text> dayLetters(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => (t.data?.length ?? 2) == 1)
        .toList();

    testWidgets('renders the compact week volume summary by default', (
      tester,
    ) async {
      await tester.pumpWidget(host(stats()));

      // 1200 kg -> '1.2k' rendered in the emphasis metric style.
      final number = tester.widget<Text>(find.text('1.2k'));
      expect(number.style?.fontWeight, FontWeight.w700);
      expect(number.style?.fontSize, 22);
      expect(find.text('kg this week'), findsOneWidget);
      // The old two-bar / target copy is gone.
      expect(find.text('of 4k kg'), findsNothing);
    });

    testWidgets('omits the summary column when showSummary is false', (
      tester,
    ) async {
      await tester.pumpWidget(host(stats(), showSummary: false));

      expect(find.text('1.2k'), findsNothing);
      expect(find.text('kg this week'), findsNothing);
      // The seven daily bars remain.
      expect(dayLetters(tester).length, 7);
    });

    testWidgets('renders one daily bar per day with the Mon–Sun letters', (
      tester,
    ) async {
      await tester.pumpWidget(host(stats()));

      final letters = dayLetters(tester).map((t) => t.data).toList();
      expect(letters, ['M', 'T', 'W', 'T', 'F', 'S', 'S']);
    });

    testWidgets('emphasises only the current day letter', (tester) async {
      await tester.pumpWidget(host(stats(todayIndex: 3))); // Thursday

      final context = tester.element(find.byType(WeekTrainingWidget));
      final colors = Theme.of(context).colorScheme;

      final bold = dayLetters(
        tester,
      ).where((t) => t.style?.fontWeight == FontWeight.w700).toList();
      expect(bold.length, 1);
      expect(bold.single.data, 'T'); // index 3 letter (Thursday)
      expect(bold.single.style?.color, colors.onSurface);

      // Every other letter is the quieter weekday treatment.
      final quiet = dayLetters(
        tester,
      ).where((t) => t.style?.fontWeight == FontWeight.w500).toList();
      expect(quiet.length, 6);
      expect(
        quiet.every((t) => t.style?.color == colors.onSurfaceVariant),
        isTrue,
      );
    });

    testWidgets('fills trained days in the primary accent over a faint track', (
      tester,
    ) async {
      await tester.pumpWidget(host(stats()));
      await tester.pumpAndSettle(); // let the fill tween complete

      final context = tester.element(find.byType(WeekTrainingWidget));
      final colors = Theme.of(context).colorScheme;

      final fillColors = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => (d.decoration as BoxDecoration).color)
          .toList();

      // The single trained day fills in the blue primary accent.
      expect(fillColors.where((c) => c == colors.primary).length, 1);
      // Rest-day tracks are the faint onSurfaceVariant wash.
      final track = colors.onSurfaceVariant.withValues(alpha: 0.18);
      expect(fillColors, contains(track));
    });

    testWidgets('trained days render a FULL bar; rest days are track-only', (
      tester,
    ) async {
      await tester.pumpWidget(host(binaryStats()));
      await tester.pumpAndSettle(); // let the fill tween settle

      // Three trained days (heavy Mon, light Wed, sets-only Fri) → three fills,
      // and EVERY fill is a full bar (1.0) — no volume-proportional heights.
      final factors = fillFactors(tester);
      expect(factors.length, 3, reason: 'one fill per trained day, none more');
      expect(
        factors,
        everyElement(closeTo(1.0, 0.0001)),
        reason: 'binary bars: trained = full, never partial volume fill',
      );
    });

    testWidgets('a single trained day fills fully (no partial volume fill)', (
      tester,
    ) async {
      await tester.pumpWidget(host(stats()));
      await tester.pumpAndSettle();

      final factors = fillFactors(tester);
      expect(factors.length, 1); // only Mon is trained
      expect(factors.single, closeTo(1.0, 0.0001));
    });

    testWidgets('renders no fixed-width target ticks', (tester) async {
      await tester.pumpWidget(host(stats()));

      // The old 2px target ticks no longer exist anywhere in the chart.
      final ticks = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.constraints?.maxWidth == 2);
      expect(ticks, isEmpty);
    });
  });
}
