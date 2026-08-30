import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/domain/models/recovery_signal_availability.dart'
    show HealthProviderAvailability;
import 'package:hustl_app/features/health_sync/domain/repositories/health_metrics_repository.dart';
import 'package:hustl_app/features/health_sync/domain/usecases/load_latest_readiness.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/presentation/screens/workout_summary_screen.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/summary/strain_recovery_note.dart';
import 'package:hustl_app/features/workout_templates/domain/models/workout_template.dart';
import 'package:hustl_app/features/workout_templates/domain/repositories/template_repository.dart';

/// Repo whose [loadSnapshot] always yields a confident, banded recovery
/// snapshot — so [LoadLatestReadinessUseCase] returns a non-null readiness and
/// the post-workout note would render IF the screen asks for it.
class _RecoveryRepo implements HealthMetricsRepository {
  @override
  Future<HealthSnapshot> loadSnapshot({
    required DateTime start,
    required DateTime end,
    bool forceRefresh = false,
  }) async => HealthSnapshot(
    rangeStart: start,
    rangeEnd: end,
    metrics: const [],
    nutritionEntries: const [],
    dailySummaries: const [],
    recoverySnapshots: [
      DailyRecoverySnapshot(
        date: DateTime.now(),
        sleepPerformanceScore: 70,
        hrvValue: 48,
        hrvKind: HrvKind.sdnn,
        restingHeartRateBpm: 60,
        readinessScore: 36,
        recoveryScore: 34,
        strainScore: 16,
        baselineCoverageDays: 21,
        band: RecoveryFlowBand.recharge.legacyBand,
        flowBand: RecoveryFlowBand.recharge,
        confidence: RecoveryConfidence.high,
      ),
    ],
    lastSyncedAt: DateTime.now(),
  );

  @override
  Future<HealthPermissionsStatus> getPermissionsStatus() async =>
      const HealthPermissionsStatus(
        hasPermissions: true,
        isServiceAvailable: true,
      );

  @override
  Future<HealthPermissionsStatus> requestPermissions() async =>
      const HealthPermissionsStatus(
        hasPermissions: true,
        isServiceAvailable: true,
      );

  @override
  Future<HealthProviderAvailability> getProviderAvailability() async =>
      HealthProviderAvailability.available;

  @override
  Future<void> installHealthConnect() async {}

  @override
  Future<void> clearCache() async {}

  @override
  Future<void> resetPermissionDenialFlag() async {}
}

class _TemplateRepoFake implements TemplateRepository {
  @override
  Future<List<WorkoutTemplate>> getWorkoutTemplates() async => const [];
  @override
  Future<void> deleteWorkoutTemplate(String id) async {}
  @override
  Future<WorkoutTemplate?> getWorkoutTemplate(String id) async => null;
  @override
  Future<WorkoutTemplate> createWorkoutTemplate(WorkoutTemplate t) async => t;
  @override
  Future<WorkoutTemplate> updateWorkoutTemplate(WorkoutTemplate t) async => t;
}

class _WorkoutRepoFake implements WorkoutRepository {
  _WorkoutRepoFake(this.session);
  final WorkoutSession session;

  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async => session;
  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => [session];
  @override
  Future<WorkoutSession?> getLatestActiveSession() async => null;
  @override
  Future<void> deleteWorkoutSession(String id) async {}
  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession s) async => s;
  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession s, {
    bool markDirty = true,
  }) async => s;
  @override
  Future<WorkoutSession> addExerciseToSession(String s, WorkoutExercise e) =>
      Future.error(UnimplementedError());
  @override
  Future<WorkoutExercise> addSetToExercise(String s, String e, WorkoutSet x) =>
      Future.error(UnimplementedError());
  @override
  Future<WorkoutSession> completeWorkoutSession(String s) =>
      Future.error(UnimplementedError());
  @override
  Future<List<WorkoutSet>?> getPreviousExerciseSets(
    String name, {
    String? exerciseSlug,
  }) async => null;
  @override
  Future<void> recomputeAllPrFlags() async {}
  @override
  Future<bool> checkIfSetIsPR(
    String name,
    WorkoutSet set, {
    String? exerciseSlug,
  }) async => false;
  @override
  Future<DateTime?> getLastPerformedDate(
    String name, {
    String? exerciseSlug,
  }) async => null;
  @override
  Future<ExercisePr?> getExercisePr(
    String name, {
    String? exerciseSlug,
  }) async => null;
  @override
  Future<WorkoutSession> updateExerciseInSession(
    String s,
    String e,
    WorkoutExercise x,
  ) => Future.error(UnimplementedError());
  @override
  Future<WorkoutExercise> updateSetInExercise(
    String s,
    String e,
    int i,
    WorkoutSet x,
  ) => Future.error(UnimplementedError());
  @override
  Future<WorkoutSession> removeExerciseFromSession(String s, String e) =>
      Future.error(UnimplementedError());
}

WorkoutSession _session() => WorkoutSession(
  id: 's1',
  name: 'Session',
  // An OLD workout (days ago) — its summary must never carry today's recovery.
  startTime: DateTime(2024, 1, 1, 8),
  endTime: DateTime(2024, 1, 1, 9),
  exercises: const [
    WorkoutExercise(
      id: 'e1',
      exercise: Exercise(name: 'Bench', muscles: []),
      sets: [WorkoutSet(id: 'set1', weight: 100, reps: 5, isCompleted: true)],
    ),
  ],
);

Future<void> _registerDi() async {
  await GetIt.instance.reset(dispose: true);
  GetIt.instance.registerSingleton<TemplateRepository>(_TemplateRepoFake());
  GetIt.instance.registerSingleton<WorkoutRepository>(
    _WorkoutRepoFake(_session()),
  );
  GetIt.instance.registerSingleton<LoadLatestReadinessUseCase>(
    LoadLatestReadinessUseCase(_RecoveryRepo()),
  );
}

void main() {
  tearDown(() => GetIt.instance.reset(dispose: true));

  testWidgets('just-finished summary shows the post-workout recovery note', (
    tester,
  ) async {
    await _registerDi();

    await tester.pumpWidget(
      const MaterialApp(
        home: WorkoutSummaryScreen(sessionId: 's1', justFinished: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StrainRecoveryNote), findsOneWidget);
  });

  testWidgets(
    'historical summary (default / not just-finished) never shows today\'s '
    'recovery note',
    (tester) async {
      await _registerDi();

      await tester.pumpWidget(
        const MaterialApp(
          // Default justFinished == false → the History/deep-link path.
          home: WorkoutSummaryScreen(sessionId: 's1'),
        ),
      );
      await tester.pumpAndSettle();

      // The summary rendered, but with no stale recovery annotation.
      expect(find.text('Workout complete'), findsOneWidget);
      expect(find.byType(StrainRecoveryNote), findsNothing);
    },
  );
}
