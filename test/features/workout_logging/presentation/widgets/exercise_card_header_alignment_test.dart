import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/data/repositories/mock_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/exercise_card.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/set_row.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/set_row_reps_field.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/set_row_weight_field.dart';

WorkoutExercise _exercise() {
  return const WorkoutExercise(
    id: 'ex1',
    exercise: Exercise(name: 'Bench Press', muscles: ['chest']),
    sets: [
      WorkoutSet(id: 's0', weight: 40, reps: 12),
      WorkoutSet(id: 's1', weight: 60, reps: 8),
    ],
  );
}

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 390, child: ListView(children: [child])),
    ),
  );
}

/// Finds the sets-table HEADER label [data] — a `Text` widget that is NOT a
/// descendant of any [SetRow]. This disambiguates the header `kg` from the
/// `kg` suffix rendered inside each weight field.
Finder _headerLabel(WidgetTester tester, String data) {
  final matches = find
      .descendant(of: find.byType(ExerciseCard), matching: find.text(data))
      .evaluate()
      .where(
        (e) => find
            .ancestor(
              of: find.byWidget(e.widget),
              matching: find.byType(SetRow),
            )
            .evaluate()
            .isEmpty,
      )
      .toList();
  expect(
    matches.length,
    1,
    reason: 'expected exactly one header label "$data" outside the set rows',
  );
  return find.byWidget(matches.single.widget);
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    await prefs.setHapticsEnabled(false);
    GetIt.I.registerSingleton<PreferencesService>(prefs);
    GetIt.I.registerLazySingleton<WorkoutRepository>(
      () => MockWorkoutRepository(),
    );
  });

  tearDown(() async {
    await GetIt.I.reset(dispose: true);
  });

  testWidgets('weightReps header columns line up above the data columns', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ExerciseCard(
          exercise: _exercise(),
          onExerciseUpdated: (_) {},
          onStartRestTimer: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 'kg' header is centered over the weight field.
    final kgHeader = tester.getRect(_headerLabel(tester, 'kg'));
    final weightField = tester.getRect(find.byType(SetRowWeightField).first);
    expect(
      (kgHeader.center.dx - weightField.center.dx).abs(),
      lessThan(1.0),
      reason: 'the "kg" header must be centered over the weight field',
    );

    // 'Reps' header is centered over the reps field.
    final repsHeader = tester.getRect(_headerLabel(tester, 'Reps'));
    final repsField = tester.getRect(find.byType(SetRowRepsField).first);
    expect(
      (repsHeader.center.dx - repsField.center.dx).abs(),
      lessThan(1.0),
      reason: 'the "Reps" header must be centered over the reps field',
    );

    // 'Set' header is centered over the set-number cell.
    final setHeader = tester.getRect(_headerLabel(tester, 'Set'));
    final setNumber = tester.getRect(find.text('1'));
    expect(
      (setHeader.center.dx - setNumber.center.dx).abs(),
      lessThan(1.0),
      reason: 'the "Set" header must be centered over the set-number column',
    );
  });

  testWidgets('action chips render in a Wrap — all visible, no hidden scroll', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ExerciseCard(
          exercise: _exercise(),
          onExerciseUpdated: (_) {},
          onStartRestTimer: (_) {},
          // Enabling Replace + delete surfaces the full common chip set.
          onExerciseReplaced: (_) {},
          onExerciseDeleted: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Every common secondary action is visible at once (the horizontal-scroll
    // layout used to clip chips behind a non-obvious swipe — this locks that
    // they all render together).
    for (final key in const [
      'chip-info',
      'chip-warmup',
      'chip-swap',
      'chip-rest-timer',
      'chip-more',
    ]) {
      expect(
        find.byKey(ValueKey(key)),
        findsOneWidget,
        reason: 'action chip "$key" must be visible without scrolling',
      );
    }

    // They live in a Wrap, not the old hidden horizontal SingleChildScrollView.
    final infoChip = find.byKey(const ValueKey('chip-info'));
    expect(
      find.ancestor(of: infoChip, matching: find.byType(Wrap)),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: infoChip, matching: find.byType(SingleChildScrollView)),
      findsNothing,
    );
  });
}
