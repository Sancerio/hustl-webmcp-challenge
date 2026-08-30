import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/onboarding/domain/coach_readiness_service.dart';
import 'package:hustl_app/features/onboarding/domain/onboarding_proposal_gate.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';

class _FakeWorkoutRepo implements WorkoutRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubReadinessService extends CoachReadinessService {
  _StubReadinessService(this._snapshot)
    : super(workoutRepository: _FakeWorkoutRepo());

  final CoachReadinessSnapshot _snapshot;

  @override
  Future<CoachReadinessSnapshot> snapshot() async => _snapshot;
}

// Build a snapshot directly (threshold-agnostic) so the gate's own thresholds
// are what's under test, not the readiness curve.
CoachReadinessSnapshot _snap({
  required int workouts,
  required double readiness,
}) {
  return CoachReadinessSnapshot(
    readiness: readiness,
    workouts: workouts,
    meals: 0,
    healthConnected: false,
    approvedProposals: 0,
    filledCount: workouts > 0 ? 1 : 0,
    note: '',
  );
}

const _above = OnboardingProposalGate.readinessThreshold + 0.05;
const _below = OnboardingProposalGate.readinessThreshold - 0.05;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = PreferencesService();
    prefs.resetForTests();
    await prefs.init();
  });

  OnboardingProposalGate gate(CoachReadinessSnapshot snapshot) =>
      OnboardingProposalGate(
        preferences: prefs,
        readinessService: _StubReadinessService(snapshot),
      );

  test(
    'eligible when not seen, >1 workout, and readiness above the floor',
    () async {
      expect(
        await gate(_snap(workouts: 4, readiness: _above)).isEligible(),
        isTrue,
      );
    },
  );

  test(
    'not eligible on the first session (only one completed workout)',
    () async {
      expect(
        await gate(_snap(workouts: 1, readiness: _above)).isEligible(),
        isFalse,
      );
    },
  );

  test('not eligible once already seen (once-only)', () async {
    await prefs.setOnboardingProposalSeen(true);
    expect(
      await gate(_snap(workouts: 4, readiness: _above)).isEligible(),
      isFalse,
    );
  });

  test('not eligible when readiness is below the floor', () async {
    expect(
      await gate(_snap(workouts: 4, readiness: _below)).isEligible(),
      isFalse,
    );
  });
}
