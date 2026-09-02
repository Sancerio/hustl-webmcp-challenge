import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_evaluator/src/model/evaluator_state.dart';
import 'package:hustl_evaluator/src/model/models.dart';
import 'package:hustl_evaluator/src/ui/coach_screens.dart';
import 'package:hustl_evaluator/src/ui/design.dart';
import 'package:hustl_evaluator/src/ui/evaluator_scope.dart';

void main() {
  testWidgets('proposal detail remains stable at a 390 by 844 viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = EvaluatorState();
    await state.loadFixtures();
    final proposal = state.propose(
      ProposalKind.nutritionTargets,
      'Nutrition target update',
      const {
        'caloriesTarget': 2400,
        'proteinTarget': 160.0,
        'carbsTarget': 260.0,
        'fatTarget': 75.0,
        'rationale': 'Synthetic evaluator review',
      },
    );

    await tester.pumpWidget(
      EvaluatorScope(
        state: state,
        child: MaterialApp(
          theme: evaluatorTheme(),
          home: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: ProposalDetailScreen(proposalId: proposal.id),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Calories'), findsOneWidget);
    expect(find.text('2,400 kcal'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('maximum length food edit wraps at the desktop row breakpoint', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final beforeName = _foodNameAtLimit('Before1');
    final afterName = _foodNameAtLimit('After22');
    expect(beforeName.runes.length, 200);
    expect(afterName.runes.length, 200);
    expect(beforeName.trim(), beforeName);
    expect(afterName.trim(), afterName);

    final state = EvaluatorState();
    state.foodEntries[0] = state.foodEntries.first.copyWith({
      'foodName': beforeName,
    });
    final proposal = state.propose(
      ProposalKind.foodLogEdit,
      'Food name correction',
      {
        'targetEntryId': state.foodEntries.first.id,
        'changes': {'foodName': afterName},
      },
    );

    await tester.pumpWidget(
      EvaluatorScope(
        state: state,
        child: MaterialApp(
          theme: evaluatorTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: ProposalDetailScreen(proposalId: proposal.id),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ProposalDetailScreen), findsOneWidget);
    expect(find.text('Food name correction'), findsOneWidget);
    expect(find.text('Proposal not found'), findsNothing);
    expect(tester.takeException(), isNull);

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Meal: '),
      250,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Meal: '), findsOneWidget);
    expect(find.text('Food name'), findsOneWidget);
    expect(find.text(beforeName), findsNWidgets(2));
    expect(find.text(afterName), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Food name')).dy,
      tester.getTopLeft(find.text(beforeName).last).dy,
    );
    expect(tester.getSize(find.text(afterName)).height, greaterThan(40));
    expect(tester.takeException(), isNull);

    final apply = find.ancestor(
      of: find.text('Apply'),
      matching: find.bySubtype<FilledButton>(),
    );
    final dismiss = find.ancestor(
      of: find.text('Dismiss'),
      matching: find.bySubtype<OutlinedButton>(),
    );

    await tester.scrollUntilVisible(apply, 250, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(apply.hitTestable(), findsOneWidget);
    expect(dismiss.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('food create review discloses every persisted nutrition field', (
    tester,
  ) async {
    final state = EvaluatorState();
    final proposal = state.propose(
      ProposalKind.foodLog,
      'Log recovery meal',
      const {
        'date': '2026-08-31',
        'items': [
          {
            'foodName': 'Recovery rice bowl',
            'servingGrams': 325.0,
            'calories': 610.0,
            'proteinGrams': 42.0,
            'carbsGrams': 68.0,
            'fatGrams': 19.0,
            'fiberGrams': 11.5,
            'sugarGrams': 7.25,
            'sodiumMg': 640.0,
          },
        ],
      },
    );

    await _pumpProposalDetail(tester, state: state, proposalId: proposal.id);

    for (final detail in const [
      '2026-08-31',
      'Recovery rice bowl',
      'Serving: 325 g · Calories: 610 kcal',
      'Protein: 42 g · Carbs: 68 g · Fat: 19 g',
      'Fibre: 11.5 g',
      'Sugar: 7.25 g',
      'Sodium: 640 mg',
    ]) {
      await _expectTextReachable(tester, detail);
    }
    await _expectReviewActionsReachable(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('food removal identifies the complete target before Apply', (
    tester,
  ) async {
    const targetId = '00000000-0000-4000-8000-000000000011';
    const decoyId = '00000000-0000-4000-8000-000000000012';
    final sharedName = _foodNameAtLimit('Shared1');
    final state = EvaluatorState();
    state.foodEntries
      ..clear()
      ..addAll([
        FoodLogEntry(
          id: targetId,
          date: '2026-08-31',
          consumedAt: DateTime.utc(2026, 8, 31, 7, 45),
          foodName: sharedName,
          servingGrams: 325,
          calories: 610,
          proteinGrams: 42,
          carbsGrams: 68,
          fatGrams: 19,
          fiberGrams: 11.5,
          sugarGrams: 7.25,
          sodiumMg: 640,
        ),
        FoodLogEntry(
          id: decoyId,
          date: '2026-08-31',
          consumedAt: DateTime.utc(2026, 8, 31, 8, 45),
          foodName: sharedName,
          servingGrams: 325,
          calories: 610,
          proteinGrams: 42,
          carbsGrams: 68,
          fatGrams: 19,
          fiberGrams: 11.5,
          sugarGrams: 7.25,
          sodiumMg: 640,
        ),
      ]);
    final proposal = state.propose(
      ProposalKind.foodLogDelete,
      'Remove recovery meal',
      {'targetEntryId': state.foodEntries.first.id},
    );

    await _pumpProposalDetail(
      tester,
      state: state,
      proposalId: proposal.id,
      textScale: 1.5,
    );

    for (final detail in [
      '2026-08-31',
      '2026-08-31T07:45:00.000Z',
      sharedName,
      'Serving: 325 g · Calories: 610 kcal',
      'Protein: 42 g · Carbs: 68 g · Fat: 19 g',
      'Fibre: 11.5 g',
      'Sugar: 7.25 g',
      'Sodium: 640 mg',
    ]) {
      await _expectTextReachable(tester, detail);
    }
    expect(find.text('2026-08-31T08:45:00.000Z'), findsNothing);
    await _expectReviewActionsReachable(tester);

    final apply = find.ancestor(
      of: find.text('Apply'),
      matching: find.bySubtype<FilledButton>(),
    );
    await tester.scrollUntilVisible(
      apply,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(apply.hitTestable(), findsOneWidget);
    await tester.tap(apply);
    await tester.pumpAndSettle();

    expect(state.foodEntries.map((entry) => entry.id), [decoyId]);
    expect(state.proposalById(proposal.id)!.status, ProposalStatus.applied);
    expect(find.text('Apply'), findsNothing);
    expect(find.text('Dismiss'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('template review discloses persisted exercise details', (
    tester,
  ) async {
    final slug = '${List<String>.filled(17, 'loaded').join('-')}kg';
    final notes = _notesAtLimit();
    expect(slug.runes.length, 120);
    expect(notes.runes.length, 500);
    expect(notes.trim(), notes);

    final state = EvaluatorState();
    state.exercises = [
      ExerciseFixture(
        id: 'barbell-back-squat',
        slug: slug,
        name: 'Barbell Back Squat',
        muscles: ['Quads', 'Glutes'],
        loggingMode: 'weight_reps',
      ),
    ];
    final proposal = state.propose(
      ProposalKind.templateCreate,
      'Create strength template',
      {
        'plan': {
          'name': 'Strength detail audit',
          'description': 'Every stored exercise detail must be reviewable.',
          'exercises': [
            {
              'exerciseId': 'barbell-back-squat',
              'slug': slug,
              'sets': 3,
              'repsTarget': 8,
              'restTimerSeconds': 90,
              'weightTarget': 2000.0,
              'rpeTarget': 8,
              'notes': notes,
            },
          ],
        },
      },
    );

    await _pumpProposalDetail(
      tester,
      state: state,
      proposalId: proposal.id,
      textScale: 1.3,
    );

    for (final detail in [
      'Strength detail audit',
      'Every stored exercise detail must be reviewable.',
      'Barbell Back Squat',
      '3 sets · 8 reps · RPE 8 · 90s rest',
      'Slug: $slug',
      'Target weight: 2,000 kg',
      'Notes: $notes',
    ]) {
      await _expectTextReachable(tester, detail);
    }
    await _expectReviewActionsReachable(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

String _foodNameAtLimit(String word) =>
    '${List<String>.filled(25, word).join(' ')}!';

String _notesAtLimit() =>
    List<String>.generate(500, (index) => index % 12 == 10 ? ' ' : 'n').join();

Future<void> _pumpProposalDetail(
  WidgetTester tester, {
  required EvaluatorState state,
  required String proposalId,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    EvaluatorScope(
      state: state,
      child: MaterialApp(
        theme: evaluatorTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: ProposalDetailScreen(proposalId: proposalId),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(ProposalDetailScreen), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<void> _expectTextReachable(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.scrollUntilVisible(
    target,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  expect(target, findsOneWidget);
  expect(target.hitTestable(), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<void> _expectReviewActionsReachable(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  final actions = <Finder>[
    find.ancestor(
      of: find.text('Apply'),
      matching: find.bySubtype<FilledButton>(),
    ),
    find.ancestor(
      of: find.text('Dismiss'),
      matching: find.bySubtype<OutlinedButton>(),
    ),
  ];
  for (final action in actions) {
    await tester.scrollUntilVisible(action, 250, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(action.hitTestable(), findsOneWidget);
  }
  expect(tester.takeException(), isNull);
}
