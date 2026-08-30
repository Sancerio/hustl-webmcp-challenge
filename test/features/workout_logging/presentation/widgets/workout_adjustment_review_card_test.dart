import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/core/webmcp/active_workout_web_mcp_controller.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/workout_adjustment_review_card.dart';

void main() {
  testWidgets('renders the real old-to-new diff and explicit review actions', (
    tester,
  ) async {
    var applied = 0;
    var discarded = 0;
    const before = WorkoutSet(id: 'set-1', weight: 60, reps: 8);
    const after = WorkoutSet(id: 'set-1', weight: 62.5, reps: 10, rpe: 8);
    const adjustment = StagedWorkoutAdjustment(
      ownerToken: 1,
      sessionId: 'session-1',
      baseRevision: 'revision-1',
      changes: [
        WorkoutSetAdjustment(
          exerciseId: 'exercise-1',
          exerciseName: 'Bench Press',
          setId: 'set-1',
          setNumber: 1,
          before: before,
          after: after,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: WorkoutAdjustmentReviewCard(
            adjustment: adjustment,
            onApply: () async => applied++,
            onDiscard: () => discarded++,
          ),
        ),
      ),
    );

    expect(find.text('Review suggested changes'), findsOneWidget);
    expect(find.text('Nothing changes until you apply them.'), findsOneWidget);
    expect(find.text('Not applied'), findsOneWidget);
    expect(find.text('Bench Press · Set 1'), findsOneWidget);
    expect(
      find.text('Weight 60 → 62.5  ·  Reps 8 → 10  ·  RPE — → 8'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('discardWorkoutAdjustment')));
    await tester.tap(find.byKey(const Key('applyWorkoutAdjustment')));
    await tester.pump();

    expect(discarded, 1);
    expect(applied, 1);
  });
}
