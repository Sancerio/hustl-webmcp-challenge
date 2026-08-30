import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/summary/summary_pr_cards.dart';

/// Renders [SummaryPrCards] with a mix of PR entries — some carrying a logged
/// RPE (rendering the [EffortReserveGauge]), one without — in both theme
/// brightnesses, so the added effort gauge on each PR row is visually
/// captured.
///
///   flutter test --no-pub --update-goldens \
///     test/features/workout_logging/presentation/widgets/summary/summary_pr_cards_golden_test.dart
void main() {
  const entries = [
    SummaryPrEntry(exerciseName: 'Bench Press', weight: 100, reps: 5, rpe: 8),
    SummaryPrEntry(exerciseName: 'Back Squat', weight: 140, reps: 3, rpe: 10),
    SummaryPrEntry(exerciseName: 'Deadlift', weight: 180, reps: 1),
  ];

  Future<void> pumpHarness(WidgetTester tester, ThemeData theme) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(420 * 2, 320 * 2);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: SummaryPrCards(entries: entries),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('summary PR cards with effort gauges — light', (tester) async {
    await pumpHarness(tester, AppTheme.lightTheme);

    await expectLater(
      find.byType(SummaryPrCards),
      matchesGoldenFile('goldens/summary_pr_cards_light.png'),
    );
  });

  testWidgets('summary PR cards with effort gauges — dark', (tester) async {
    await pumpHarness(tester, AppTheme.darkTheme);

    await expectLater(
      find.byType(SummaryPrCards),
      matchesGoldenFile('goldens/summary_pr_cards_dark.png'),
    );
  });
}
