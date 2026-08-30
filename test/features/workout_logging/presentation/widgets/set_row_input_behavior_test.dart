import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/data/repositories/mock_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/duration_field.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/exercise_card.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/set_input_keyboard.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/set_row.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/set_row_completion_button.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

/// Hosts [child] under a [SetInputKeyboardScope] with the shared custom keyboard
/// docked at the bottom — the same wiring as ActiveWorkoutScreen. Cardio
/// distance/Time and strength weight/reps all drive this single keyboard.
Widget _scopedHost(SetInputKeyboardController controller, Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SetInputKeyboardScope(
        controller: controller,
        child: Column(
          children: [
            Expanded(child: ListView(children: [child])),
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final session = controller.active;
                if (session == null) return const SizedBox.shrink();
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
  );
}

Widget _wrapWithOutsideTap(Widget child) => MaterialApp(
  home: Scaffold(
    body: Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: const SizedBox(),
          ),
        ),
        Center(child: child),
      ],
    ),
  ),
);

class _SetRowHost extends StatefulWidget {
  const _SetRowHost({required this.onDeleted});

  final VoidCallback onDeleted;

  @override
  State<_SetRowHost> createState() => _SetRowHostState();
}

class _SetRowHostState extends State<_SetRowHost> {
  bool _show = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      home: Scaffold(
        body: ListView(
          children: [
            if (_show)
              SetRow(
                setIndex: 0,
                set: const WorkoutSet(id: 's1', weight: 0, reps: 0),
                onSetUpdated: (_) {},
                onSetCompleted: (_) {},
                dismissThreshold: 0.1,
                onSetDeleted: () {
                  setState(() => _show = false);
                  widget.onDeleted();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ImmediatePrRepo extends MockWorkoutRepository {
  _ImmediatePrRepo(this._result);

  final bool _result;
  int calls = 0;

  @override
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  }) async {
    calls++;
    return _result;
  }
}

class _DurationFieldHost extends StatefulWidget {
  const _DurationFieldHost({super.key, this.initialValue});

  final int? initialValue;

  @override
  State<_DurationFieldHost> createState() => _DurationFieldHostState();
}

class _DurationFieldHostState extends State<_DurationFieldHost> {
  int? value;
  int? lastSubmitted;
  int? lastChanged;

  @override
  void initState() {
    super.initState();
    value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: DurationField(
            key: const ValueKey('durationField'),
            valueSeconds: value,
            onChanged: (seconds) {
              setState(() {
                lastChanged = seconds;
              });
            },
            onSubmitted: (seconds) {
              setState(() {
                lastSubmitted = seconds;
                value = seconds;
              });
            },
          ),
        ),
      ),
    );
  }
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

  group('SetRow input behavior', () {
    testWidgets(
      'does not call onSetUpdated on every keystroke; updates on editing complete',
      (tester) async {
        int updateCalls = 0;
        int completeCalls = 0;

        const initial = WorkoutSet(id: '1', weight: 0.0, reps: 0);

        await tester.pumpWidget(
          _wrap(
            SetRow(
              setIndex: 0,
              set: initial,
              onSetUpdated: (_) => updateCalls++,
              onSetCompleted: (_) => completeCalls++,
            ),
          ),
        );

        // Find the two text fields (weight then reps)
        final textFields = find.byType(TextField);
        expect(textFields, findsNWidgets(2));

        // Enter weight but do not submit yet
        await tester.enterText(textFields.at(0), '42.5');
        await tester.pump();

        // onChanged should not propagate updates immediately
        expect(updateCalls, 0);
        expect(completeCalls, 0);

        // Commit weight field (simulate pressing Next)
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();
        expect(updateCalls, 1);
        expect(completeCalls, 0);

        // Enter reps through the custom reps keyboard and commit.
        await tester.tap(find.byKey(const Key('repsField-0')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('repsKeyboardDigit8')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('repsKeyboardDone')));
        await tester.pumpAndSettle();
        expect(updateCalls, 2);
        expect(completeCalls, 1);
      },
    );

    testWidgets(
      'tapping complete does not call onSetUpdated from blur; persists via onSetCompleted',
      (tester) async {
        int updateCalls = 0;
        WorkoutSet? completed;

        const initial = WorkoutSet(id: '1', weight: 0.0, reps: 0);

        await tester.pumpWidget(
          _wrap(
            SetRow(
              setIndex: 0,
              set: initial,
              onSetUpdated: (_) => updateCalls++,
              onSetCompleted: (s) => completed = s,
            ),
          ),
        );

        final weightField = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.suffixText == 'kg',
        );
        expect(weightField, findsOneWidget);

        await tester.tap(weightField);
        await tester.pump();
        await tester.enterText(weightField, '50');
        await tester.pump();

        await tester.tap(find.byIcon(Icons.check_circle_outline));
        await tester.pump();

        expect(updateCalls, 0);
        expect(completed, isNotNull);
        expect(completed!.isCompleted, isTrue);
        expect(completed!.weight, 50);
      },
    );

    testWidgets('editing a completed set re-saves via onSetCompleted', (
      tester,
    ) async {
      WorkoutSet? completed;
      int completeCalls = 0;

      const initial = WorkoutSet(
        id: '1',
        weight: 20,
        reps: 5,
        isCompleted: true,
      );

      await tester.pumpWidget(
        _wrap(
          SetRow(
            setIndex: 0,
            set: initial,
            onSetUpdated: (_) {},
            onSetCompleted: (s) {
              completeCalls++;
              completed = s;
            },
          ),
        ),
      );

      final weightField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.suffixText == 'kg',
      );
      expect(weightField, findsOneWidget);

      await tester.enterText(weightField, '25');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();

      expect(completeCalls, 1);
      expect(completed?.weight, 25);
    });

    testWidgets('prefilled values highlight after editing completes', (
      tester,
    ) async {
      // Previous set provides placeholder values
      const previous = WorkoutSet(id: 'p1', weight: 50, reps: 10);
      WorkoutSet current = const WorkoutSet(
        id: 's1',
        weight: 0.0,
        reps: 0,
        isCompleted: false,
      );

      await tester.pumpWidget(
        _wrap(
          SetRow(
            setIndex: 0,
            set: current,
            previousSet: previous,
            onSetUpdated: (s) => current = s,
            onSetCompleted: (_) {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      final weightField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.suffixText == 'kg',
      );
      expect(weightField, findsOneWidget);

      final context = tester.element(weightField);
      final theme = Theme.of(context);

      // Initially uses placeholder color
      TextField fieldWidget = tester.widget(weightField);
      expect(
        fieldWidget.style?.color,
        theme.colorScheme.onSurface.withValues(alpha: 0.35),
      );

      // Commit editing even with same value
      await tester.enterText(weightField, '50');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();

      // Color should now be the highlighted onSurface color
      fieldWidget = tester.widget(weightField);
      expect(fieldWidget.style?.color, theme.colorScheme.onSurface);
    });

    testWidgets('resetting set to zero preserves confirmed styling', (
      tester,
    ) async {
      const previous = WorkoutSet(id: 'p1', weight: 50, reps: 10);
      WorkoutSet current = const WorkoutSet(
        id: 's1',
        weight: 50,
        reps: 10,
        isCompleted: false,
      );

      Widget build() => _wrap(
        SetRow(
          key: const ValueKey('row'),
          setIndex: 0,
          set: current,
          previousSet: previous,
          onSetUpdated: (s) => current = s,
          onSetCompleted: (_) {},
        ),
      );

      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      final weightField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.suffixText == 'kg',
      );
      final context = tester.element(weightField);
      final theme = Theme.of(context);

      TextField fieldWidget = tester.widget(weightField);
      expect(fieldWidget.style?.color, theme.colorScheme.onSurface);

      // Parent updates set with zero values
      current = const WorkoutSet(
        id: 's1',
        weight: 0,
        reps: 0,
        isCompleted: false,
      );
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      fieldWidget = tester.widget(weightField);
      expect(fieldWidget.style?.color, theme.colorScheme.onSurface);
    });

    testWidgets('manually entering zero after confirmation keeps highlight', (
      tester,
    ) async {
      const previous = WorkoutSet(id: 'p1', weight: 0, reps: 0);
      WorkoutSet current = const WorkoutSet(
        id: 's1',
        weight: 0,
        reps: 0,
        isCompleted: false,
      );

      Widget build() => _wrap(
        SetRow(
          setIndex: 0,
          set: current,
          previousSet: previous,
          onSetUpdated: (s) => current = s,
          onSetCompleted: (_) {},
        ),
      );

      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      final weightField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.suffixText == 'kg',
      );
      final context = tester.element(weightField);
      final theme = Theme.of(context);

      // Confirm a non-zero value
      await tester.enterText(weightField, '5');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      TextField fieldWidget = tester.widget(weightField);
      expect(fieldWidget.style?.color, theme.colorScheme.onSurface);

      // Enter zero and commit
      await tester.enterText(weightField, '0');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      current = const WorkoutSet(
        id: 's1',
        weight: 0,
        reps: 0,
        isCompleted: false,
      );
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      fieldWidget = tester.widget(weightField);
      expect(fieldWidget.style?.color, theme.colorScheme.onSurface);
    });

    testWidgets('clearing weight does not auto-reinstate previous value', (
      tester,
    ) async {
      const previous = WorkoutSet(id: 'p1', weight: 12.5, reps: 10);
      WorkoutSet current = const WorkoutSet(
        id: 's1',
        weight: 0,
        reps: 0,
        isCompleted: false,
      );

      await tester.pumpWidget(
        _wrap(
          SetRow(
            setIndex: 0,
            set: current,
            previousSet: previous,
            onSetUpdated: (s) => current = s,
            onSetCompleted: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final weightField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.suffixText == 'kg',
      );
      expect(weightField, findsOneWidget);

      // Clear the field and ensure the UI doesn't force the previous value back.
      await tester.enterText(weightField, '');
      await tester.pump();
      final afterClear = tester.widget<TextField>(weightField);
      expect(afterClear.controller?.text, '');

      // Now type 0 and commit; should persist 0 (useful for bodyweight exercises).
      await tester.enterText(weightField, '0');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(current.weight, 0);
    });

    testWidgets('clearing reps then disposing does not throw', (tester) async {
      const previous = WorkoutSet(id: 'p1', weight: 12.5, reps: 10);
      const current = WorkoutSet(
        id: 's1',
        weight: 0,
        reps: 0,
        isCompleted: false,
      );

      await tester.pumpWidget(
        _wrap(
          SetRow(
            setIndex: 0,
            set: current,
            previousSet: previous,
            onSetUpdated: (_) {},
            onSetCompleted: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));

      await tester.tap(textFields.at(1));
      await tester.pump();
      await tester.enterText(textFields.at(1), '8');
      await tester.pump();

      await tester.enterText(textFields.at(1), '');
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('completed set shows tinted background and left accent', (
      tester,
    ) async {
      const set = WorkoutSet(id: 's1', weight: 50, reps: 10, isCompleted: true);

      await tester.pumpWidget(
        _wrap(
          SetRow(
            setIndex: 0,
            set: set,
            previousSet: null,
            onSetUpdated: (_) {},
            onSetCompleted: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final animatedContainerFinder = find.byWidgetPredicate(
        (widget) => widget is AnimatedContainer,
      );
      expect(animatedContainerFinder, findsOneWidget);

      final container = tester.widget<AnimatedContainer>(
        animatedContainerFinder,
      );
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration, isNotNull);
      expect(decoration!.color, isNotNull);
      expect(find.byKey(const Key('completedLeftAccent')), findsOneWidget);
    });

    testWidgets('completion button uses the fast fade-scale transition', (
      tester,
    ) async {
      var completed = false;

      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) => SetRowCompletionButton(
              setIndex: 0,
              isCompleted: completed,
              isPr: false,
              onComplete: () => setState(() => completed = true),
              onUncomplete: () => setState(() => completed = false),
            ),
          ),
        ),
      );

      final switcher = tester.widget<AnimatedSwitcher>(
        find.byType(AnimatedSwitcher),
      );
      expect(switcher.duration, AppMotion.fast);
      expect(switcher.reverseDuration, AppMotion.fast);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pump();

      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AnimatedSwitcher),
          matching: find.byType(ScaleTransition),
        ),
        findsWidgets,
      );
      final transitionScales = tester
          .widgetList<ScaleTransition>(
            find.descendant(
              of: find.byType(AnimatedSwitcher),
              matching: find.byType(ScaleTransition),
            ),
          )
          .map((transition) => transition.scale.value);
      expect(transitionScales, contains(closeTo(0.97, 0.001)));

      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('completion button reduces the transition to opacity only', (
      tester,
    ) async {
      var completed = false;

      await tester.pumpWidget(
        _wrap(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: StatefulBuilder(
              builder: (context, setState) => SetRowCompletionButton(
                setIndex: 0,
                isCompleted: completed,
                isPr: false,
                onComplete: () => setState(() => completed = true),
                onUncomplete: () => setState(() => completed = false),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(AnimatedSwitcher),
          matching: find.byType(ScaleTransition),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(AnimatedSwitcher),
          matching: find.byType(FadeTransition),
        ),
        findsWidgets,
      );

      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('completing set highlights prefilled inputs', (tester) async {
      const previous = WorkoutSet(id: 'p', weight: 50, reps: 10);

      await tester.pumpWidget(
        _wrap(
          SetRow(
            setIndex: 0,
            set: const WorkoutSet(
              id: 's2',
              weight: 0,
              reps: 0,
              isCompleted: false,
            ),
            previousSet: previous,
            onSetUpdated: (_) {},
            onSetCompleted: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final weightField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.suffixText == 'kg',
      );
      final repsField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.suffixText == null,
      );
      final theme = Theme.of(tester.element(weightField));

      TextField weightWidget = tester.widget(weightField);
      TextField repsWidget = tester.widget(repsField);
      expect(
        weightWidget.style?.color,
        theme.colorScheme.onSurface.withValues(alpha: 0.35),
      );
      expect(
        repsWidget.style?.color,
        theme.colorScheme.onSurface.withValues(alpha: 0.35),
      );

      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pump();

      weightWidget = tester.widget(weightField);
      repsWidget = tester.widget(repsField);
      expect(weightWidget.style?.color, theme.colorScheme.onSurface);
      expect(repsWidget.style?.color, theme.colorScheme.onSurface);
    });

    testWidgets('completing a set delegates to onSetCompleted; SetRow emits no '
        'direct haptic (the parent ExerciseCard owns the completion buzz)', (
      tester,
    ) async {
      final prefs = GetIt.I<PreferencesService>();
      await prefs.setHapticsEnabled(true);

      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      WorkoutSet? completed;
      await tester.pumpWidget(
        _wrap(
          SetRow(
            setIndex: 0,
            set: const WorkoutSet(id: '1', weight: 0.0, reps: 0),
            onSetUpdated: (_) {},
            onSetCompleted: (s) => completed = s,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pump();

      // The completion is delegated up; the single completion haptic (and the
      // PR celebrate) is fired centrally by ExerciseCard, not by SetRow.
      expect(completed, isNotNull);
      final vibrates = calls
          .where((call) => call.method == 'HapticFeedback.vibrate')
          .toList();
      expect(vibrates, isEmpty);
    });

    testWidgets('no haptic feedback when disabled', (tester) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(
        _wrap(
          SetRow(
            setIndex: 0,
            set: const WorkoutSet(id: '1', weight: 0.0, reps: 0),
            onSetUpdated: (_) {},
            onSetCompleted: (_) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pump();

      final vibrates = calls.where(
        (call) => call.method == 'HapticFeedback.vibrate',
      );
      expect(vibrates, isEmpty);
    });

    testWidgets('focus traversal moves weight to reps and commits values', (
      tester,
    ) async {
      const set1 = WorkoutSet(id: 's1', weight: 0, reps: 0);
      const set2 = WorkoutSet(id: 's2', weight: 0, reps: 0);

      WorkoutSet updated1 = set1;
      WorkoutSet updated2 = set2;
      var set1Completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SetRow(
                  setIndex: 0,
                  set: set1,
                  previousSet: null,
                  onSetUpdated: (set) => updated1 = set,
                  onSetCompleted: (_) {
                    set1Completed = true;
                  },
                ),
                SetRow(
                  setIndex: 1,
                  set: set2,
                  previousSet: null,
                  onSetUpdated: (set) => updated2 = set,
                  onSetCompleted: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final weightFields = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.suffixText == 'kg',
      );
      final repsFields = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.suffixText == null,
      );
      expect(weightFields, findsNWidgets(2));
      expect(repsFields, findsNWidgets(2));

      await tester.tap(weightFields.first);
      await tester.pump();
      await tester.enterText(weightFields.first, '50');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();

      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('repsKeyboardDigit1')));
      await tester.tap(find.byKey(const Key('repsKeyboardDigit0')));
      await tester.tap(find.byKey(const Key('repsKeyboardDone')));
      await tester.pumpAndSettle();
      expect(updated1.weight, 50);
      expect(updated1.reps, 10);
      expect(set1Completed, isTrue);

      await tester.tap(weightFields.at(1));
      await tester.pump();
      await tester.enterText(weightFields.at(1), '55');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(updated2.weight, 55);
    });

    testWidgets(
      'tapping the Set badge opens the type menu and selecting a type '
      'updates the set',
      (tester) async {
        WorkoutSet? updated;

        await tester.pumpWidget(
          _wrap(
            SetRow(
              setIndex: 0,
              set: const WorkoutSet(id: 's1', weight: 0, reps: 0),
              onSetUpdated: (set) => updated = set,
              onSetCompleted: (_) {},
            ),
          ),
        );

        // A regular set's badge is the plain ordinal "1" (no icon) — the Strong
        // redesign drops the colored trigger glyph for working sets.
        expect(find.text('1'), findsOneWidget);
        expect(find.byIcon(Icons.more_horiz), findsNothing);

        // The Set badge IS the set-type selector now (Strong-style): tap it to
        // open the menu. It keeps the stable `setTypeButton` key.
        await tester.tap(find.byKey(const Key('setTypeButton')));
        await tester.pumpAndSettle();

        // The menu lists every type with its leading icon (Regular's is the
        // `more_horiz` placeholder).
        expect(find.byIcon(Icons.more_horiz), findsOneWidget);
        expect(find.byIcon(Icons.wb_sunny), findsOneWidget);
        expect(find.byIcon(Icons.close), findsOneWidget);
        expect(find.byIcon(Icons.link), findsOneWidget);
        expect(find.byIcon(Icons.arrow_downward), findsOneWidget);

        await tester.tap(find.text('Super set').last);
        await tester.pumpAndSettle();

        expect(updated, isNotNull);
        expect(updated!.setType, SetType.superset);
      },
    );

    testWidgets('standalone dropset rows show a D badge', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SetRow(
            setIndex: 0,
            set: const WorkoutSet(
              id: 's1',
              weight: 80,
              reps: 8,
              setType: SetType.dropset,
            ),
            onSetUpdated: (_) {},
            onSetCompleted: (_) {},
          ),
        ),
      );

      expect(find.byKey(const Key('dropBadge')), findsOneWidget);
      expect(find.text('D'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('completed set edits persist on focus loss', (tester) async {
      WorkoutSet? lastCompleted;
      WorkoutSet current = const WorkoutSet(
        id: 's1',
        weight: 20,
        reps: 5,
        isCompleted: true,
      );
      late StateSetter setStateHost;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setStateHost = setState;
            return _wrapWithOutsideTap(
              SetRow(
                key: const ValueKey('row'),
                setIndex: 0,
                set: current,
                onSetUpdated: (_) {},
                onSetCompleted: (set) => lastCompleted = set,
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      final weightField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.suffixText == 'kg',
      );
      await tester.tap(weightField);
      await tester.pump();
      await tester.enterText(weightField, '25');
      await tester.pump();

      await tester.tapAt(const Offset(5, 5));
      await tester.pump();

      expect(lastCompleted, isNotNull);
      expect(lastCompleted!.isCompleted, isTrue);
      expect(lastCompleted!.weight, 25);

      current = lastCompleted!;
      setStateHost(() {});
      await tester.pump();

      final fieldWidget = tester.widget<TextField>(weightField);
      expect(fieldWidget.controller?.text, '25');
    });

    testWidgets('completed zero weight stays visible with previous values', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SetRow(
            setIndex: 0,
            set: const WorkoutSet(
              id: 'set-1',
              weight: 0,
              reps: 10,
              isCompleted: true,
            ),
            previousSet: const WorkoutSet(id: 'prev', weight: 20, reps: 10),
            exerciseKind: ExerciseKind.strength,
            loggingMode: ExerciseLoggingMode.weightReps,
            onSetUpdated: (_) {},
            onSetCompleted: (_) {},
          ),
        ),
      );
      await tester.pump();

      final weightField = tester.widget<TextField>(
        find.byType(TextField).at(0),
      );
      expect(double.tryParse(weightField.controller?.text ?? ''), 0);
    });

    testWidgets('entering zero weight stays visible after rebuild', (
      tester,
    ) async {
      WorkoutSet current = const WorkoutSet(
        id: 'set-2',
        weight: 0,
        reps: 10,
        isCompleted: false,
      );
      late StateSetter hostSetState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                hostSetState = setState;
                return SetRow(
                  setIndex: 0,
                  set: current,
                  previousSet: const WorkoutSet(
                    id: 'prev',
                    weight: 0,
                    reps: 10,
                  ),
                  exerciseKind: ExerciseKind.strength,
                  loggingMode: ExerciseLoggingMode.weightReps,
                  onSetUpdated: (updated) {
                    current = updated;
                  },
                  onSetCompleted: (completed) {
                    current = completed;
                    hostSetState(() {});
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final weightFieldFinder = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.suffixText == 'kg',
      );
      await tester.tap(weightFieldFinder);
      await tester.pump();
      await tester.enterText(weightFieldFinder, '0');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pumpAndSettle();

      final weightField = tester.widget<TextField>(weightFieldFinder);
      expect(double.tryParse(weightField.controller?.text ?? ''), 0);
      expect(current.isCompleted, isTrue);
    });

    testWidgets('entering zero weight stays visible after scroll', (
      tester,
    ) async {
      WorkoutSet current = const WorkoutSet(
        id: 'set-3',
        weight: 0,
        reps: 10,
        isCompleted: false,
      );
      late StateSetter hostSetState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                hostSetState = setState;
                return ListView.builder(
                  cacheExtent: 0,
                  itemCount: 40,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return SizedBox(
                        // Tall enough for the input row + the optional RPE line.
                        height: 120,
                        child: SetRow(
                          setIndex: 0,
                          set: current,
                          previousSet: const WorkoutSet(
                            id: 'prev',
                            weight: 0,
                            reps: 10,
                          ),
                          exerciseKind: ExerciseKind.strength,
                          loggingMode: ExerciseLoggingMode.weightReps,
                          onSetUpdated: (updated) {
                            current = updated;
                          },
                          onSetCompleted: (completed) {
                            current = completed;
                            hostSetState(() {});
                          },
                        ),
                      );
                    }
                    return SizedBox(
                      height: 110,
                      child: Center(child: Text('filler $index')),
                    );
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final weightFieldFinder = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.suffixText == 'kg',
      );

      await tester.tap(weightFieldFinder);
      await tester.pump();
      await tester.enterText(weightFieldFinder, '0');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pumpAndSettle();

      expect(current.isCompleted, isTrue);
      final initialWeightField = tester.widget<TextField>(weightFieldFinder);
      expect(double.tryParse(initialWeightField.controller?.text ?? ''), 0);

      await tester.fling(find.byType(ListView), const Offset(0, -2000), 2500);
      await tester.pumpAndSettle();
      expect(weightFieldFinder, findsNothing);

      await tester.fling(find.byType(ListView), const Offset(0, 2000), 2500);
      await tester.pumpAndSettle();
      expect(weightFieldFinder, findsOneWidget);

      final weightFieldAfterScroll = tester.widget<TextField>(
        weightFieldFinder,
      );
      expect(double.tryParse(weightFieldAfterScroll.controller?.text ?? ''), 0);
    });

    testWidgets('iOS swipe left deletes a set row', (tester) async {
      var deleted = false;

      await tester.pumpWidget(_SetRowHost(onDeleted: () => deleted = true));
      await tester.pumpAndSettle();

      final dismissibleFinder = find.byType(Dismissible);
      expect(dismissibleFinder, findsOneWidget);

      final size = tester.getSize(dismissibleFinder);
      await tester.drag(dismissibleFinder, Offset(-(size.width + 100), 0));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
    });
  });

  group('SetRow reps keyboard RPE mode', () {
    // Strong-style: RPE is selected from the custom Reps keyboard rather than a
    // separate table column. Hustl stores integer RPE today, so the keyboard
    // offers the supported 6-10 values.
    testWidgets('reps cell opens custom keyboard and RPE mode persists choice', (
      tester,
    ) async {
      WorkoutSet? updated;
      var completeCalls = 0;

      await tester.pumpWidget(
        _wrap(
          SetRow(
            setIndex: 0,
            // reps outside 6-10 so picker digits never collide with the field.
            set: const WorkoutSet(id: 's1', weight: 50, reps: 12),
            onSetUpdated: (s) => updated = s,
            onSetCompleted: (_) => completeCalls++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('repsRpeKeyboard')), findsNothing);

      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('repsRpeKeyboard')), findsOneWidget);
      // RPE rides in the keyboard as an always-visible 6-10 range (no mode
      // toggle, no separate table column).
      expect(find.byKey(const Key('rirKey4')), findsOneWidget);
      expect(find.byKey(const Key('rirKey0')), findsOneWidget);

      await tester.tap(find.byKey(const Key('rirKey2')));
      await tester.pumpAndSettle();

      expect(updated?.rpe, 8);
      // RPE rides through as a plain update; completion is untouched.
      expect(updated?.isCompleted, isFalse);
      expect(completeCalls, 0);
    });

    testWidgets('first keypad digit replaces the existing reps (tap-to-edit)', (
      tester,
    ) async {
      // Opening the keyboard on an existing value reads as "select-all": the
      // first digit must REPLACE, not append (editing 12 -> 8 yields 8, not
      // 128). Regression guard for the keyboard's _replaceOnNextDigit logic.
      WorkoutSet? updated;

      await tester.pumpWidget(
        _wrap(
          SetRow(
            setIndex: 0,
            set: const WorkoutSet(id: 's1', weight: 50, reps: 12),
            onSetUpdated: (s) => updated = s,
            onSetCompleted: (s) => updated = s,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('repsKeyboardDigit8')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('repsKeyboardDone')));
      await tester.pumpAndSettle();

      expect(updated?.reps, 8);
    });

    testWidgets(
      'choosing RPE does not persist untouched previous placeholders',
      (tester) async {
        WorkoutSet? updated;

        await tester.pumpWidget(
          _wrap(
            SetRow(
              setIndex: 0,
              set: const WorkoutSet(id: 's1', weight: 0, reps: 0),
              previousSet: const WorkoutSet(id: 'p1', weight: 100, reps: 5),
              onSetUpdated: (s) => updated = s,
              onSetCompleted: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('repsField-0')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('rirKey2')));
        await tester.pumpAndSettle();

        expect(updated?.weight, 0);
        expect(updated?.reps, 0);
        expect(updated?.rpe, 8);
      },
    );

    testWidgets('rep row with RPE fits inside a 320dp phone row', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 288,
            child: SetRow(
              setIndex: 0,
              set: const WorkoutSet(id: 's1', weight: 100, reps: 12),
              previousSet: const WorkoutSet(id: 'p1', weight: 95, reps: 10),
              onSetUpdated: (_) {},
              onSetCompleted: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping the selected RPE value clears it', (tester) async {
      WorkoutSet? updated;

      await tester.pumpWidget(
        _wrap(
          SetRow(
            setIndex: 0,
            set: const WorkoutSet(id: 's1', weight: 50, reps: 12, rpe: 8),
            onSetUpdated: (s) => updated = s,
            onSetCompleted: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('rirKey2')));
      await tester.pumpAndSettle();

      expect(updated?.rpe, isNull);
    });

    testWidgets('rpe is editable on a completed set and keeps it completed', (
      tester,
    ) async {
      WorkoutSet? updated;
      var completeCalls = 0;

      await tester.pumpWidget(
        _wrap(
          SetRow(
            setIndex: 0,
            set: const WorkoutSet(
              id: 's1',
              weight: 50,
              reps: 12,
              isCompleted: true,
            ),
            onSetUpdated: (s) => updated = s,
            onSetCompleted: (_) => completeCalls++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rirKey1')));
      await tester.pumpAndSettle();

      expect(updated?.rpe, 9);
      expect(updated?.isCompleted, isTrue);
      expect(completeCalls, 0);
    });

    testWidgets('warm-up rows still expose the keyboard RPE range', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SetRow(
            setIndex: 0,
            set: const WorkoutSet(
              id: 's1',
              weight: 40,
              reps: 10,
              setType: SetType.warmup,
            ),
            onSetUpdated: (_) {},
            onSetCompleted: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('repsField-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rirKey4')), findsOneWidget);
    });

    testWidgets(
      'rep-based exercise does not show a separate RPE column header',
      (tester) async {
        const exercise = Exercise(
          name: 'Bench Press',
          muscles: ['Chest'],
          kind: ExerciseKind.strength,
          loggingMode: ExerciseLoggingMode.weightReps,
        );
        const workoutExercise = WorkoutExercise(
          id: 'we-rpe-header',
          exercise: exercise,
          sets: [WorkoutSet(id: 's1', weight: 0, reps: 0)],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ExerciseCard(
                exercise: workoutExercise,
                onExerciseUpdated: (_) {},
                onStartRestTimer: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('RPE'), findsNothing);
      },
    );

    testWidgets('non rep-based exercises have no RPE keyboard mode', (
      tester,
    ) async {
      const exercise = Exercise(
        name: 'Rowing',
        muscles: ['Back'],
        kind: ExerciseKind.cardio,
        loggingMode: ExerciseLoggingMode.distanceDuration,
      );
      const workoutExercise = WorkoutExercise(
        id: 'we-no-rpe',
        exercise: exercise,
        sets: [WorkoutSet(id: 's1', weight: 0, reps: 0)],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseCard(
              exercise: workoutExercise,
              onExerciseUpdated: (_) {},
              onStartRestTimer: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RPE'), findsNothing);
    });
  });

  group('Workout logging widget behavior', () {
    testWidgets('assisted set allows negative weight input', (tester) async {
      const set1 = WorkoutSet(id: 's1', weight: 0, reps: 0);
      WorkoutSet updated = set1;

      await tester.pumpWidget(
        _wrap(
          SetRow(
            setIndex: 0,
            set: set1,
            exerciseKind: ExerciseKind.assisted,
            onSetUpdated: (set) => updated = set,
            onSetCompleted: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final weightField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.suffixText == 'kg',
      );
      expect(weightField, findsOneWidget);

      await tester.tap(weightField);
      await tester.pump();
      await tester.enterText(weightField, '15.5');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();

      expect(updated.weight, -15.5);
    });

    testWidgets(
      'assisted completion flips positive weight when tapping check',
      (tester) async {
        const set1 = WorkoutSet(id: 's1', weight: 0, reps: 0);
        WorkoutSet? completed;

        await tester.pumpWidget(
          _wrap(
            SetRow(
              setIndex: 0,
              set: set1,
              exerciseKind: ExerciseKind.assisted,
              onSetUpdated: (_) {},
              onSetCompleted: (set) => completed = set,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final weightField = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.suffixText == 'kg',
        );
        expect(weightField, findsOneWidget);

        await tester.tap(weightField);
        await tester.pump();
        await tester.enterText(weightField, '12');
        await tester.pump();

        await tester.tap(find.byIcon(Icons.check_circle_outline));
        await tester.pump();

        expect(completed, isNotNull);
        expect(completed!.weight, -12);
      },
    );

    testWidgets('cardio exercise shows km and Time headers', (tester) async {
      const exercise = Exercise(
        name: 'Rowing',
        muscles: ['Back'],
        kind: ExerciseKind.cardio,
        loggingMode: ExerciseLoggingMode.distanceDuration,
      );
      const workoutExercise = WorkoutExercise(
        id: 'we1',
        exercise: exercise,
        sets: [WorkoutSet(id: 's1', weight: 0, reps: 0)],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseCard(
              exercise: workoutExercise,
              onExerciseUpdated: (_) {},
              onStartRestTimer: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('km'), findsWidgets);
      expect(find.text('Time'), findsOneWidget);
    });

    testWidgets(
      'distance+duration row ghosts the previous distance and time inside the '
      'fields (the field prefill, shown alongside the Previous column)',
      (tester) async {
        // Strong-style: BOTH the explicit Previous column AND the in-field
        // prefill show last session's value. This test pins the prefill — last
        // session's value reads as a faint placeholder inside the km + Time
        // fields, alongside the dedicated Previous column.
        const set = WorkoutSet(id: 's1', weight: 0, reps: 0);
        const previous = WorkoutSet(id: 'p1', weight: 5.0, reps: 90);

        await tester.pumpWidget(
          _wrap(
            SetRow(
              setIndex: 0,
              set: set,
              previousSet: previous,
              exerciseKind: ExerciseKind.cardio,
              loggingMode: ExerciseLoggingMode.distanceDuration,
              onSetUpdated: (_) {},
              onSetCompleted: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final theme = Theme.of(tester.element(find.byType(SetRow)));

        // The km field carries the previous distance (5.0) as a faint prefill.
        final kmField = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.suffixText == 'km',
        );
        expect(kmField, findsOneWidget);
        final kmWidget = tester.widget<TextField>(kmField);
        expect(double.tryParse(kmWidget.controller?.text ?? ''), 5.0);
        expect(
          kmWidget.style?.color,
          theme.colorScheme.onSurface.withValues(alpha: 0.35),
          reason: 'previous distance must ghost faintly in the km field',
        );

        // The Time field carries the previous duration (90s -> 01:30) faintly.
        final durationField = find.byKey(const ValueKey('durationField'));
        expect(durationField, findsOneWidget);
        final editable = find.descendant(
          of: durationField,
          matching: find.byType(EditableText),
        );
        expect(tester.widget<EditableText>(editable).controller.text, '01:30');
        // The Time field is now the keyed TextField itself (a read-only proxy
        // for the custom keyboard), not a DurationField wrapper.
        final durationTextField = tester.widget<TextField>(durationField);
        expect(
          durationTextField.style?.color,
          // The Time field now reuses the reps field's read-only visual path,
          // so a prefill ghosts at the same 0.35 alpha as the weight/reps fields.
          theme.colorScheme.onSurface.withValues(alpha: 0.35),
          reason: 'previous duration must ghost faintly in the Time field',
        );
      },
    );

    testWidgets(
      'the "Previous" column shows last session\'s value per logging mode',
      (tester) async {
        // The explicit Previous column (Strong/Hevy-style) renders last
        // session\'s value as a compact, faint Text — read natively by screen
        // readers, so no separate Semantics node is needed.
        Future<void> pumpRow(
          WorkoutSet previous,
          ExerciseKind kind,
          ExerciseLoggingMode mode,
        ) async {
          await tester.pumpWidget(
            _wrap(
              SetRow(
                setIndex: 0,
                set: const WorkoutSet(id: 's1', weight: 0, reps: 0),
                previousSet: previous,
                exerciseKind: kind,
                loggingMode: mode,
                onSetUpdated: (_) {},
                onSetCompleted: (_) {},
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        // weightReps -> "60 kg × 10"
        await pumpRow(
          const WorkoutSet(id: 'p', weight: 60, reps: 10),
          ExerciseKind.strength,
          ExerciseLoggingMode.weightReps,
        );
        expect(find.text('60 kg × 10'), findsOneWidget);

        // distanceDuration -> "5 · 01:30" (compact mid-dot, unit in header)
        await pumpRow(
          const WorkoutSet(id: 'p', weight: 5.0, reps: 90),
          ExerciseKind.cardio,
          ExerciseLoggingMode.distanceDuration,
        );
        expect(find.text('5 · 01:30'), findsOneWidget);

        // durationOnly -> "01:30"
        await pumpRow(
          const WorkoutSet(id: 'p', weight: 0, reps: 90),
          ExerciseKind.strength,
          ExerciseLoggingMode.durationOnly,
        );
        expect(find.text('01:30'), findsWidgets);
      },
    );

    testWidgets(
      'assisted previous value keeps the sign (matches the field ghost)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            SetRow(
              setIndex: 0,
              set: const WorkoutSet(id: 's1', weight: 0, reps: 0),
              previousSet: const WorkoutSet(id: 'p', weight: -20, reps: 8),
              exerciseKind: ExerciseKind.assisted,
              loggingMode: ExerciseLoggingMode.weightReps,
              onSetUpdated: (_) {},
              onSetCompleted: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Assistance is stored as a negative weight; the compact column shows
        // the magnitude (the implicit "kg" lives in the column header).
        expect(find.text('-20 kg × 8'), findsOneWidget);
      },
    );

    testWidgets('the "Previous" column reads "-" when there is no previous set', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SetRow(
            setIndex: 0,
            set: const WorkoutSet(id: 's1', weight: 0, reps: 0),
            previousSet: null,
            onSetUpdated: (_) {},
            onSetCompleted: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A template-like row with no history reads as a normal table cell ("-"),
      // not a void, and carries no "Previous: …" Semantics announcement.
      expect(find.text('-'), findsOneWidget);
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel(RegExp('^Previous:')), findsNothing);
      handle.dispose();
    });

    testWidgets('cardio reps accepts mm:ss and preserves seconds', (
      tester,
    ) async {
      final controller = SetInputKeyboardController();
      addTearDown(controller.dispose);

      const exercise = Exercise(
        name: 'Run',
        muscles: ['Legs'],
        kind: ExerciseKind.cardio,
        loggingMode: ExerciseLoggingMode.distanceDuration,
      );
      const workoutExercise = WorkoutExercise(
        id: 'we2',
        exercise: exercise,
        sets: [WorkoutSet(id: 's1', weight: 5.0, reps: 0)],
      );
      WorkoutExercise updated = workoutExercise;

      await tester.pumpWidget(
        _scopedHost(
          controller,
          ExerciseCard(
            exercise: workoutExercise,
            onExerciseUpdated: (exercise) => updated = exercise,
            onStartRestTimer: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the Time field → custom keyboard opens. Enter 12:30 via digit keys,
      // then Done (no native keyboard).
      await tester.tap(find.byKey(const ValueKey('durationField')));
      await tester.pumpAndSettle();
      for (final d in ['1', '2', '3', '0']) {
        await tester.tap(find.byKey(Key('repsKeyboardDigit$d')));
      }
      await tester.pump();
      await tester.tap(find.byKey(const Key('repsKeyboardDone')));
      await tester.pumpAndSettle();

      expect(updated.sets.first.reps, 750);
    });

    testWidgets(
      'duration-only exercise hides weight input and shows Time only',
      (tester) async {
        const exercise = Exercise(
          name: 'Plank',
          muscles: ['Abs'],
          kind: ExerciseKind.strength,
          loggingMode: ExerciseLoggingMode.durationOnly,
        );
        const workoutExercise = WorkoutExercise(
          id: 'we-plank',
          exercise: exercise,
          sets: [WorkoutSet(id: 's1', weight: 0, reps: 0)],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ExerciseCard(
                exercise: workoutExercise,
                onExerciseUpdated: (_) {},
                onStartRestTimer: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Time'), findsOneWidget);
        expect(find.text('km'), findsNothing);
        expect(find.text('kg'), findsNothing);

        final weightField = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.suffixText != null &&
              (widget.decoration!.suffixText == 'kg' ||
                  widget.decoration!.suffixText == 'km'),
        );
        expect(weightField, findsNothing);
        expect(find.byKey(const ValueKey('durationField')), findsOneWidget);
      },
    );

    testWidgets('cardio reps auto-formats bare digits to mm:ss', (
      tester,
    ) async {
      final controller = SetInputKeyboardController();
      addTearDown(controller.dispose);
      const set1 = WorkoutSet(id: 's1', weight: 5.0, reps: 0);

      await tester.pumpWidget(
        _scopedHost(
          controller,
          SetRow(
            setIndex: 0,
            set: set1,
            exerciseKind: ExerciseKind.cardio,
            loggingMode: ExerciseLoggingMode.distanceDuration,
            onSetUpdated: (_) {},
            onSetCompleted: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('durationField')));
      await tester.pumpAndSettle();
      for (final d in ['1', '2', '3', '4']) {
        await tester.tap(find.byKey(Key('repsKeyboardDigit$d')));
      }
      await tester.pump();

      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('durationField')),
      );
      expect(field.controller?.text, '12:34');
    });

    testWidgets('duration input caps at 4 digits (mm:ss)', (tester) async {
      final controller = SetInputKeyboardController();
      addTearDown(controller.dispose);
      const set1 = WorkoutSet(id: 's1', weight: 0, reps: 0);

      await tester.pumpWidget(
        _scopedHost(
          controller,
          SetRow(
            setIndex: 0,
            set: set1,
            exerciseKind: ExerciseKind.cardio,
            loggingMode: ExerciseLoggingMode.distanceDuration,
            onSetUpdated: (_) {},
            onSetCompleted: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('durationField')));
      await tester.pumpAndSettle();
      // A 5th digit is ignored — duration caps at 4 raw digits (mm:ss, ≤ 99:59).
      for (final d in ['1', '2', '3', '4', '5']) {
        await tester.tap(find.byKey(Key('repsKeyboardDigit$d')));
      }
      await tester.pump();

      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('durationField')),
      );
      expect(field.controller?.text, '12:34');
    });

    testWidgets('cardio digit-only reps input normalizes seconds over 59', (
      tester,
    ) async {
      final controller = SetInputKeyboardController();
      addTearDown(controller.dispose);
      const set1 = WorkoutSet(id: 's1', weight: 5.0, reps: 0);
      WorkoutSet updated = set1;

      await tester.pumpWidget(
        _scopedHost(
          controller,
          SetRow(
            setIndex: 0,
            set: set1,
            exerciseKind: ExerciseKind.cardio,
            loggingMode: ExerciseLoggingMode.distanceDuration,
            onSetUpdated: (set) => updated = set,
            onSetCompleted: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('durationField')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('repsKeyboardDigit9')));
      await tester.tap(find.byKey(const Key('repsKeyboardDigit0')));
      await tester.pump();

      // Raw "90" reads as 90 seconds (last two digits are seconds) → shown as
      // 00:90 while typing.
      var field = tester.widget<TextField>(
        find.byKey(const ValueKey('durationField')),
      );
      expect(field.controller?.text, '00:90');

      await tester.tap(find.byKey(const Key('repsKeyboardDone')));
      await tester.pumpAndSettle();

      // Persisted as 90s, normalized to 01:30 on Done.
      expect(updated.reps, 90);
      field = tester.widget<TextField>(
        find.byKey(const ValueKey('durationField')),
      );
      expect(field.controller?.text, '01:30');
    });

    testWidgets('cardio uncomplete preserves mm:ss input without Done', (
      tester,
    ) async {
      final controller = SetInputKeyboardController();
      addTearDown(controller.dispose);
      const exercise = Exercise(
        name: 'Run',
        muscles: ['Legs'],
        kind: ExerciseKind.cardio,
        loggingMode: ExerciseLoggingMode.distanceDuration,
      );
      const workoutExercise = WorkoutExercise(
        id: 'we3',
        exercise: exercise,
        sets: [WorkoutSet(id: 's1', weight: 2.0, reps: 0)],
      );
      WorkoutExercise latest = workoutExercise;

      await tester.pumpWidget(
        _scopedHost(
          controller,
          ExerciseCard(
            exercise: workoutExercise,
            onExerciseUpdated: (exercise) => latest = exercise,
            onStartRestTimer: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Complete the set, then edit the Time to 02:15 (135s) via the keyboard.
      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('durationField')));
      await tester.pumpAndSettle();
      for (final d in ['2', '1', '5']) {
        await tester.tap(find.byKey(Key('repsKeyboardDigit$d')));
      }
      await tester.pump();

      // Tap the filled check to uncomplete — the typed 135s is preserved.
      await tester.tap(find.byIcon(Icons.check_circle));
      await tester.pumpAndSettle();

      expect(latest.sets.first.reps, 135);
    });

    testWidgets('clearing duration and blurring persists 0 without Done', (
      tester,
    ) async {
      final controller = SetInputKeyboardController();
      addTearDown(controller.dispose);
      const set1 = WorkoutSet(id: 's1', weight: 0, reps: 75);
      WorkoutSet updated = set1;
      var completeCalls = 0;

      await tester.pumpWidget(
        _scopedHost(
          controller,
          SetRow(
            setIndex: 0,
            set: set1,
            exerciseKind: ExerciseKind.cardio,
            loggingMode: ExerciseLoggingMode.distanceDuration,
            onSetUpdated: (set) => updated = set,
            onSetCompleted: (_) => completeCalls++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the Time keyboard (seeded 01:15) and Clear it.
      await tester.tap(find.byKey(const ValueKey('durationField')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('repsKeyboardClear')));
      await tester.pump();

      // Dismiss the keyboard (blur-save) WITHOUT Done.
      controller.close();
      await tester.pumpAndSettle();

      expect(updated.reps, 0);
      expect(completeCalls, 0);
    });

    testWidgets(
      'completion applies PR flag even when lookup resolves before rebuild',
      (tester) async {
        final repo = _ImmediatePrRepo(true);
        GetIt.I.registerSingleton<WorkoutRepository>(repo);

        const exercise = Exercise(
          name: 'Bench Press',
          muscles: ['Chest'],
          kind: ExerciseKind.strength,
          loggingMode: ExerciseLoggingMode.weightReps,
        );
        WorkoutExercise current = const WorkoutExercise(
          id: 'we-pr-race',
          exercise: exercise,
          sets: [WorkoutSet(id: 's1', weight: 100, reps: 5)],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return ExerciseCard(
                    exercise: current,
                    onExerciseUpdated: (exercise) {
                      current = exercise;
                      setState(() {});
                    },
                    onStartRestTimer: (_) {},
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.check_circle_outline));
        await tester.pump();
        await tester.pump();

        expect(current.sets.first.isCompleted, isTrue);
        expect(current.sets.first.isPr, isTrue);
        expect(repo.calls, 1);

        // The PR flash is a finite flutter_animate pulse (a Ticker). Settle it
        // so the animation completes and disposes before teardown.
        await tester.pumpAndSettle();
      },
    );

    testWidgets('distance-duration completion does not run weight PR lookup', (
      tester,
    ) async {
      final repo = _ImmediatePrRepo(true);
      GetIt.I.registerSingleton<WorkoutRepository>(repo);

      const exercise = Exercise(
        name: 'Custom Run',
        muscles: ['Cardio'],
        loggingMode: ExerciseLoggingMode.distanceDuration,
      );
      WorkoutExercise current = const WorkoutExercise(
        id: 'we-cardio-pr',
        exercise: exercise,
        sets: [WorkoutSet(id: 's1', weight: 2.5, reps: 780)],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ExerciseCard(
                  exercise: current,
                  onExerciseUpdated: (exercise) {
                    current = exercise;
                    setState(() {});
                  },
                  onStartRestTimer: (_) {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pump();
      await tester.pump();

      expect(current.sets.first.isCompleted, isTrue);
      expect(current.sets.first.isPr, isFalse);
      expect(repo.calls, 0);
    });

    testWidgets('re-completing invalid set clears stale PR flag', (
      tester,
    ) async {
      final repo = _ImmediatePrRepo(true);
      GetIt.I.registerSingleton<WorkoutRepository>(repo);

      const exercise = Exercise(
        name: 'Bench Press',
        muscles: ['Chest'],
        kind: ExerciseKind.strength,
        loggingMode: ExerciseLoggingMode.weightReps,
      );
      WorkoutExercise current = const WorkoutExercise(
        id: 'we-pr-clear',
        exercise: exercise,
        sets: [
          WorkoutSet(
            id: 's1',
            weight: 100,
            reps: 5,
            isCompleted: true,
            isPr: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ExerciseCard(
                  exercise: current,
                  onExerciseUpdated: (exercise) {
                    current = exercise;
                    setState(() {});
                  },
                  onStartRestTimer: (_) {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final weightField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.suffixText == 'kg',
      );
      expect(weightField, findsOneWidget);

      await tester.tap(weightField);
      await tester.pump();
      await tester.enterText(weightField, '0');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();

      expect(current.sets.first.isCompleted, isTrue);
      expect(current.sets.first.isPr, isFalse);
      expect(repo.calls, 0);
    });

    testWidgets(
      'warm-up rows show a W badge; working ordinals re-derive (W W 1 2 3)',
      (tester) async {
        const exercise = Exercise(name: 'Bench', muscles: ['Chest']);
        // Empty (0/0) sets keep reps/weight fields blank so the only literal
        // digits on screen are the re-derived ordinals in the set-number slot.
        const workoutExercise = WorkoutExercise(
          id: 'we-warm',
          exercise: exercise,
          sets: [
            WorkoutSet(id: 'w1', weight: 0, reps: 0, setType: SetType.warmup),
            WorkoutSet(id: 'w2', weight: 0, reps: 0, setType: SetType.warmup),
            WorkoutSet(id: 's1', weight: 0, reps: 0),
            WorkoutSet(id: 's2', weight: 0, reps: 0),
            WorkoutSet(id: 's3', weight: 0, reps: 0),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ExerciseCard(
                  exercise: workoutExercise,
                  onExerciseUpdated: (_) {},
                  onStartRestTimer: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Two warm-up rows render the amber W badge instead of an ordinal.
        expect(find.byKey(const Key('warmupBadge')), findsNWidgets(2));
        // 'W' text inside each badge.
        expect(find.text('W'), findsNWidgets(2));

        // Working ordinals re-derive over non-warm-up sets only: 1, 2, 3.
        // (No '4' or '5' even though there are 5 rows total.)
        expect(find.text('1'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('4'), findsNothing);
        expect(find.text('5'), findsNothing);
      },
    );
  });

  group('DurationField behavior', () {
    testWidgets('renders provided initial value in mm:ss format', (
      tester,
    ) async {
      await tester.pumpWidget(const _DurationFieldHost(initialValue: 75));
      await tester.pump();

      final editable = find.descendant(
        of: find.byKey(const ValueKey('durationField')),
        matching: find.byType(EditableText),
      );

      final text = tester.widget<EditableText>(editable).controller.text;
      expect(text, '01:15');
    });

    testWidgets('formats sequential digit input into mm:ss mask', (
      tester,
    ) async {
      await tester.pumpWidget(const _DurationFieldHost());

      final editable = find.descendant(
        of: find.byKey(const ValueKey('durationField')),
        matching: find.byType(EditableText),
      );

      await tester.tap(editable);
      await tester.pump();

      await tester.enterText(editable, '1');
      await tester.pump();
      expect(tester.widget<EditableText>(editable).controller.text, '00:01');

      await tester.enterText(editable, '12');
      await tester.pump();
      expect(tester.widget<EditableText>(editable).controller.text, '00:12');

      await tester.enterText(editable, '123');
      await tester.pump();
      expect(tester.widget<EditableText>(editable).controller.text, '01:23');

      await tester.enterText(editable, '1234');
      await tester.pump();
      expect(tester.widget<EditableText>(editable).controller.text, '12:34');
    });

    testWidgets('backspace removes digits from the end', (tester) async {
      await tester.pumpWidget(const _DurationFieldHost());

      final editable = find.descendant(
        of: find.byKey(const ValueKey('durationField')),
        matching: find.byType(EditableText),
      );

      await tester.tap(editable);
      await tester.pump();
      await tester.enterText(editable, '1234');
      await tester.pump();
      expect(tester.widget<EditableText>(editable).controller.text, '12:34');

      await tester.enterText(editable, '123');
      await tester.pump();
      expect(tester.widget<EditableText>(editable).controller.text, '01:23');

      await tester.enterText(editable, '12');
      await tester.pump();
      expect(tester.widget<EditableText>(editable).controller.text, '00:12');

      await tester.enterText(editable, '1');
      await tester.pump();
      expect(tester.widget<EditableText>(editable).controller.text, '00:01');

      await tester.enterText(editable, '');
      await tester.pump();
      expect(tester.widget<EditableText>(editable).controller.text, isEmpty);
    });

    testWidgets('submits normalized seconds when pressing done', (
      tester,
    ) async {
      final hostKey = GlobalKey<_DurationFieldHostState>();
      await tester.pumpWidget(_DurationFieldHost(key: hostKey));

      final editable = find.descendant(
        of: find.byKey(const ValueKey('durationField')),
        matching: find.byType(EditableText),
      );

      await tester.tap(editable);
      await tester.pump();
      await tester.enterText(editable, '75');
      await tester.pump();

      expect(hostKey.currentState!.lastChanged, 75);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(hostKey.currentState!.lastSubmitted, 75);
      expect(hostKey.currentState!.value, 75);
      expect(tester.widget<EditableText>(editable).controller.text, '01:15');
    });

    testWidgets('formats more than four digits as minutes:seconds', (
      tester,
    ) async {
      await tester.pumpWidget(const _DurationFieldHost());

      final editable = find.descendant(
        of: find.byKey(const ValueKey('durationField')),
        matching: find.byType(EditableText),
      );

      await tester.tap(editable);
      await tester.pump();
      await tester.enterText(editable, '123456');
      await tester.pump();

      expect(tester.widget<EditableText>(editable).controller.text, '1234:56');
    });

    testWidgets('ignores non-digit characters in input', (tester) async {
      await tester.pumpWidget(const _DurationFieldHost());

      final editable = find.descendant(
        of: find.byKey(const ValueKey('durationField')),
        matching: find.byType(EditableText),
      );

      await tester.tap(editable);
      await tester.pump();
      await tester.enterText(editable, '12ab34');
      await tester.pump();

      expect(tester.widget<EditableText>(editable).controller.text, '12:34');
    });
  });
}
