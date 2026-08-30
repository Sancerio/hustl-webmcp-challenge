import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/set_row.dart';

/// Stateful host that persists [onSetUpdated] back into the row, so an accepted
/// suggestion drives the same rebuild path as typed input.
class _SuggestionHost extends StatefulWidget {
  const _SuggestionHost({required this.initial, required this.previous});

  final WorkoutSet initial;
  final WorkoutSet? previous;

  @override
  State<_SuggestionHost> createState() => _SuggestionHostState();
}

class _SuggestionHostState extends State<_SuggestionHost> {
  late WorkoutSet _set = widget.initial;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            SetRow(
              setIndex: 0,
              set: _set,
              previousSet: widget.previous,
              onSetUpdated: (s) => setState(() => _set = s),
              onSetCompleted: (s) => setState(() => _set = s),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  const emptyWorking = WorkoutSet(id: '1', weight: 0, reps: 0);
  const previousCompleted = WorkoutSet(
    id: 'p1',
    weight: 100,
    reps: 8,
    isCompleted: true,
  );

  final hint = find.byKey(const Key('nextSetSuggestion'));

  Future<void> setPrefs({required bool enabled}) async {
    await GetIt.I.reset(dispose: true);
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    await prefs.setHapticsEnabled(false);
    await prefs.setSuggestNextSetTargets(enabled);
    GetIt.I.registerSingleton<PreferencesService>(prefs);
  }

  tearDown(() async {
    await GetIt.I.reset(dispose: true);
  });

  testWidgets('renders the suggestion hint on an empty working row', (
    tester,
  ) async {
    await setPrefs(enabled: true);
    await tester.pumpWidget(
      const _SuggestionHost(initial: emptyWorking, previous: previousCompleted),
    );
    await tester.pump();

    // 100 kg x 8 completed -> +2.5 kg at same reps.
    expect(hint, findsOneWidget);
    expect(find.text('102.5 kg × 8'), findsOneWidget);
  });

  testWidgets('tapping the hint fills the weight and reps fields', (
    tester,
  ) async {
    await setPrefs(enabled: true);
    await tester.pumpWidget(
      const _SuggestionHost(initial: emptyWorking, previous: previousCompleted),
    );
    await tester.pump();

    await tester.tap(hint);
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    expect(tester.widget<TextField>(fields.at(0)).controller?.text, '102.5');
    expect(tester.widget<TextField>(fields.at(1)).controller?.text, '8');

    // The hint retires once the row carries a value (never a lingering CTA).
    expect(hint, findsNothing);
  });

  testWidgets('does not complete the set when accepted', (tester) async {
    await setPrefs(enabled: true);
    await tester.pumpWidget(
      const _SuggestionHost(initial: emptyWorking, previous: previousCompleted),
    );
    await tester.pump();

    await tester.tap(hint);
    await tester.pumpAndSettle();

    // No completed accent -> the set is still open, awaiting the completion tap.
    expect(find.byKey(const Key('completedLeftAccent')), findsNothing);
  });

  testWidgets('absent when the toggle is off', (tester) async {
    await setPrefs(enabled: false);
    await tester.pumpWidget(
      const _SuggestionHost(initial: emptyWorking, previous: previousCompleted),
    );
    await tester.pump();

    expect(hint, findsNothing);
  });

  testWidgets('absent on a completed row', (tester) async {
    await setPrefs(enabled: true);
    await tester.pumpWidget(
      const _SuggestionHost(
        initial: WorkoutSet(id: '1', weight: 100, reps: 8, isCompleted: true),
        previous: previousCompleted,
      ),
    );
    await tester.pump();

    expect(hint, findsNothing);
  });

  testWidgets('absent when the row already has typed values', (tester) async {
    await setPrefs(enabled: true);
    await tester.pumpWidget(
      const _SuggestionHost(
        initial: WorkoutSet(id: '1', weight: 60, reps: 5),
        previous: previousCompleted,
      ),
    );
    await tester.pump();

    expect(hint, findsNothing);
  });

  testWidgets('absent when there is no previous set', (tester) async {
    await setPrefs(enabled: true);
    await tester.pumpWidget(
      const _SuggestionHost(initial: emptyWorking, previous: null),
    );
    await tester.pump();

    expect(hint, findsNothing);
  });

  testWidgets('absent on a warm-up row', (tester) async {
    await setPrefs(enabled: true);
    await tester.pumpWidget(
      const _SuggestionHost(
        initial: WorkoutSet(
          id: '1',
          weight: 0,
          reps: 0,
          setType: SetType.warmup,
        ),
        previous: previousCompleted,
      ),
    );
    await tester.pump();

    expect(hint, findsNothing);
  });
}
