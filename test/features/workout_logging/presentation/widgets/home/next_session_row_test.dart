import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/next_session_row.dart';

WorkoutSession _session() => WorkoutSession(
  id: 'upper',
  name: 'Upper',
  startTime: DateTime(2026, 6, 13, 9),
  endTime: DateTime(2026, 6, 13, 10),
  isCompleted: true,
  exercises: const [
    WorkoutExercise(
      id: 'bench',
      exercise: Exercise(name: 'Bench Press', muscles: ['Chest']),
      sets: [WorkoutSet(id: 's', weight: 100, reps: 5, isCompleted: true)],
    ),
  ],
);

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('appends "lighter day suggested" for the Recharge band', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        NextSessionRow.forSession(
          _session(),
          onStart: () {},
          readinessBand: RecoveryFlowBand.recharge,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('lighter day suggested'), findsOneWidget);
    // The Start CTA stays unconditional and unchanged.
    expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
  });

  testWidgets('appends "moderate day" for the Steady band', (tester) async {
    await tester.pumpWidget(
      host(
        NextSessionRow.forSession(
          _session(),
          onStart: () {},
          readinessBand: RecoveryFlowBand.steady,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('moderate day'), findsOneWidget);
  });

  testWidgets('appends nothing for the Ready band', (tester) async {
    await tester.pumpWidget(
      host(
        NextSessionRow.forSession(
          _session(),
          onStart: () {},
          readinessBand: RecoveryFlowBand.ready,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('lighter day'), findsNothing);
    expect(find.textContaining('moderate day'), findsNothing);
    // Meta is the plain session line.
    expect(find.text('1 exercise · ~60 min'), findsOneWidget);
  });

  testWidgets('meta is unchanged when no readiness band is provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(NextSessionRow.forSession(_session(), onStart: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 exercise · ~60 min'), findsOneWidget);
    expect(find.textContaining('lighter day'), findsNothing);
    expect(find.textContaining('moderate day'), findsNothing);
  });
}
