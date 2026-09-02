import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_evaluator/src/app.dart';
import 'package:hustl_evaluator/src/model/evaluator_state.dart';
import 'package:hustl_evaluator/src/model/models.dart';
import 'package:hustl_evaluator/src/webmcp/tool.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<ExerciseFixture> fixtures;
  setUpAll(() async {
    final fixtureState = EvaluatorState();
    await fixtureState.loadFixtures();
    fixtures = fixtureState.exercises;
  });

  testWidgets(
    '/demo canonicalization registers only the canonical Train catalog',
    (tester) async {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.defaultRouteNameTestValue = '/demo';
      addTearDown(() {
        binding.platformDispatcher.defaultRouteNameTestValue = '/';
      });
      final state = EvaluatorState()..exercises = fixtures;
      final host = _QuotaHost(
        registrationDelay: const Duration(milliseconds: 50),
      );

      await tester.pumpWidget(EvaluatorApp(state: state, toolHost: host));
      await _settle(tester);

      expect(find.text('Train with context'), findsOneWidget);
      expect(host.activeNames.toSet(), {
        'hustl_get_today_context',
        'hustl_open_surface',
        'hustl_get_training_context',
        'hustl_get_workout_history',
        'hustl_get_exercise_history',
      });
      expect(host.registrationAttempts, 5);

      final retainedTraining = host.activeDefinition(
        'hustl_get_training_context',
      );
      final openRecovery = host.activeDefinition('hustl_open_surface').handler(
        const {'surface': 'recovery'},
      );
      await _settle(tester);
      expect(await openRecovery, {'status': 'opened', 'route': '/health'});
      expect(await retainedTraining.handler(const {}), {
        'status': 'unavailable',
        'code': 'stale_route',
      });
      expect(host.activeNames.toSet(), {
        'hustl_get_today_context',
        'hustl_open_surface',
        'hustl_get_recovery_context',
      });

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('normal shell keeps proposal decisions human-owned', (
    tester,
  ) async {
    final state = EvaluatorState();
    state.exercises = fixtures;
    await tester.pumpWidget(EvaluatorApp(state: state));
    await _settle(tester);

    expect(find.text('Train with context'), findsOneWidget);
    expect(find.textContaining('Demo data'), findsNothing);
    expect(find.textContaining('Reset demo'), findsNothing);
    expect(find.textContaining('Confirm goal'), findsNothing);
    final proposal = state.propose(
      ProposalKind.nutritionTargets,
      'Nutrition target update',
      const {
        'caloriesTarget': 2100,
        'proteinTarget': 180.0,
        'carbsTarget': 205.0,
        'fatTarget': 65.0,
      },
    );
    await _settle(tester);

    await tester.tap(find.text('Coach'));
    await _settle(tester);
    await tester.tap(find.text(proposal.title));
    await _settle(tester);
    expect(find.text('Calories'), findsOneWidget);
    expect(find.text('2,400 kcal'), findsOneWidget);
    expect(find.text('2,100 kcal'), findsOneWidget);
    expect(find.textContaining('caloriesTarget'), findsNothing);
    expect(find.text('Apply'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);

    await tester.tap(find.text('Apply'));
    await _settle(tester);
    expect(state.nutritionTargets.calories, 2100);
    expect(find.text('Apply'), findsNothing);
    expect(find.text('Dismiss'), findsNothing);
    expect(find.textContaining('terminal'), findsOneWidget);

    expect(find.text('Continue to Train'), findsOneWidget);
    await tester.tap(find.text('Continue to Train'));
    await _settle(tester);
    expect(find.text('118 / 180 g'), findsOneWidget);

    final foodProposal = state.propose(
      ProposalKind.foodLog,
      'Add snack',
      const {
        'date': '2026-08-31',
        'items': <Map<String, Object?>>[
          {
            'foodName': 'Apple',
            'servingGrams': 100.0,
            'calories': 52.0,
            'proteinGrams': 0.3,
            'carbsGrams': 14.0,
            'fatGrams': 0.2,
          },
        ],
      },
    );
    state.apply(foodProposal.id);
    await _settle(tester);
    await tester.tap(find.text('Nutrition'));
    await _settle(tester);
    expect(find.text('1,482 / 2,100 kcal'), findsOneWidget);
    expect(find.text('3 meals logged'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Coach decisions preserve the real shell catalog under quota', (
    tester,
  ) async {
    final state = EvaluatorState();
    state.exercises = fixtures;
    final applyProposal = state
        .propose(ProposalKind.nutritionTargets, 'Apply review', const {
          'caloriesTarget': 2100,
          'proteinTarget': 180.0,
          'carbsTarget': 205.0,
          'fatTarget': 65.0,
        });
    final dismissProposal = state
        .propose(ProposalKind.nutritionTargets, 'Dismiss review', const {
          'caloriesTarget': 2200,
          'proteinTarget': 175.0,
          'carbsTarget': 225.0,
          'fatTarget': 70.0,
        });
    final host = _QuotaHost();
    await tester.pumpWidget(EvaluatorApp(state: state, toolHost: host));
    await _settle(tester);

    await tester.tap(find.text('Coach'));
    await _settle(tester);
    expect(host.activeNames, hasLength(7));
    host.leaveSuccessfulRegistrations(2);
    final coachRegistrationAttempts = host.registrationAttempts;

    await tester.tap(find.text(applyProposal.title));
    await _settle(tester);
    await tester.tap(find.text('Apply'));
    await _settle(tester);
    expect(
      state.proposalById(applyProposal.id)!.status,
      ProposalStatus.applied,
    );
    expect(host.activeNames, hasLength(7));
    expect(host.registrationAttempts, coachRegistrationAttempts);

    await tester.tap(find.text('Back to Coach'));
    await _settle(tester);
    expect(host.activeNames, hasLength(7));
    expect(host.registrationAttempts, coachRegistrationAttempts);

    await tester.tap(find.text(dismissProposal.title));
    await _settle(tester);
    await tester.tap(find.text('Dismiss'));
    await _settle(tester);
    expect(
      state.proposalById(dismissProposal.id)!.status,
      ProposalStatus.rejected,
    );
    expect(host.activeNames, hasLength(7));
    expect(host.registrationAttempts, coachRegistrationAttempts);

    await tester.tap(find.text('Back to Coach'));
    await _settle(tester);
    expect(host.activeNames, hasLength(7));
    expect(host.registrationAttempts, coachRegistrationAttempts);
    expect(host.supported, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'registered navigation reports the route opened by the real app',
    (tester) async {
      final state = EvaluatorState();
      state.exercises = fixtures;
      final proposal = state
          .propose(ProposalKind.nutritionTargets, 'Open this review', const {
            'caloriesTarget': 2100,
            'proteinTarget': 180.0,
            'carbsTarget': 205.0,
            'fatTarget': 65.0,
          });
      final host = _QuotaHost();
      await tester.pumpWidget(EvaluatorApp(state: state, toolHost: host));
      await _settle(tester);
      final retainedTraining = host.activeDefinition(
        'hustl_get_training_context',
      );

      final openCoach = host.activeDefinition('hustl_open_surface').handler(
        const {'surface': 'coach'},
      );
      await _settle(tester);
      expect(await openCoach, {'status': 'opened', 'route': '/proposals'});
      expect(find.text('Coach'), findsWidgets);
      expect(find.text(proposal.title), findsOneWidget);
      expect(host.activeNames, hasLength(7));
      expect(await retainedTraining.handler(const {}), {
        'status': 'unavailable',
        'code': 'stale_route',
      });

      final coachRegistrationAttempts = host.registrationAttempts;
      final openProposal = host.activeDefinition('hustl_open_proposal').handler(
        {'proposalId': proposal.id},
      );
      await _settle(tester);
      expect(await openProposal, {
        'status': 'opened',
        'proposalId': proposal.id,
        'route': '/proposals/${proposal.id}',
      });
      expect(find.text(proposal.title), findsWidgets);
      expect(find.text('Apply'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
      expect(host.activeNames, hasLength(7));
      expect(host.registrationAttempts, coachRegistrationAttempts);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('proposal routes always provide a state-preserving Train exit', (
    tester,
  ) async {
    final state = EvaluatorState()..exercises = fixtures;
    final proposal = state.propose(
      ProposalKind.templateCreate,
      'Four-day strength plan',
      const {
        'plan': {
          'name': 'Four-day strength plan',
          'exercises': <Map<String, Object?>>[],
        },
      },
    );
    final host = _QuotaHost();
    await tester.pumpWidget(EvaluatorApp(state: state, toolHost: host));
    await _settle(tester);

    await tester.tap(find.text('Coach'));
    await _settle(tester);
    await tester.tap(find.text(proposal.title));
    await _settle(tester);
    expect(find.text('Return to Train'), findsOneWidget);
    final retainedCoach = host.activeDefinition('hustl_get_coach_activity');

    await tester.tap(find.text('Return to Train'));
    await _settle(tester);
    expect(find.text('Train with context'), findsOneWidget);
    expect(state.proposalById(proposal.id)!.status, ProposalStatus.pending);
    expect(host.activeNames.toSet(), {
      'hustl_get_today_context',
      'hustl_open_surface',
      'hustl_get_training_context',
      'hustl_get_workout_history',
      'hustl_get_exercise_history',
    });
    expect(await retainedCoach.handler(const {}), {
      'status': 'unavailable',
      'code': 'stale_route',
    });

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('a refreshed proposal deep link can return to Train', (
    tester,
  ) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.defaultRouteNameTestValue =
        '/proposals/proposal-missing';
    addTearDown(() {
      binding.platformDispatcher.defaultRouteNameTestValue = '/';
    });
    final state = EvaluatorState()..exercises = fixtures;
    await tester.pumpWidget(EvaluatorApp(state: state));
    await _settle(tester);

    expect(find.text('Proposal not found'), findsOneWidget);
    expect(
      find.text(
        'The evaluator resets its synthetic proposals after a refresh.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Return to Train'));
    await _settle(tester);
    expect(find.text('Train with context'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 300));
}

class _QuotaHost implements ToolHost {
  _QuotaHost({this.registrationDelay = Duration.zero});

  final Duration registrationDelay;
  final List<_QuotaRegistration> _registrations = [];
  int? _successfulRegistrationLimit;
  int registrationAttempts = 0;
  int successfulRegistrations = 0;
  bool _supported = true;

  @override
  bool get supported => _supported;

  List<String> get activeNames => [
    for (final registration in _registrations)
      if (!registration.disposed) registration.definition.name,
  ];

  ToolDefinition activeDefinition(String name) => _registrations
      .where(
        (registration) =>
            !registration.disposed && registration.definition.name == name,
      )
      .single
      .definition;

  void leaveSuccessfulRegistrations(int remaining) {
    _successfulRegistrationLimit = successfulRegistrations + remaining;
  }

  @override
  Future<ToolRegistration?> register(ToolDefinition definition) async {
    registrationAttempts += 1;
    if (registrationDelay > Duration.zero) {
      await Future<void>.delayed(registrationDelay);
    }
    if (_successfulRegistrationLimit case final int limit
        when successfulRegistrations >= limit) {
      _supported = false;
      return null;
    }
    final registration = _QuotaRegistration(definition);
    _registrations.add(registration);
    successfulRegistrations += 1;
    return registration;
  }
}

class _QuotaRegistration implements ToolRegistration {
  _QuotaRegistration(this.definition);

  final ToolDefinition definition;
  bool disposed = false;

  @override
  void dispose() => disposed = true;
}
