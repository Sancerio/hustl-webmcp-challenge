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
import 'package:hustl_app/features/workout_logging/domain/utils/superset_grouping.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/exercise_card.dart';

WorkoutExercise _exercise({
  required String id,
  required String name,
  String? groupId,
  int? order,
  int setCount = 2,
}) {
  return WorkoutExercise(
    id: id,
    exercise: Exercise(name: name, muscles: const ['chest']),
    sets: List.generate(
      setCount,
      (i) => WorkoutSet(id: '$id-s$i', weight: 20, reps: 5),
    ),
    supersetGroupId: groupId,
    supersetOrder: order,
  );
}

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: ListView(children: [child])),
  );
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
    'grouped first member shows rail, Superset header, A-round labels',
    (tester) async {
      final members = [
        _exercise(id: 'a', name: 'Bench Press', groupId: 'g1', order: 0),
        _exercise(id: 'b', name: 'Row', groupId: 'g1', order: 1),
      ];
      final group = SupersetGrouping.groupsFor(members).single;
      expect(group.label, 'Superset');

      await tester.pumpWidget(
        _host(
          ExerciseCard(
            exercise: members.first,
            supersetGroup: group,
            onExerciseUpdated: (_) {},
            onStartRestTimer: (_) {},
          ),
        ),
      );
      await tester.pump();

      // Rail + header chip on the first member.
      expect(find.byKey(const Key('supersetRail')), findsOneWidget);
      expect(find.byKey(const Key('supersetHeaderChip')), findsOneWidget);
      expect(find.text('Superset'), findsWidgets);

      // Round labels for member A: A1, A2.
      expect(find.text('A1'), findsOneWidget);
      expect(find.text('A2'), findsOneWidget);
      // No plain numeric ordinals for the grouped working sets.
      expect(find.text('1'), findsNothing);
    },
  );

  testWidgets('second member renders B-round labels and no header chip', (
    tester,
  ) async {
    final members = [
      _exercise(id: 'a', name: 'Bench Press', groupId: 'g1', order: 0),
      _exercise(id: 'b', name: 'Row', groupId: 'g1', order: 1),
    ];
    final group = SupersetGrouping.groupsFor(members).single;

    await tester.pumpWidget(
      _host(
        ExerciseCard(
          exercise: members[1],
          supersetGroup: group,
          onExerciseUpdated: (_) {},
          onStartRestTimer: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('supersetRail')), findsOneWidget);
    // Header chip is only on the first member.
    expect(find.byKey(const Key('supersetHeaderChip')), findsNothing);
    expect(find.text('B1'), findsOneWidget);
    expect(find.text('B2'), findsOneWidget);
  });

  testWidgets('three members render a Giant set header', (tester) async {
    final members = [
      _exercise(id: 'a', name: 'Bench', groupId: 'g1', order: 0),
      _exercise(id: 'b', name: 'Row', groupId: 'g1', order: 1),
      _exercise(id: 'c', name: 'Curl', groupId: 'g1', order: 2),
    ];
    final group = SupersetGrouping.groupsFor(members).single;
    expect(group.label, 'Giant set');

    await tester.pumpWidget(
      _host(
        ExerciseCard(
          exercise: members.first,
          supersetGroup: group,
          onExerciseUpdated: (_) {},
          onStartRestTimer: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Giant set'), findsWidgets);
  });

  testWidgets('ungrouped exercise shows no rail, header, or round labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ExerciseCard(
          exercise: _exercise(id: 'solo', name: 'Squat'),
          onExerciseUpdated: (_) {},
          onStartRestTimer: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('supersetRail')), findsNothing);
    expect(find.byKey(const Key('supersetHeaderChip')), findsNothing);
    // Plain numeric ordinals.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('A1'), findsNothing);
  });

  testWidgets('non-final group member suppresses the auto rest timer', (
    tester,
  ) async {
    final members = [
      _exercise(id: 'a', name: 'Bench', groupId: 'g1', order: 0, setCount: 1),
      _exercise(id: 'b', name: 'Row', groupId: 'g1', order: 1, setCount: 1),
    ];
    final group = SupersetGrouping.groupsFor(members).single;

    int restCalls = 0;
    await tester.pumpWidget(
      _host(
        ExerciseCard(
          exercise: members.first, // non-final member A
          supersetGroup: group,
          onExerciseUpdated: (_) {},
          onStartRestTimer: (_) => restCalls++,
        ),
      ),
    );
    await tester.pump();

    // Tap the completion button for the only set.
    await tester.tap(find.byTooltip('Mark set 1 as completed'));
    await tester.pump();

    expect(restCalls, 0, reason: 'non-final members share the round rest');
  });

  testWidgets('last group member starts the shared rest on completion', (
    tester,
  ) async {
    final members = [
      _exercise(id: 'a', name: 'Bench', groupId: 'g1', order: 0, setCount: 1),
      _exercise(id: 'b', name: 'Row', groupId: 'g1', order: 1, setCount: 1),
    ];
    final group = SupersetGrouping.groupsFor(members).single;

    int restCalls = 0;
    await tester.pumpWidget(
      _host(
        ExerciseCard(
          exercise: members[1], // final member B
          supersetGroup: group,
          onExerciseUpdated: (_) {},
          onStartRestTimer: (_) => restCalls++,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Mark set 1 as completed'));
    await tester.pump();

    expect(restCalls, 1, reason: 'the last member fires the one shared rest');
  });

  testWidgets('ungrouped exercise surfaces the Superset chip when candidates '
      'exist', (tester) async {
    await tester.pumpWidget(
      _host(
        ExerciseCard(
          exercise: _exercise(id: 'solo', name: 'Squat'),
          linkCandidates: [_exercise(id: 'other', name: 'Lunge')],
          onCreateSuperset: (_) {},
          onExerciseUpdated: (_) {},
          onStartRestTimer: (_) {},
        ),
      ),
    );
    await tester.pump();

    final chip = find.byKey(const ValueKey('chip-superset'));
    expect(chip, findsOneWidget);
    expect(find.text('Superset'), findsOneWidget);
  });

  testWidgets('grouped exercise chip reads "In superset"', (tester) async {
    final members = [
      _exercise(id: 'a', name: 'Bench', groupId: 'g1', order: 0),
      _exercise(id: 'b', name: 'Row', groupId: 'g1', order: 1),
    ];
    final group = SupersetGrouping.groupsFor(members).single;

    await tester.pumpWidget(
      _host(
        ExerciseCard(
          exercise: members.first,
          supersetGroup: group,
          onRemoveFromSuperset: () {},
          onExerciseUpdated: (_) {},
          onStartRestTimer: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('chip-superset')), findsOneWidget);
    expect(find.text('In superset'), findsOneWidget);
  });
}
