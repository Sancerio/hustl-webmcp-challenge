import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/summary/summary_pr_cards.dart';

void main() {
  group('SummaryPrCards weight rendering', () {
    testWidgets(
      'renders a micro-plate PR weight without rounding 3.75 to 3.8',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SummaryPrCards(
                entries: [
                  SummaryPrEntry(
                    exerciseName: 'Bicep Curl (Dumbbell)',
                    weight: 3.75,
                    reps: 12,
                  ),
                ],
              ),
            ),
          ),
        );

        expect(find.text('3.75 kg × 12'), findsOneWidget);
        expect(find.text('3.8 kg × 12'), findsNothing);
      },
    );

    testWidgets('whole-number PR weights show no trailing decimals', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SummaryPrCards(
              entries: [
                SummaryPrEntry(
                  exerciseName: 'Bench Press (Barbell)',
                  weight: 100,
                  reps: 5,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('100 kg × 5'), findsOneWidget);
    });

    testWidgets('distance-duration PRs render km and time instead of kg', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SummaryPrCards(
              entries: [
                SummaryPrEntry(
                  exerciseName: 'Run',
                  weight: 1.5,
                  reps: 540,
                  loggingMode: ExerciseLoggingMode.distanceDuration,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('1.5 km × 09:00'), findsOneWidget);
      expect(find.textContaining('kg'), findsNothing);
    });

    test('session extractor ignores non-weight PR flags', () {
      final entries = prEntriesFromSession(
        WorkoutSession(
          id: 's',
          name: 'Cardio',
          startTime: DateTime(2026),
          exercises: const [
            WorkoutExercise(
              id: 'run',
              exercise: Exercise(
                name: 'Run',
                muscles: ['Cardio'],
                loggingMode: ExerciseLoggingMode.distanceDuration,
              ),
              sets: [WorkoutSet(id: 'set', weight: 1.5, reps: 540, isPr: true)],
            ),
          ],
        ),
      );

      expect(entries, isEmpty);
    });
  });
}
