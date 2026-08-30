import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/core/widgets/app_progress_ring.dart';
import 'package:hustl_app/core/widgets/staggered_entrance.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/summary/summary_celebration_hero.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/summary/summary_pr_cards.dart';

void main() {
  setUp(StaggeredEntrance.resetForTest);

  testWidgets('celebration hero is data-as-hero: blue ring with big volume', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SummaryCelebrationHero(
            title: 'Workout complete',
            subtitle: 'You set a new personal record',
            exercises: 4,
            prs: 2,
            metricValue: 5200,
          ),
        ),
      ),
    );
    // Let the count-up + ring entrance + stagger settle.
    await tester.pumpAndSettle();

    // Wave I: the focal metric is an AppProgressRing hero (no gradient sweep —
    // the ring uses the solid blue accent, so still no ShaderMask).
    final ring = tester.widget<AppProgressRing>(find.byType(AppProgressRing));
    expect(ring.progress, 1);
    expect(ring.semanticsLabel, 'Total volume');
    expect(find.byType(ShaderMask), findsNothing);

    // The ring is blue (colorScheme.primary).
    final colors = Theme.of(
      tester.element(find.byType(AppProgressRing)),
    ).colorScheme;
    expect(ring.color, colors.primary);

    expect(find.text('Workout complete'), findsOneWidget);

    // The session volume is BIG and centred inside the ring (34/w700,
    // thousands-separated), captioned by its quiet unit label.
    final volumeText = tester.widget<Text>(find.text('5,200'));
    expect(volumeText.style?.fontSize, 34);
    expect(volumeText.style?.fontWeight, FontWeight.w700);
    expect(find.text('kg volume'), findsOneWidget);

    // Exercises / PRs counts remain as aligned stat rows beneath the ring.
    expect(find.text('Exercises'), findsOneWidget);
    expect(find.text('PRs'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('cardio hero centres on distance instead of kg volume', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SummaryCelebrationHero(
            title: 'Workout complete',
            subtitle: 'Logged just now · 32 min',
            exercises: 1,
            prs: 0,
            metricValue: 5.2,
            metricUnitLabel: 'km distance',
            metricSemanticsLabel: 'Total distance',
            metricFractionDigits: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final ring = tester.widget<AppProgressRing>(find.byType(AppProgressRing));
    expect(ring.semanticsLabel, 'Total distance');
    expect(find.text('5.2'), findsOneWidget);
    expect(find.text('km distance'), findsOneWidget);
    expect(find.text('kg volume'), findsNothing);
  });

  testWidgets('PR rows render one quiet trophy row per PR set', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SummaryPrCards(
            entries: [
              SummaryPrEntry(exerciseName: 'Bench Press', weight: 100, reps: 5),
              SummaryPrEntry(exerciseName: 'Squat', weight: 140, reps: 3),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    // The shared SectionHeader now renders sentence-case (plural for >1 PR).
    expect(find.text('New personal records'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events_rounded), findsNWidgets(2));
  });
}
