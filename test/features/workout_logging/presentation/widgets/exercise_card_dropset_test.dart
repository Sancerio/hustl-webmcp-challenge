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

WorkoutExercise _exercise({List<WorkoutSet>? sets}) {
  return WorkoutExercise(
    id: 'ex1',
    exercise: const Exercise(name: 'Leg Extension', muscles: ['quads']),
    sets:
        sets ??
        const [
          WorkoutSet(id: 's0', weight: 40, reps: 12),
          WorkoutSet(id: 's1', weight: 40, reps: 12),
          WorkoutSet(id: 's2', weight: 100, reps: 8, isCompleted: true),
        ],
  );
}

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: ListView(children: [child])),
  );
}

class _ExerciseCardHarness extends StatefulWidget {
  const _ExerciseCardHarness({required this.exercise, required this.onUpdated});

  final WorkoutExercise exercise;
  final ValueChanged<WorkoutExercise> onUpdated;

  @override
  State<_ExerciseCardHarness> createState() => _ExerciseCardHarnessState();
}

class _ExerciseCardHarnessState extends State<_ExerciseCardHarness> {
  late WorkoutExercise exercise = widget.exercise;

  @override
  Widget build(BuildContext context) {
    return ExerciseCard(
      exercise: exercise,
      onExerciseUpdated: (updated) {
        widget.onUpdated(updated);
        setState(() => exercise = updated);
      },
      onStartRestTimer: (_) {},
    );
  }
}

