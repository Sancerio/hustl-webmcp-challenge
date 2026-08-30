import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/webmcp/today_context_service.dart';
import 'package:hustl_app/features/ai_proposals/domain/models/proposal_summary.dart';
import 'package:hustl_app/features/ai_proposals/domain/repositories/proposals_repository.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/domain/models/recovery_signal_availability.dart';
import 'package:hustl_app/features/health_sync/domain/repositories/health_metrics_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/nutrition_target_plan.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockWorkoutRepository extends Mock
    implements ReadOnlyWorkoutRepository {}

class _MockHealthRepository extends Mock implements HealthMetricsRepository {}

class _MockFoodLogRepository extends Mock
    implements ReadOnlyFoodLogRepository {}

class _MockNutritionTargetsRepository extends Mock
    implements ReadOnlyNutritionTargetsRepository {}

class _MockProposalsRepository extends Mock implements ProposalsRepository {}

class _MockProposalSummary extends Mock implements ProposalSummary {}

void main() {
  late _MockWorkoutRepository workouts;
  late _MockHealthRepository health;
  late _MockFoodLogRepository food;
  late _MockNutritionTargetsRepository targets;
  late _MockProposalsRepository proposals;
  final now = DateTime(2026, 8, 26, 9, 30);

  setUpAll(() {
    registerFallbackValue(DateTime(2000));
  });

  setUp(() {
    workouts = _MockWorkoutRepository();
    health = _MockHealthRepository();
    food = _MockFoodLogRepository();
    targets = _MockNutritionTargetsRepository();
    proposals = _MockProposalsRepository();

    when(() => workouts.getWorkoutSnapshotReadOnly(limit: 25)).thenAnswer(
      (_) async =>
          const ReadOnlyWorkoutSnapshot(activeSession: null, sessions: []),
    );
    when(
      () => health.loadSnapshot(
        start: any(named: 'start'),
        end: any(named: 'end'),
      ),
    ).thenAnswer((_) async => _healthSnapshot(now));
    when(
      () => food.getLogsForDateReadOnly(any()),
    ).thenAnswer((_) async => const []);
    when(
      () => targets.getCurrentPlanReadOnly(any()),
    ).thenAnswer((_) async => null);
    when(
      () => proposals.listPending(limit: 50),
    ).thenAnswer((_) async => const []);
  });

  TodayContextService service() => TodayContextService(
    workoutRepository: workouts,
    healthRepository: health,
    foodLogRepository: food,
    nutritionTargetsRepository: targets,
    proposalsRepository: proposals,
    clock: () => now,
  );

  test('aggregates all four pillars from existing repositories', () async {
    final older = _session(
      'older',
      'Upper A',
      now.subtract(const Duration(days: 5)),
    );
    final latest = _session(
      'latest',
      'Full Body',
      now.subtract(const Duration(days: 1)),
    );
    when(() => workouts.getWorkoutSnapshotReadOnly(limit: 25)).thenAnswer(
      (_) async => ReadOnlyWorkoutSnapshot(
        activeSession: null,
        sessions: [older, latest],
      ),
    );
    when(
      () => health.loadSnapshot(
        start: any(named: 'start'),
        end: any(named: 'end'),
      ),
    ).thenAnswer(
      (_) async => _healthSnapshot(
        now,
        recovery: DailyRecoverySnapshot(
          date: now,
          sleepDurationMinutes: 450,
          hrvValue: 58,
          readinessScore: 82,
          flowBand: RecoveryFlowBand.charged,
          confidence: RecoveryConfidence.high,
          baselineCoverageDays: 20,
        ),
        availability: const RecoverySignalAvailability(
          hrv: true,
          restingHeartRate: true,
          sleep: true,
        ),
      ),
    );
    when(() => food.getLogsForDateReadOnly(any())).thenAnswer(
      (_) async => [_food(now, calories: 625, protein: 42, carbs: 71, fat: 18)],
    );
    when(() => targets.getCurrentPlanReadOnly(any())).thenAnswer(
      (_) async => NutritionTargetPlan(
        weekStart: now,
        mode: 'auto',
        goal: 'maintain',
        caloriesTarget: 2200,
        proteinTarget: 150,
        carbsTarget: 240,
        fatTarget: 70,
      ),
    );
    when(
      () => proposals.listPending(limit: 50),
    ).thenAnswer((_) async => [_MockProposalSummary(), _MockProposalSummary()]);

    final result = await service().load();
    final json = result.toJson();

    expect(result.status, 'ready');
    expect(result.training.state, 'repeat_recommended');
    expect(result.training.recommendedSessionId, 'latest');
    expect(result.recovery.state, 'available');
    expect(result.recovery.score, 82);
    expect(result.recovery.sleepHours, 7.5);
    expect(result.nutrition.state, 'tracking');
    expect(result.nutrition.calories, 625);
    expect(result.nutrition.caloriesTarget, 2200);
    expect(result.coach.pendingProposalCount, 2);
    expect(result.unavailableSections, isEmpty);
    expect(json['availableSurfaces'], [
      'train',
      'recovery',
      'nutrition',
      'coach',
    ]);
    expect(result.asOf, matches(RegExp(r'[+-]\d{2}:\d{2}$')));
    verify(() => targets.getCurrentPlanReadOnly(any())).called(1);
  });

  test('successful empty nutrition is a real zero', () async {
    final result = await service().load();

    expect(result.nutrition.state, 'empty');
    expect(result.nutrition.calories, 0);
    expect(result.nutrition.proteinGrams, 0);
    expect(result.nutrition.carbsGrams, 0);
    expect(result.nutrition.fatGrams, 0);
    expect(result.unavailableSections, isEmpty);
  });

  test(
    'failed nutrition stays missing and makes the response partial',
    () async {
      when(
        () => food.getLogsForDateReadOnly(any()),
      ).thenThrow(StateError('private detail'));

      final result = await service().load();
      final encoded = result.toJson().toString();

      expect(result.status, 'partial');
      expect(result.nutrition.state, 'unavailable');
      expect(result.nutrition.calories, isNull);
      expect(result.unavailableSections, contains('nutrition'));
      expect(encoded, isNot(contains('private detail')));
    },
  );

  test('active session takes precedence over repeat recommendation', () async {
    final active = _session('active', 'Push Day', now, completed: false);
    when(() => workouts.getWorkoutSnapshotReadOnly(limit: 25)).thenAnswer(
      (_) async =>
          ReadOnlyWorkoutSnapshot(activeSession: active, sessions: [active]),
    );

    final result = await service().load();

    expect(result.training.state, 'active');
    expect(result.training.activeSessionId, 'active');
    expect(result.unavailableSections, isNot(contains('training')));
  });

  test('calibrating recovery withholds its score', () async {
    when(
      () => health.loadSnapshot(
        start: any(named: 'start'),
        end: any(named: 'end'),
      ),
    ).thenAnswer(
      (_) async => _healthSnapshot(
        now,
        recovery: DailyRecoverySnapshot(
          date: now,
          hrvValue: 42,
          readinessScore: 67,
          baselineCoverageDays: 4,
          isCalibrating: true,
        ),
        availability: const RecoverySignalAvailability(hrv: true),
      ),
    );

    final result = await service().load();

    expect(result.recovery.state, 'calibrating');
    expect(result.recovery.score, isNull);
    expect(result.recovery.baselineCoverageDays, 4);
  });
}

HealthSnapshot _healthSnapshot(
  DateTime now, {
  DailyRecoverySnapshot? recovery,
  RecoverySignalAvailability availability = RecoverySignalAvailability.empty,
}) => HealthSnapshot(
  rangeStart: now.subtract(const Duration(days: 56)),
  rangeEnd: now,
  metrics: const [],
  nutritionEntries: const [],
  dailySummaries: const [],
  recoverySnapshots: recovery == null ? const [] : [recovery],
  lastSyncedAt: now,
  signalAvailability: availability,
);

WorkoutSession _session(
  String id,
  String name,
  DateTime start, {
  bool completed = true,
}) => WorkoutSession(
  id: id,
  name: name,
  startTime: start,
  endTime: completed ? start.add(const Duration(hours: 1)) : null,
  exercises: const [],
  isCompleted: completed,
);

FoodLogEntry _food(
  DateTime now, {
  required double calories,
  required double protein,
  required double carbs,
  required double fat,
}) => FoodLogEntry(
  id: 'food-1',
  date: now,
  loggedAt: now,
  servingGrams: 250,
  calories: calories,
  proteinGrams: protein,
  carbsGrams: carbs,
  fatGrams: fat,
);
