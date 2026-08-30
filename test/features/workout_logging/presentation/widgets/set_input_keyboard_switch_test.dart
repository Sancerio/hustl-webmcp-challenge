import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/set_input_keyboard.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/set_row.dart';

/// Hosts the set rows under a [SetInputKeyboardScope] and mounts the shared
/// keyboard at the bottom when a field is active — the same wiring as
/// ActiveWorkoutScreen, so tapping a field re-targets the open keyboard.
Widget _scoped(SetInputKeyboardController controller, List<Widget> rows) {
  return MaterialApp(
    home: Scaffold(
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, child) => PopScope(
          // Same as ActiveWorkoutScreen: back dismisses the open keyboard first.
          canPop: !controller.isOpen,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            controller.close();
          },
          child: child!,
        ),
        child: SetInputKeyboardScope(
          controller: controller,
          child: Column(
            children: [
              Expanded(child: ListView(children: rows)),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final session = controller.active;
                  if (session == null) return const SizedBox.shrink();
                  // Mirror ActiveWorkoutScreen: a tap outside the keyboard + the
                  // fields (same TapRegion group) dismisses it; stable key so the
                  // keyboard is reused across field switches, not rebuilt.
                  return TapRegion(
                    groupId: setInputTapGroupId,
                    onTapOutside: (_) => controller.close(),
                    child: SetInputKeyboard(
                      key: const ValueKey('setInputKeyboard'),
                      session: session,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() async {
    await GetIt.I.reset(dispose: true);
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    await prefs.setHapticsEnabled(false);
    GetIt.I.registerSingleton<PreferencesService>(prefs);
  });

  Finder weightFieldAt(int index) => find
      .byWidgetPredicate(
        (w) => w is TextField && w.decoration?.suffixText == 'kg',
      )
      .at(index);

  final keyboard = find.byKey(const Key('repsRpeKeyboard'));
  // RIR 2 ≡ RPE 8 (RIR = 10 − RPE); used as the "effort badges are present" probe.
  final rpeNode = find.byKey(const Key('rirKey2'));
  final clearKey = find.byKey(const Key('repsKeyboardClear'));
  final decimalKey = find.byKey(const Key('repsKeyboardDecimal'));

  Finder distanceField() => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.suffixText == 'km',
  );
  final durationField = find.byKey(const ValueKey('durationField'));

  testWidgets(
    'tapping a different field keeps the keyboard open, re-targets it, and '
    'adapts to the field type (reps↔weight)',
    (tester) async {
      final controller = SetInputKeyboardController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _scoped(controller, [
          SetRow(
            setIndex: 0,
            set: const WorkoutSet(id: 's1', weight: 50, reps: 10),
            onSetUpdated: (_) {},
            onSetCompleted: (_) {},
          ),
          SetRow(
            setIndex: 1,
            set: const WorkoutSet(id: 's2', weight: 60, reps: 8),
            onSetUpdated: (_) {},
            onSetCompleted: (_) {},
          ),
        ]),
      );
      await tester.pumpAndSettle();

      // No field active yet → no keyboard.
      expect(keyboard, findsNothing);
      expect(controller.isOpen, isFalse);

      // Tap reps on row 0 → reps keyboard opens: RPE range present, no decimal.
      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();
      expect(keyboard, findsOneWidget);
      expect(controller.active?.kind, SetInputKind.reps);
      expect(rpeNode, findsOneWidget);
      expect(clearKey, findsOneWidget);
      expect(decimalKey, findsNothing);
      final repsRow0Controller = controller.active!.controller;

      // Tap WEIGHT on row 0 while open → keyboard STAYS up, re-targets to weight
      // mode: decimal key appears, the keypad Clear is gone. The RIR badges stay
      // (always present → constant height), so only the corner key swaps.
      await tester.tap(weightFieldAt(0));
      await tester.pumpAndSettle();
      expect(keyboard, findsOneWidget); // never dismissed
      expect(controller.isOpen, isTrue);
      expect(controller.active?.kind, SetInputKind.weight);
      expect(decimalKey, findsOneWidget);
      expect(rpeNode, findsOneWidget);
      expect(clearKey, findsNothing);
      expect(controller.active!.controller, isNot(repsRow0Controller));

      // Tap reps on row 1 → still open, back to reps mode, now targeting a
      // DIFFERENT field than row 0's reps.
      await tester.tap(find.byKey(const Key('repsField-1')));
      await tester.pumpAndSettle();
      expect(keyboard, findsOneWidget);
      expect(controller.active?.kind, SetInputKind.reps);
      expect(rpeNode, findsOneWidget);
      expect(decimalKey, findsNothing);
      expect(controller.active!.controller, isNot(repsRow0Controller));
    },
  );

  testWidgets(
    "switching to another field commits the previous field's typed draft "
    '(no Done tapped)',
    (tester) async {
      final controller = SetInputKeyboardController();
      addTearDown(controller.dispose);
      final persisted = <WorkoutSet>[];

      await tester.pumpWidget(
        _scoped(controller, [
          SetRow(
            setIndex: 0,
            set: const WorkoutSet(id: 's1', weight: 50, reps: 10),
            onSetUpdated: persisted.add,
            onSetCompleted: (_) {},
          ),
        ]),
      );
      await tester.pumpAndSettle();

      // Edit reps: open, type "12" (first digit replaces the existing 10).
      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('repsKeyboardDigit1')));
      await tester.tap(find.byKey(const Key('repsKeyboardDigit2')));
      await tester.pump();

      // Switch to the weight field WITHOUT tapping Done.
      await tester.tap(weightFieldAt(0));
      await tester.pumpAndSettle();

      // The reps draft was persisted (not lost) by the re-target.
      expect(persisted, isNotEmpty);
      expect(persisted.last.reps, 12);
      expect(controller.active?.kind, SetInputKind.weight);
    },
  );

  testWidgets('closing the keyboard (tap-outside) commits the typed draft', (
    tester,
  ) async {
    final controller = SetInputKeyboardController();
    addTearDown(controller.dispose);
    final persisted = <WorkoutSet>[];

    await tester.pumpWidget(
      _scoped(controller, [
        SetRow(
          setIndex: 0,
          set: const WorkoutSet(id: 's1', weight: 50, reps: 10),
          onSetUpdated: persisted.add,
          onSetCompleted: (_) {},
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('repsField-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repsKeyboardDigit7')));
    await tester.pump();

    // Same path as the screen's background-tap handler.
    controller.close();
    await tester.pumpAndSettle();

    expect(controller.isOpen, isFalse);
    expect(persisted, isNotEmpty);
    expect(persisted.last.reps, 7);
  });

  testWidgets(
    'system back dismisses the open keyboard and commits, instead of leaving',
    (tester) async {
      final controller = SetInputKeyboardController();
      addTearDown(controller.dispose);
      final persisted = <WorkoutSet>[];

      await tester.pumpWidget(
        _scoped(controller, [
          SetRow(
            setIndex: 0,
            set: const WorkoutSet(id: 's1', weight: 50, reps: 10),
            onSetUpdated: persisted.add,
            onSetCompleted: (_) {},
          ),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('repsKeyboardDigit9')));
      await tester.pump();
      expect(controller.isOpen, isTrue);

      // Android system back while the keyboard is open.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // First back closed (and committed) the keyboard — didn't leave.
      expect(controller.isOpen, isFalse);
      expect(persisted.last.reps, 9);
      expect(find.byType(SetRow), findsOneWidget);
    },
  );

  testWidgets(
    'selecting RPE only does not promote the prefilled previous-session values',
    (tester) async {
      final controller = SetInputKeyboardController();
      addTearDown(controller.dispose);
      final persisted = <WorkoutSet>[];

      await tester.pumpWidget(
        _scoped(controller, [
          SetRow(
            setIndex: 0,
            // Not yet entered; the row shows a faint prefill of the previous set.
            set: const WorkoutSet(id: 's1', weight: 0, reps: 0),
            previousSet: const WorkoutSet(id: 'p1', weight: 60, reps: 8),
            onSetUpdated: persisted.add,
            onSetCompleted: (_) {},
          ),
        ]),
      );
      await tester.pumpAndSettle();

      // Open the reps keyboard and pick an RPE — do NOT type weight/reps.
      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rirKey2')));
      await tester.pump();
      controller.close(); // blur-save
      await tester.pumpAndSettle();

      // RPE was set, but the prefill (60kg × 8) was NOT logged as real values.
      expect(persisted, isNotEmpty);
      expect(persisted.last.rpe, 8);
      expect(persisted.last.weight, 0);
      expect(persisted.last.reps, 0);
    },
  );

  testWidgets(
    'removing the active row clears the keyboard (no disposed-controller write)',
    (tester) async {
      final controller = SetInputKeyboardController();
      addTearDown(controller.dispose);

      SetRow row(String id, int index) => SetRow(
        key: ValueKey(id),
        setIndex: index,
        set: WorkoutSet(id: id, weight: 50, reps: 10),
        onSetUpdated: (_) {},
        onSetCompleted: (_) {},
      );

      await tester.pumpWidget(
        _scoped(controller, [row('s1', 0), row('s2', 1)]),
      );
      await tester.pumpAndSettle();

      // Open the keyboard on the first row.
      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();
      expect(controller.isOpen, isTrue);

      // Rebuild without the first row → its keyed element disposes while it
      // owned the active session.
      await tester.pumpWidget(_scoped(controller, [row('s2', 0)]));
      await tester.pump(); // run the deferred post-frame close

      expect(controller.isOpen, isFalse);
    },
  );

  testWidgets(
    'a virtualized/removed active row commits its typed draft (not lost)',
    (tester) async {
      final controller = SetInputKeyboardController();
      addTearDown(controller.dispose);
      final persisted = <WorkoutSet>[];

      SetRow row(String id, int index) => SetRow(
        key: ValueKey(id),
        setIndex: index,
        set: WorkoutSet(id: id, weight: 50, reps: 10),
        onSetUpdated: persisted.add,
        onSetCompleted: (_) {},
      );

      await tester.pumpWidget(
        _scoped(controller, [row('s1', 0), row('s2', 1)]),
      );
      await tester.pumpAndSettle();

      // Edit reps on row 0: open + type "12" (first digit replaces the 10).
      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('repsKeyboardDigit1')));
      await tester.tap(find.byKey(const Key('repsKeyboardDigit2')));
      await tester.pump();

      // Remove row 0 (simulating virtualization/removal) WITHOUT tapping Done.
      await tester.pumpWidget(_scoped(controller, [row('s2', 0)]));
      await tester.pump(); // run the deferred post-frame commit

      // The typed draft was persisted, not silently dropped.
      expect(persisted.any((s) => s.id == 's1' && s.reps == 12), isTrue);
    },
  );

  testWidgets(
    'swipe-deleting the active row does not resurrect it via the draft commit',
    (tester) async {
      final controller = SetInputKeyboardController();
      addTearDown(controller.dispose);
      final updates = <WorkoutSet>[];
      var sets = <WorkoutSet>[
        const WorkoutSet(id: 's1', weight: 50, reps: 10),
        const WorkoutSet(id: 's2', weight: 60, reps: 8),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SetInputKeyboardScope(
                controller: controller,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        children: [
                          for (var i = 0; i < sets.length; i++)
                            () {
                              final s = sets[i];
                              return SetRow(
                                key: ValueKey('row-${s.id}'),
                                setIndex: i,
                                set: s,
                                onSetUpdated: updates.add,
                                onSetCompleted: (_) {},
                                onSetDeleted: () => setState(
                                  () => sets = sets
                                      .where((x) => x.id != s.id)
                                      .toList(),
                                ),
                              );
                            }(),
                        ],
                      ),
                    ),
                    ListenableBuilder(
                      listenable: controller,
                      builder: (_, __) {
                        final s = controller.active;
                        if (s == null) return const SizedBox.shrink();
                        return SetInputKeyboard(
                          key: const ValueKey('setInputKeyboard'),
                          session: s,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Edit reps on row 0, then swipe it away WITHOUT tapping Done.
      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('repsKeyboardDigit1')));
      await tester.tap(find.byKey(const Key('repsKeyboardDigit2')));
      await tester.pump();

      await tester.drag(
        find.byKey(const ValueKey('s1')), // the Dismissible (keyed by set id)
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();
      await tester.pump(); // run any deferred post-frame callback

      // s1 was deleted and NOT brought back by a dispose-time draft commit.
      expect(sets.any((s) => s.id == 's1'), isFalse);
      expect(updates.any((s) => s.id == 's1'), isFalse);
    },
  );

  testWidgets('cardio distance + time use the custom keyboard; distance "Next" '
      're-targets to Time', (tester) async {
    final controller = SetInputKeyboardController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _scoped(controller, [
        const SetRow(
          setIndex: 0,
          set: WorkoutSet(id: 's1', weight: 0, reps: 0),
          onSetUpdated: _ignoreSet,
          onSetCompleted: _ignoreSet,
          exerciseKind: ExerciseKind.cardio,
          loggingMode: ExerciseLoggingMode.distanceDuration,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    // Both cardio fields are read-only proxies for the SAME custom keyboard —
    // no native keyboard anywhere.
    final km = tester.widget<TextField>(distanceField());
    expect(km.readOnly, isTrue);
    expect(km.keyboardType, TextInputType.none);
    expect(tester.widget<TextField>(durationField).readOnly, isTrue);

    // Tap distance → custom keyboard opens in distance mode: decimal key,
    // NO RIR row (cardio has no effort), and a "Next" key (advance to Time).
    await tester.tap(distanceField());
    await tester.pumpAndSettle();
    expect(keyboard, findsOneWidget);
    expect(controller.active?.kind, SetInputKind.distance);
    expect(decimalKey, findsOneWidget);
    expect(rpeNode, findsNothing);
    expect(find.byKey(const Key('repsKeyboardNext')), findsOneWidget);
    expect(find.byKey(const Key('repsKeyboardDone')), findsNothing);

    // Tap "Next" → keyboard stays open, now targeting the Time (duration)
    // field: Clear key (no decimal), no RIR, and the primary key flips to
    // "Done" (Time is the last field).
    await tester.tap(find.byKey(const Key('repsKeyboardNext')));
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);
    expect(controller.active?.kind, SetInputKind.duration);
    expect(clearKey, findsOneWidget);
    expect(decimalKey, findsNothing);
    expect(rpeNode, findsNothing);
    expect(find.byKey(const Key('repsKeyboardDone')), findsOneWidget);
    expect(find.byKey(const Key('repsKeyboardNext')), findsNothing);
  });

  testWidgets(
    'switching weight↔reps re-targets the keyboard in place (State reused, '
    'not torn down) so the keypad does not flicker',
    (tester) async {
      final controller = SetInputKeyboardController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _scoped(controller, [
          const SetRow(
            setIndex: 0,
            set: WorkoutSet(id: 's1', weight: 50, reps: 10),
            onSetUpdated: _ignoreSet,
            onSetCompleted: _ignoreSet,
          ),
        ]),
      );
      await tester.pumpAndSettle();

      // Open on reps (RPE range present, no decimal).
      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();
      expect(rpeNode, findsOneWidget);
      final stateOnReps = tester.state(find.byType(SetInputKeyboard));

      // Switch to weight: same State instance → the widget was re-targeted in
      // place via didUpdateWidget, NOT disposed and rebuilt (the old jank).
      await tester.tap(weightFieldAt(0));
      await tester.pumpAndSettle();
      final stateOnWeight = tester.state(find.byType(SetInputKeyboard));
      expect(identical(stateOnReps, stateOnWeight), isTrue);
      // And it adapted: decimal key now present (the RIR badges stay — always
      // present for constant height).
      expect(decimalKey, findsOneWidget);
      expect(rpeNode, findsOneWidget);

      // Switch back to reps: still the same State instance.
      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();
      expect(
        identical(stateOnReps, tester.state(find.byType(SetInputKeyboard))),
        isTrue,
      );
      expect(rpeNode, findsOneWidget);
    },
  );

  testWidgets('weight "Next" key re-targets the keyboard to reps (stays open)', (
    tester,
  ) async {
    final controller = SetInputKeyboardController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _scoped(controller, [
        const SetRow(
          setIndex: 0,
          set: WorkoutSet(id: 's1', weight: 50, reps: 10),
          onSetUpdated: _ignoreSet,
          onSetCompleted: _ignoreSet,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    // Open on weight → primary key reads "Next" (not "Done").
    await tester.tap(weightFieldAt(0));
    await tester.pumpAndSettle();
    expect(controller.active?.kind, SetInputKind.weight);
    expect(find.byKey(const Key('repsKeyboardNext')), findsOneWidget);
    expect(find.byKey(const Key('repsKeyboardDone')), findsNothing);

    // Tap Next → keyboard stays open, now targeting reps; key flips to "Done".
    await tester.tap(find.byKey(const Key('repsKeyboardNext')));
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);
    expect(controller.active?.kind, SetInputKind.reps);
    expect(find.byKey(const Key('repsKeyboardDone')), findsOneWidget);
    expect(find.byKey(const Key('repsKeyboardNext')), findsNothing);
  });

  testWidgets(
    'tapping a non-field control (the ✓ check) outside the keyboard dismisses it',
    (tester) async {
      final controller = SetInputKeyboardController();
      addTearDown(controller.dispose);
      final completed = <WorkoutSet>[];

      await tester.pumpWidget(
        _scoped(controller, [
          SetRow(
            setIndex: 0,
            set: const WorkoutSet(id: 's1', weight: 50, reps: 10),
            onSetUpdated: _ignoreSet,
            onSetCompleted: completed.add,
          ),
        ]),
      );
      await tester.pumpAndSettle();

      // Open the keyboard on reps.
      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();
      expect(keyboard, findsOneWidget);
      expect(controller.isOpen, isTrue);

      // Tap the ✓ completion button — a control OUTSIDE the keyboard+fields
      // tap group. It should complete the set AND dismiss the keyboard.
      await tester.tap(find.byTooltip('Mark set 1 as completed'));
      await tester.pumpAndSettle();

      expect(completed, isNotEmpty);
      expect(controller.isOpen, isFalse);
      expect(keyboard, findsNothing);
    },
  );

  testWidgets(
    'tapping the RIR "?" opens the explainer with a link to the full guide',
    (tester) async {
      final controller = SetInputKeyboardController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _scoped(controller, [
          const SetRow(
            setIndex: 0,
            set: WorkoutSet(id: 's1', weight: 50, reps: 10),
            onSetUpdated: _ignoreSet,
            onSetCompleted: _ignoreSet,
          ),
        ]),
      );
      await tester.pumpAndSettle();

      // Open the keyboard, then tap the "?" help.
      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rirHelp')));
      await tester.pumpAndSettle();

      // The explainer sheet is shown, with a link to the full Learn guide.
      expect(find.text('RIR — reps in reserve'), findsOneWidget);
      expect(find.byKey(const Key('rirReadMore')), findsOneWidget);
    },
  );

  testWidgets('the primary action key sits in the RIGHT column, clear of 0 '
      '(no mis-tap of Done while reaching for 0)', (tester) async {
    final controller = SetInputKeyboardController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _scoped(controller, [
        const SetRow(
          setIndex: 0,
          set: WorkoutSet(id: 's1', weight: 50, reps: 10),
          onSetUpdated: _ignoreSet,
          onSetCompleted: _ignoreSet,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('repsField-0')));
    await tester.pumpAndSettle();

    // Reps is the last field, so the primary key reads "Done".
    final zero = tester.getRect(find.byKey(const Key('repsKeyboardDigit0')));
    final done = tester.getRect(find.byKey(const Key('repsKeyboardDone')));

    // The action is a key in the right-hand column — entirely right of 0, so a
    // low reach for 0 can never land on it. The W / F tags sit there too.
    expect(done.left, greaterThanOrEqualTo(zero.right));
    expect(find.byKey(const Key('repsKeyboardWarmup')), findsOneWidget);
    expect(find.byKey(const Key('repsKeyboardFailure')), findsOneWidget);
    expect(find.byKey(const Key('repsKeyboardCollapse')), findsOneWidget);
  });

  testWidgets('the keypad W tag toggles the set to a warm-up set', (
    tester,
  ) async {
    final controller = SetInputKeyboardController();
    addTearDown(controller.dispose);
    SetType? updatedType;

    await tester.pumpWidget(
      _scoped(controller, [
        SetRow(
          setIndex: 0,
          set: const WorkoutSet(id: 's1', weight: 50, reps: 10),
          onSetUpdated: (s) => updatedType = s.setType,
          onSetCompleted: _ignoreSet,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('repsField-0')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('repsKeyboardWarmup')));
    await tester.pumpAndSettle();

    expect(updatedType, SetType.warmup);
  });

  testWidgets('the keypad F tag marks failure and pre-selects RIR 0', (
    tester,
  ) async {
    final controller = SetInputKeyboardController();
    addTearDown(controller.dispose);
    WorkoutSet? updated;

    await tester.pumpWidget(
      _scoped(controller, [
        SetRow(
          setIndex: 0,
          set: const WorkoutSet(id: 's1', weight: 50, reps: 10),
          onSetUpdated: (s) => updated = s,
          onSetCompleted: _ignoreSet,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('repsField-0')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('repsKeyboardFailure')));
    await tester.pumpAndSettle();

    // F (to failure) == RIR 0 (no reps left): the set is typed failure AND its
    // effort is set to RIR 0 (rpe 10) in one tap.
    expect(updated?.setType, SetType.failure);
    expect(updated?.rpe, 10);
  });

  testWidgets('a reps field with a logged effort shows its RIR tag', (
    tester,
  ) async {
    final controller = SetInputKeyboardController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _scoped(controller, [
        // rpe 4 ≡ RIR 6 → the tag reads "6+", a label that can't collide with a
        // rep count or set index in this row.
        const SetRow(
          setIndex: 0,
          set: WorkoutSet(id: 's1', weight: 50, reps: 10, rpe: 4),
          onSetUpdated: _ignoreSet,
          onSetCompleted: _ignoreSet,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    // The keyboard is closed (no keypad mounted), so "6+" can only be the tag.
    expect(find.text('6+'), findsOneWidget);
  });
}

// Top-level no-op so the cardio rows above can stay `const` (closures aren't
// const-constructible).
void _ignoreSet(WorkoutSet _) {}