/// Taps the Set badge for the row at [rowIndex] (0-based, in list order) — the
/// badge is now the set-type selector (Strong-style; no separate icon button) —
/// and picks the menu entry [label]. The trigger keeps the stable
/// `setTypeButton` key.
Future<void> _pickType(WidgetTester tester, int rowIndex, String label) async {
  final badges = find.byKey(const Key('setTypeButton'));
  await tester.tap(badges.at(rowIndex));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
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

  testWidgets(
    'picking "Drop set" on a working set appends a pre-filled drop ~-15%',
    (tester) async {
      late WorkoutExercise updated;
      await tester.pumpWidget(
        _host(
          ExerciseCard(
            exercise: _exercise(),
            onExerciseUpdated: (e) => updated = e,
            onStartRestTimer: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Row index 2 is the heavy working set (100kg x 8), completed.
      await _pickType(tester, 2, 'Drop set');

      // One child drop appended beneath the parent.
      final drops = updated.sets
          .where((s) => s.setType == SetType.dropset)
          .toList();
      expect(drops.length, 1);
      final drop = drops.single;
      expect(drop.parentSetId, 's2');
      expect(drop.dropIndex, 1);
      // 100 - 15% = 85, floored to a 2.5 multiple.
      expect(drop.weight, 85);
      // reps pre-filled from the parent.
      expect(drop.reps, 8);
    },
  );

  testWidgets('the Set column shows 3 / 3.1 / 3.2 with a D badge (no 4)', (
    tester,
  ) async {
    const sets = [
      WorkoutSet(id: 's0', weight: 40, reps: 12),
      WorkoutSet(id: 's1', weight: 40, reps: 12),
      WorkoutSet(id: 's2', weight: 100, reps: 8, isCompleted: true),
      WorkoutSet(
        id: 'd1',
        weight: 85,
        reps: 8,
        setType: SetType.dropset,
        parentSetId: 's2',
        dropIndex: 1,
      ),
      WorkoutSet(
        id: 'd2',
        weight: 70,
        reps: 8,
        setType: SetType.dropset,
        parentSetId: 's2',
        dropIndex: 2,
      ),
    ];

    await tester.pumpWidget(
      _host(
        ExerciseCard(
          exercise: _exercise(sets: sets),
          onExerciseUpdated: (_) {},
          onStartRestTimer: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Parent keeps its working ordinal 3.
    expect(find.text('3'), findsOneWidget);
    // Drops render 3.1 / 3.2.
    expect(find.text('3.1'), findsOneWidget);
    expect(find.text('3.2'), findsOneWidget);
    // The Set column never implies a 4th top-level set.
    expect(find.text('4'), findsNothing);
    // D badges (one per drop) + the indented tertiary bracket.
    expect(find.byKey(const Key('dropBadge')), findsNWidgets(2));
    expect(find.byKey(const Key('dropBracket')), findsNWidgets(2));
  });

  testWidgets('"Add drop" appends 3.2 under an existing single-drop block', (
    tester,
  ) async {
    const sets = [
      WorkoutSet(id: 's2', weight: 100, reps: 8, isCompleted: true),
      WorkoutSet(
        id: 'd1',
        weight: 85,
        reps: 8,
        setType: SetType.dropset,
        parentSetId: 's2',
        dropIndex: 1,
      ),
    ];

    late WorkoutExercise updated;
    await tester.pumpWidget(
      _host(
        ExerciseCard(
          exercise: _exercise(sets: sets),
          onExerciseUpdated: (e) => updated = e,
          onStartRestTimer: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('addDrop-s2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('addDrop-s2')));
    await tester.pumpAndSettle();

    final drops = updated.sets
        .where((s) => s.setType == SetType.dropset)
        .toList();
    expect(drops.length, 2);
    expect(drops.last.dropIndex, 2);
    expect(drops.last.parentSetId, 's2');
  });

  testWidgets('reverting a dropset parent to "Regular" strips its drops', (
    tester,
  ) async {
    const sets = [
      WorkoutSet(id: 's2', weight: 100, reps: 8, isCompleted: true),
      WorkoutSet(
        id: 'd1',
        weight: 85,
        reps: 8,
        setType: SetType.dropset,
        parentSetId: 's2',
        dropIndex: 1,
      ),
    ];

    late WorkoutExercise updated;
    await tester.pumpWidget(
      _host(
        ExerciseCard(
          exercise: _exercise(sets: sets),
          onExerciseUpdated: (e) => updated = e,
          onStartRestTimer: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Row 0 is the dropset parent.
    await _pickType(tester, 0, 'Regular');

    expect(updated.sets.length, 1);
    expect(updated.sets.single.id, 's2');
    expect(updated.sets.where((s) => s.setType == SetType.dropset), isEmpty);
  });

  testWidgets('tapping the Set badge opens the type menu; picking Failure shows '
      'an F badge', (tester) async {
    late WorkoutExercise updated;
    await tester.pumpWidget(
      _host(
        ExerciseCard(
          exercise: _exercise(),
          onExerciseUpdated: (e) => updated = e,
          onStartRestTimer: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No F badge to start (all regular/working sets).
    expect(find.byKey(const Key('failureBadge')), findsNothing);

    // The Set badge IS the trigger: tapping row 1's badge opens the menu.
    await tester.tap(find.byKey(const Key('setTypeButton')).at(1));
    await tester.pumpAndSettle();
    expect(find.text('Failure'), findsOneWidget);
    await tester.tap(find.text('Failure').last);
    await tester.pumpAndSettle();

    // Failure == RIR 0: the SAME (final) exercise update carries BOTH the
    // failure type and RIR 0 (rpe 10). This is the production ExerciseCard path
    // the keyboard F key also routes through — a regression guard against the
    // type and effort persisting as two racing writes.
    expect(updated.sets[1].setType, SetType.failure);
    expect(updated.sets[1].rpe, 10);
  });

  testWidgets(
    'typing reps then tapping F preserves the uncommitted reps draft',
    (tester) async {
      WorkoutExercise? updated;
      await tester.pumpWidget(
        _host(
          _ExerciseCardHarness(
            exercise: _exercise(
              sets: const [WorkoutSet(id: 's0', weight: 7.5, reps: 0)],
            ),
            onUpdated: (exercise) => updated = exercise,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('repsKeyboardDigit1')));
      await tester.tap(find.byKey(const Key('repsKeyboardDigit2')));
      await tester.pump();

      // Before this regression fix the card handled F from its older persisted
      // set (reps: 0), rebuilt the row, and replaced the typed 12 with 0.
      await tester.tap(find.byKey(const Key('repsKeyboardFailure')));
      await tester.pumpAndSettle();

      expect(updated, isNotNull);
      expect(updated!.sets.single.reps, 12);
      expect(updated!.sets.single.setType, SetType.failure);
      expect(updated!.sets.single.rpe, 10);
      expect(find.text('12'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping F on an untouched duration prefill does not persist it',
    (tester) async {
      WorkoutExercise? updated;
      const exercise = WorkoutExercise(
        id: 'plank-row',
        exercise: Exercise(
          name: 'Plank',
          muscles: ['Abs'],
          loggingMode: ExerciseLoggingMode.durationOnly,
        ),
        sets: [WorkoutSet(id: 's0', weight: 0, reps: 0)],
        previousSessionSets: [WorkoutSet(id: 'p0', weight: 0, reps: 90)],
      );
      await tester.pumpWidget(
        _host(
          _ExerciseCardHarness(
            exercise: exercise,
            onUpdated: (value) => updated = value,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Merely opening Time must not turn the ghosted 01:30 previous value
      // into a draft. The keyboard F shortcut still changes type and effort.
      await tester.tap(find.byKey(const ValueKey('durationField')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('repsKeyboardFailure')));
      await tester.pumpAndSettle();

      expect(updated, isNotNull);
      expect(updated!.sets.single.reps, 0);
      expect(updated!.sets.single.setType, SetType.failure);
      expect(updated!.sets.single.rpe, 10);
    },
  );

  testWidgets('typing a duration then tapping F preserves the new duration', (
    tester,
  ) async {
    WorkoutExercise? updated;
    const exercise = WorkoutExercise(
      id: 'run-row',
      exercise: Exercise(
        name: 'Run',
        muscles: ['Legs'],
        kind: ExerciseKind.cardio,
        loggingMode: ExerciseLoggingMode.distanceDuration,
      ),
      sets: [WorkoutSet(id: 's0', weight: 0, reps: 0)],
    );
    await tester.pumpWidget(
      _host(
        _ExerciseCardHarness(
          exercise: exercise,
          onUpdated: (value) => updated = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('durationField')));
    await tester.pumpAndSettle();
    for (final digit in ['1', '2', '0']) {
      await tester.tap(find.byKey(Key('repsKeyboardDigit$digit')));
    }
    await tester.pump();
    await tester.tap(find.byKey(const Key('repsKeyboardFailure')));
    await tester.pumpAndSettle();

    expect(updated, isNotNull);
    expect(updated!.sets.single.reps, 80); // 01:20
    expect(updated!.sets.single.setType, SetType.failure);
    expect(updated!.sets.single.rpe, 10);
  });

  testWidgets(
    'picking Failure on a dropset parent strips drops AND logs RIR 0',
    (tester) async {
      const sets = [
        WorkoutSet(id: 's2', weight: 100, reps: 8, isCompleted: true),
        WorkoutSet(
          id: 'd1',
          weight: 85,
          reps: 8,
          setType: SetType.dropset,
          parentSetId: 's2',
          dropIndex: 1,
        ),
      ];

      late WorkoutExercise updated;
      await tester.pumpWidget(
        _host(
          ExerciseCard(
            exercise: _exercise(sets: sets),
            onExerciseUpdated: (e) => updated = e,
            onStartRestTimer: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Row 0 is the dropset parent. Failure strips its drops AND, in the same
      // update, marks the parent failure with RIR 0.
      await _pickType(tester, 0, 'Failure');

      expect(updated.sets.where((s) => s.setType == SetType.dropset), isEmpty);
      final parent = updated.sets.firstWhere((s) => s.id == 's2');
      expect(parent.setType, SetType.failure);
      expect(parent.rpe, 10);
    },
  );

  testWidgets('Set badge renders W (warm-up), F (failure), D (drop), and a '
      'plain number for a regular set', (tester) async {
    const sets = [
      WorkoutSet(id: 'w1', weight: 40, reps: 12, setType: SetType.warmup),
      WorkoutSet(id: 's1', weight: 80, reps: 10),
      WorkoutSet(id: 's2', weight: 100, reps: 8, setType: SetType.failure),
      WorkoutSet(id: 's3', weight: 100, reps: 8, isCompleted: true),
      WorkoutSet(
        id: 'd1',
        weight: 85,
        reps: 8,
        setType: SetType.dropset,
        parentSetId: 's3',
        dropIndex: 1,
      ),
    ];
    await tester.pumpWidget(
      _host(
        ExerciseCard(
          exercise: _exercise(sets: sets),
          onExerciseUpdated: (_) {},
          onStartRestTimer: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Warm-up → W, failure → F, drop → D pills.
    expect(find.byKey(const Key('warmupBadge')), findsOneWidget);
    expect(find.byKey(const Key('failureBadge')), findsOneWidget);
    expect(find.byKey(const Key('dropBadge')), findsOneWidget);
    expect(find.text('W'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);
    expect(find.text('D'), findsOneWidget);

    // Working ordinals advance over every non-warm-up set (incl. failure), but
    // a non-regular type renders its pill instead of the number. So the regular
    // set s1 shows "1"; the failure set s2 takes ordinal 2 yet renders "F"; the
    // parent s3 (ordinal 3) shows the plain "3". Hence visible numbers are 1 & 3.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsNothing);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets(
    'an ungrouped superset set shows an SS badge, not a silent plain ordinal',
    (tester) async {
      // Re-typing a set to "Super set" outside any group leaves displayLabel
      // null. Without an explicit branch the badge fell through to the plain
      // ordinal, hiding the type. It must show a clear "SS" indicator instead.
      const sets = [
        WorkoutSet(id: 's0', weight: 40, reps: 12),
        WorkoutSet(id: 's1', weight: 60, reps: 10, setType: SetType.superset),
        WorkoutSet(id: 's2', weight: 80, reps: 8),
      ];
      await tester.pumpWidget(
        _host(
          ExerciseCard(
            exercise: _exercise(sets: sets),
            onExerciseUpdated: (_) {},
            onStartRestTimer: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The superset row renders the SS pill...
      expect(find.byKey(const Key('supersetBadge')), findsOneWidget);
      expect(find.text('SS'), findsOneWidget);
      // ...and NOT the plain "2" ordinal it would otherwise have shown (s0 -> 1,
      // s1 -> SS, s2 -> 3). The other working ordinals still render.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsNothing);
      expect(find.text('3'), findsOneWidget);
    },
  );

  testWidgets('a GROUPED superset member keeps its round label (no SS badge)', (
    tester,
  ) async {
    // When the card hands down a round label (A1/B2…) for a grouped member,
    // that label wins — the SS fallback only applies to ungrouped supersets.
    // The card derives the label from supersetGroup; here we assert the
    // fallback does NOT fire for a plain ungrouped regular run (no SS at all).
    const sets = [
      WorkoutSet(id: 's0', weight: 40, reps: 12),
      WorkoutSet(id: 's1', weight: 60, reps: 10),
    ];
    await tester.pumpWidget(
      _host(
        ExerciseCard(
          exercise: _exercise(sets: sets),
          onExerciseUpdated: (_) {},
          onStartRestTimer: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('supersetBadge')), findsNothing);
    expect(find.text('SS'), findsNothing);
  });

  testWidgets('completing a drop does not auto-start the full rest timer', (
    tester,
  ) async {
    const sets = [
      WorkoutSet(id: 's2', weight: 100, reps: 8, isCompleted: true),
      WorkoutSet(
        id: 'd1',
        weight: 85,
        reps: 8,
        setType: SetType.dropset,
        parentSetId: 's2',
        dropIndex: 1,
      ),
    ];

    int restCalls = 0;
    await tester.pumpWidget(
      _host(
        ExerciseCard(
          exercise: _exercise(sets: sets),
          onExerciseUpdated: (_) {},
          onStartRestTimer: (_) => restCalls++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Complete the drop (row 1). Drops have little/no rest → no auto-start.
    await tester.tap(find.byTooltip('Mark set 2 as completed'));
    await tester.pump();

    expect(restCalls, 0, reason: 'drops suppress the auto rest timer');
  });
}
