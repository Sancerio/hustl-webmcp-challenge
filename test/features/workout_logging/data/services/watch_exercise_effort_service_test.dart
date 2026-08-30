import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hustl_app/features/health_sync/domain/models/heart_rate_sample.dart';
import 'package:hustl_app/features/workout_logging/data/services/watch_exercise_effort_service.dart';
import 'package:hustl_app/features/workout_logging/domain/models/exercise_timeline_event.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      WorkoutSession(
        id: 'fallback',
        name: 'Workout',
        startTime: DateTime.fromMillisecondsSinceEpoch(0),
        exercises: const [],
      ),
    );
  });

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('computes HR zones and 1–10 effort per exercise', () async {
    final repo = MockWorkoutRepository();
    when(
      () =>
          repo.updateWorkoutSession(any(), markDirty: any(named: 'markDirty')),
    ).thenAnswer((invocation) async {
      return invocation.positionalArguments.first as WorkoutSession;
    });

    // Intentionally not aligned to a 5s boundary to ensure initial samples
    // (within [startMs, startMs+5s)) are not dropped during bucketing.
    final startMs = DateTime(2026, 1, 1, 10).millisecondsSinceEpoch + 1234;
    final endMs = startMs + 10 * 60 * 1000; // 10 minutes

    const exercise = Exercise(
      name: 'Back Squat',
      muscles: [],
      slug: 'back-squat',
      kind: ExerciseKind.strength,
      loggingMode: ExerciseLoggingMode.weightReps,
    );
    const workoutExercise = WorkoutExercise(
      id: 'we1',
      exercise: exercise,
      sets: [],
    );

    final session = WorkoutSession(
      id: 's1',
      name: 'Workout',
      startTime: DateTime.fromMillisecondsSinceEpoch(startMs),
      endTime: DateTime.fromMillisecondsSinceEpoch(endMs),
      exercises: [workoutExercise],
      isCompleted: true,
      watchRecordingStartMs: startMs,
      watchRecordingEndMs: endMs,
      timelineEvents: [
        ExerciseTimelineEvent(
          tsMs: startMs,
          kind: ExerciseTimelineEventKind.select,
          workoutExerciseId: 'we1',
        ),
      ],
    );

    final samples = <HeartRateSample>[
      for (int t = startMs; t < endMs; t += 5000)
        HeartRateSample(
          time: DateTime.fromMillisecondsSinceEpoch(t),
          bpm: 180,
          source: 'UnitTest',
        ),
    ];

    final service = WatchExerciseEffortService(
      readHeartRateSamples: (_, __) async => samples,
    );

    final didUpdate = await service.computeAndPersist(
      session: session,
      workoutRepository: repo,
    );
    expect(didUpdate, isTrue);

    final captured =
        verify(
              () => repo.updateWorkoutSession(
                captureAny(),
                markDirty: any(named: 'markDirty'),
              ),
            ).captured.single
            as WorkoutSession;

    final metrics = captured.exercises.first.metrics;
    expect(metrics, isNotNull);
    final hr = metrics!['hr'] as Map;
    final effort = metrics['effort'] as Map;
    expect((hr['avgBpm'] as num).round(), 180);
    expect((hr['maxBpm'] as num).round(), 180);
    final zonesSec = hr['zonesSec'] as Map;
    expect(zonesSec['z5'], 600);
    expect(effort['hr1to10'], 8);
  });
}
