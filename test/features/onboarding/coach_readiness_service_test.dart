import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/health_sync/domain/repositories/health_metrics_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/food_log_entry.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import 'package:hustl_app/features/onboarding/domain/coach_readiness_service.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';

WorkoutSession _session({required bool completed, String id = 's'}) =>
    WorkoutSession(
      id: id,
      name: 'Workout',
      startTime: DateTime(2026, 6, 26, 9),
      exercises: const [],
      isCompleted: completed,
    );

void main() {
  group('CoachReadinessService.snapshot', () {
    test('empty/null repos degrade to safe zeros and never throw', () async {
      final service = CoachReadinessService(
        workoutRepository: _FakeWorkoutRepo(),
      );

      final snap = await service.snapshot();

      expect(snap.readiness, 0.0);
      expect(snap.workouts, 0);
      expect(snap.meals, 0);
      expect(snap.healthConnected, isFalse);
      expect(snap.approvedProposals, 0);
      expect(snap.filledCount, 0);
      expect(snap.note, contains('Log meals'));
      expect(snap.note, contains('connect Health'));
    });

    test('a throwing workout repo still yields zeros, never throws', () async {
      final service = CoachReadinessService(
        workoutRepository: _FakeWorkoutRepo(throws: true),
        foodLogRepository: _FakeFoodLogRepo(throws: true),
        healthMetricsRepository: _FakeHealthRepo(throws: true),
      );

      final snap = await service.snapshot();

      expect(snap.workouts, 0);
      expect(snap.meals, 0);
      expect(snap.healthConnected, isFalse);
      expect(snap.readiness, 0.0);
      expect(snap.filledCount, 0);
    });

    test('counts only completed workouts and fills that pillar', () async {
      final service = CoachReadinessService(
        workoutRepository: _FakeWorkoutRepo(
          sessions: [
            _session(completed: true, id: 'a'),
            _session(completed: true, id: 'b'),
            _session(completed: true, id: 'c'),
            _session(completed: false, id: 'd'),
          ],
        ),
      );

      final snap = await service.snapshot();

      expect(snap.workouts, 3);
      expect(snap.readiness, greaterThan(0.0));
      expect(snap.filledCount, 1);
    });

    test(
      'healthConnected reflects granted permissions and counts a pillar',
      () async {
        final service = CoachReadinessService(
          workoutRepository: _FakeWorkoutRepo(),
          healthMetricsRepository: _FakeHealthRepo(connected: true),
        );

        final snap = await service.snapshot();

        expect(snap.healthConnected, isTrue);
        expect(snap.filledCount, 1);
        // Health is its own 0.15 band of the score.
        expect(snap.readiness, closeTo(0.15, 1e-9));
        // Meals still missing, Health no longer missing.
        expect(snap.note, contains('Log meals'));
        expect(snap.note, isNot(contains('connect Health')));
      },
    );

    test('meals come from today logs and degrade to 0 on failure', () async {
      final ok = CoachReadinessService(
        workoutRepository: _FakeWorkoutRepo(),
        foodLogRepository: _FakeFoodLogRepo(count: 2),
      );
      expect((await ok.snapshot()).meals, 2);

      final broken = CoachReadinessService(
        workoutRepository: _FakeWorkoutRepo(),
        foodLogRepository: _FakeFoodLogRepo(throws: true),
      );
      expect((await broken.snapshot()).meals, 0);
    });
  });
}

class _FakeWorkoutRepo implements WorkoutRepository {
  _FakeWorkoutRepo({this.sessions = const [], this.throws = false});

  final List<WorkoutSession> sessions;
  final bool throws;

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (throws) throw Exception('boom');
    return sessions;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFoodLogRepo implements FoodLogRepository {
  _FakeFoodLogRepo({this.count = 0, this.throws = false});

  final int count;
  final bool throws;

  @override
  Future<List<FoodLogEntry>> getLogsForRange(DateTime start, DateTime end) =>
      throw UnimplementedError();

  @override
  Future<List<FoodLogEntry>> getLogsForDate(DateTime date) async {
    if (throws) throw Exception('boom');
    return List<FoodLogEntry>.generate(
      count,
      (i) => FoodLogEntry(
        id: 'e$i',
        date: date,
        loggedAt: date,
        servingGrams: 100,
        calories: 200,
        proteinGrams: 10,
        carbsGrams: 20,
        fatGrams: 5,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHealthRepo implements HealthMetricsRepository {
  _FakeHealthRepo({this.connected = false, this.throws = false});

  final bool connected;
  final bool throws;

  @override
  Future<HealthPermissionsStatus> getPermissionsStatus() async {
    if (throws) throw Exception('boom');
    return HealthPermissionsStatus(
      hasPermissions: connected,
      isServiceAvailable: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
