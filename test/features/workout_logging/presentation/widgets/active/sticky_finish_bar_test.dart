import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/active/sticky_finish_bar.dart';

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required int completedSets,
    required int totalSets,
    required int exerciseCount,
    bool showVolume = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StickyFinishBar(
            completedSets: completedSets,
            totalSets: totalSets,
            totalVolume: 0,
            exerciseCount: exerciseCount,
            showVolume: showVolume,
            onFinish: () {},
            onCancel: () {},
          ),
        ),
      ),
    );
  }

  group('StickyFinishBar state selection', () {
    testWidgets('shows Finish once at least one set is completed', (
      tester,
    ) async {
      await pumpBar(tester, completedSets: 1, totalSets: 26, exerciseCount: 8);

      expect(find.text('Finish'), findsOneWidget);
      expect(find.text('Cancel workout'), findsNothing);
    });

    testWidgets(
      'shows Cancel workout when exercises exist but nothing is logged',
      (tester) async {
        // The screenshot case: a full plate (8 exercises, 26 planned sets) with
        // 0 completed must surface cancel/discard, not a misleading Finish.
        await pumpBar(
          tester,
          completedSets: 0,
          totalSets: 26,
          exerciseCount: 8,
        );

        expect(find.text('Cancel workout'), findsOneWidget);
        expect(find.text('Finish'), findsNothing);
      },
    );

    testWidgets('shows Cancel workout for a fully empty workout', (
      tester,
    ) async {
      await pumpBar(tester, completedSets: 0, totalSets: 0, exerciseCount: 0);

      expect(find.text('Cancel workout'), findsOneWidget);
      expect(find.text('Finish'), findsNothing);
    });

    testWidgets('hides the kg volume segment for non-weight sessions', (
      tester,
    ) async {
      await pumpBar(
        tester,
        completedSets: 2,
        totalSets: 3,
        exerciseCount: 1,
        showVolume: false,
      );

      expect(find.text('2 of 3 sets'), findsOneWidget);
      expect(find.textContaining('kg'), findsNothing);
    });
  });
}
