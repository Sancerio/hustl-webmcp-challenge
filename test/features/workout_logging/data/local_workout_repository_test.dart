import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/exercise_library/domain/repositories/exercise_repository.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hustl_app/features/workout_logging/data/repositories/local_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/exercise_timeline_event.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/token_storage_io.dart' as token;
import 'package:hustl_app/features/health_sync/data/writeback/workout_writeback_coordinator.dart';

class _FakeExerciseRepo implements ExerciseRepository {
  final List<Exercise> _all = const [
    Exercise(name: 'Bench Press', muscles: ['Chest']),
    Exercise(name: 'Squat', muscles: ['Quads']),
    Exercise(
      name: 'Run',
      muscles: ['Cardio'],
      loggingMode: ExerciseLoggingMode.distanceDuration,
    ),
  ];
  bool throwOnFetch = false;
  int fetchCount = 0;

  @override
  Future<List<Exercise>> getAllExercises() async {
    fetchCount += 1;
    if (throwOnFetch) {
      throw Exception('offline');
    }
    return _all;
  }

  @override
  Future<List<Exercise>> getExercisesByMuscle(String muscle) async => _all
      .where(
        (e) => e.muscles.any(
          (m) => m.toLowerCase().contains(muscle.toLowerCase()),
        ),
      )
      .toList();

  @override
  Future<List<Exercise>> searchExercises(String query) async => _all
      .where((e) => e.name.toLowerCase().contains(query.toLowerCase()))
      .toList();
  @override
  Future<String?> regenerateThumbnail(Exercise exercise) async => null;
  @override
  Future<String?> regenerateThumbnailDebug(
    Exercise exercise, {
    String? steerImageUrl,
    String? steerImageDataUrl,
  }) async => null;
  @override
  Future<Exercise> generateOverviewDebug(Exercise exercise) async => exercise;
  @override
  Future<Exercise> generateHowToDebug(Exercise exercise) async => exercise;
  @override
  Future<List<Exercise>> getCustomExercises() async => const [];
  @override
  Future<List<Exercise>> getSharedExercises({String? search}) async => const [];
  @override
  Future<Exercise> addCustomExercise(Exercise exercise) async => exercise;
  @override
  Future<void> removeCustomExercise(Exercise exercise) async {}
}

class _MockWorkoutWritebackCoordinator extends Mock
    implements WorkoutWritebackCoordinator {}

class _ThrowingTokenStorage extends token.TokenStorage {
  @override
  Future<String?> getAccessToken() async => throw Exception('keychain failed');
}

class _DeferredExerciseRepo extends _FakeExerciseRepo {
  final Completer<void> started = Completer<void>();
  final Completer<List<Exercise>> finish = Completer<List<Exercise>>();

  @override
  Future<List<Exercise>> getAllExercises() {
    if (!started.isCompleted) started.complete();
    return finish.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final getIt = GetIt.instance;
  setUpAll(() {
    registerFallbackValue(
      WorkoutSession(
        id: 'fallback',
        name: 'Fallback',
        startTime: DateTime.fromMillisecondsSinceEpoch(0),
        exercises: const [],
      ),
    );
  });
  setUp(() async {
    await getIt.reset();
    getIt.registerLazySingleton<ExerciseRepository>(() => _FakeExerciseRepo());
    SharedPreferences.setMockInitialValues({});
    getIt.registerSingleton<PreferencesService>(PreferencesService());
    await getIt<PreferencesService>().init();
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('create, update, complete, and delete session', () async {
    final repo = LocalWorkoutRepository();

    final session = await repo.createWorkoutSession(
      WorkoutSession(
        id: 'tmp',
        name: 'Push Day',
        startTime: DateTime.now(),
        exercises: const [],
      ),
    );

    expect(session.id.isNotEmpty, true);

    const bench = WorkoutExercise(
      id: 'ex1',
      exercise: Exercise(name: 'Bench Press', muscles: ['Chest']),
      sets: [],
    );
    final updated = await repo.addExerciseToSession(session.id, bench);
    expect(updated.exercises.length, 1);

    const set1 = WorkoutSet(
      id: 's1',
      weight: 100,
      reps: 5,
      isCompleted: true,
      isPr: false,
    );
    final exAfterSet = await repo.addSetToExercise(updated.id, 'ex1', set1);
    expect(exAfterSet.sets.length, 1);

    final completed = await repo.completeWorkoutSession(updated.id);
    expect(completed.isCompleted, true);

    await repo.deleteWorkoutSession(updated.id);
    final fetched = await repo.getWorkoutSession(updated.id);
    expect(fetched, isNull);

    repo.dispose();
  });

  test('updateSetsInExercise applies multiple set replacements', () async {
    final repo = LocalWorkoutRepository();

    final session = await repo.createWorkoutSession(
      WorkoutSession(
        id: 'batch-session',
        name: 'Batch Day',
        startTime: DateTime.now(),
        exercises: const [
          WorkoutExercise(
            id: 'ex1',
            exercise: Exercise(name: 'Bench Press', muscles: ['Chest']),
            sets: [
              WorkoutSet(id: 's1', weight: 100, reps: 5),
              WorkoutSet(id: 's2', weight: 105, reps: 5),
              WorkoutSet(id: 's3', weight: 110, reps: 5),
            ],
          ),
        ],
      ),
    );

    final completedAt = DateTime.now();
    final updated = await repo.updateSetsInExercise(session.id, 'ex1', {
      0: const WorkoutSet(
        id: 's1',
        weight: 100,
        reps: 6,
        isCompleted: true,
      ).copyWith(completedAt: completedAt),
      2: const WorkoutSet(
        id: 's3',
        weight: 112.5,
        reps: 5,
        isCompleted: true,
      ).copyWith(completedAt: completedAt),
    });

    expect(updated.sets[0].reps, 6);
    expect(updated.sets[0].isCompleted, isTrue);
    expect(updated.sets[1].isCompleted, isFalse);
    expect(updated.sets[2].weight, 112.5);
    expect(updated.sets[2].isCompleted, isTrue);

    final fetched = await repo.getWorkoutSession(session.id);
    expect(fetched!.exercises.single.sets[0].isCompleted, isTrue);
    expect(fetched.exercises.single.sets[2].weight, 112.5);
    repo.dispose();
  });

  test('serialized background persists cannot overwrite a newer edit', () async {
    final snapshots = <List<WorkoutSession>>[];
    final encodes = <Completer<String>>[];
    final repo = LocalWorkoutRepository(
      workoutSessionsEncoder: (sessions) {
        snapshots.add(List<WorkoutSession>.of(sessions));
        final completer = Completer<String>();
        encodes.add(completer);
        return completer.future;
      },
    );

    final firstWrite = repo.createWorkoutSession(
      WorkoutSession(
        id: 'persist-a',
        name: 'First',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000),
        exercises: const [],
      ),
    );
    await pumpEventQueue();
    expect(snapshots, hasLength(1));
    expect(snapshots.single.map((session) => session.id), ['persist-a']);

    final secondWrite = repo.createWorkoutSession(
      WorkoutSession(
        id: 'persist-b',
        name: 'Second',
        startTime: DateTime.fromMillisecondsSinceEpoch(2000),
        exercises: const [],
      ),
    );
    await pumpEventQueue();

    // The newer snapshot is queued behind the first encode instead of racing it
    // to SharedPreferences and risking a stale final blob.
    expect(snapshots, hasLength(1));
    encodes.first.complete(
      jsonEncode(snapshots.first.map((session) => session.toMap()).toList()),
    );
    await firstWrite;
    await pumpEventQueue();

    expect(snapshots, hasLength(2));
    expect(
      snapshots.last.map((session) => session.id),
      containsAll(['persist-a', 'persist-b']),
    );
    encodes.last.complete(
      jsonEncode(snapshots.last.map((session) => session.toMap()).toList()),
    );
    await secondWrite;

    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString('workout_sessions_v1')!) as List;
    expect(
      stored.map((entry) => (entry as Map<String, dynamic>)['id']),
      containsAll(['persist-a', 'persist-b']),
    );
    repo.dispose();
  });

  test('clearAll fences an in-flight old-account persist', () async {
    final encodeStarted = Completer<void>();
    final finishEncode = Completer<String>();
    final repo = LocalWorkoutRepository(
      workoutSessionsEncoder: (sessions) {
        encodeStarted.complete();
        return finishEncode.future;
      },
    );

    final oldAccountWrite = repo.createWorkoutSession(
      WorkoutSession(
        id: 'old-account-session',
        name: 'Private old account workout',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000),
        exercises: const [],
      ),
    );
    await encodeStarted.future;

    final clear = repo.clearAll();
    finishEncode.complete(
      jsonEncode([
        WorkoutSession(
          id: 'old-account-session',
          name: 'Private old account workout',
          startTime: DateTime.fromMillisecondsSinceEpoch(1000),
          exercises: const [],
        ).toMap(),
      ]),
    );
    await Future.wait([oldAccountWrite, clear]);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('workout_sessions_v1'), isNull);
    expect(await repo.getWorkoutSessions(), isEmpty);
    repo.dispose();
  });

  test('clearAll fences an in-flight hydrated session read', () async {
    await getIt.unregister<ExerciseRepository>();
    final repo = LocalWorkoutRepository();
    final session = await repo.createWorkoutSession(
      WorkoutSession(
        id: 'old-read-session',
        name: 'Private old account workout',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000),
        exercises: const [
          WorkoutExercise(
            id: 'old-exercise',
            exercise: Exercise(name: 'Bench Press', muscles: []),
            sets: [],
          ),
        ],
      ),
    );
    final exercises = _DeferredExerciseRepo();
    getIt.registerSingleton<ExerciseRepository>(exercises);

    final oldAccountRead = repo.getWorkoutSession(session.id);
    await exercises.started.future;
    await repo.clearAll();
    exercises.finish.complete(const [
      Exercise(name: 'Bench Press', muscles: ['Chest']),
    ]);

    expect(await oldAccountRead, isNull);
    expect(await repo.getWorkoutSession(session.id), isNull);
    repo.dispose();
  });

  test('clearAll fences an in-flight latest-active hydration', () async {
    await getIt.unregister<ExerciseRepository>();
    final repo = LocalWorkoutRepository();
    final session = await repo.createWorkoutSession(
      WorkoutSession(
        id: 'old-active-session',
        name: 'Private old active workout',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000),
        exercises: const [
          WorkoutExercise(
            id: 'old-exercise',
            exercise: Exercise(name: 'Bench Press', muscles: []),
            sets: [],
          ),
        ],
      ),
    );
    final exercises = _DeferredExerciseRepo();
    getIt.registerSingleton<ExerciseRepository>(exercises);

    final oldAccountRead = repo.getLatestActiveSession();
    await exercises.started.future;
    await repo.clearAll();
    exercises.finish.complete(const [
      Exercise(name: 'Bench Press', muscles: ['Chest']),
    ]);

    expect(await oldAccountRead, isNull);
    expect(await repo.getWorkoutSession(session.id), isNull);
    repo.dispose();
  });

  test('clearAll fences an in-flight workout-list hydration', () async {
    await getIt.unregister<ExerciseRepository>();
    final repo = LocalWorkoutRepository();
    final session = await repo.createWorkoutSession(
      WorkoutSession(
        id: 'old-list-session',
        name: 'Private old account workout',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000),
        exercises: const [
          WorkoutExercise(
            id: 'old-exercise',
            exercise: Exercise(name: 'Bench Press', muscles: []),
            sets: [],
          ),
        ],
      ),
    );
    final exercises = _DeferredExerciseRepo();
    getIt.registerSingleton<ExerciseRepository>(exercises);

    final oldAccountRead = repo.getWorkoutSessions();
    await exercises.started.future;
    await repo.clearAll();
    exercises.finish.complete(const [
      Exercise(name: 'Bench Press', muscles: ['Chest']),
    ]);

    expect(await oldAccountRead, isEmpty);
    expect(await repo.getWorkoutSession(session.id), isNull);
    repo.dispose();
  });

  test('clearAll fences an in-flight server import hydration', () async {
    await getIt.unregister<ExerciseRepository>();
    final repo = LocalWorkoutRepository();
    expect(await repo.getWorkoutSessions(), isEmpty);
    final exercises = _DeferredExerciseRepo();
    getIt.registerSingleton<ExerciseRepository>(exercises);

    final oldAccountImport = repo.importServerSessions([
      WorkoutSession(
        id: 'old-import-session',
        name: 'Private old server workout',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000),
        exercises: const [
          WorkoutExercise(
            id: 'old-exercise',
            exercise: Exercise(name: 'Bench Press', muscles: []),
            sets: [],
          ),
        ],
      ),
    ]);
    await exercises.started.future;
    await repo.clearAll();
    exercises.finish.complete(const [
      Exercise(name: 'Bench Press', muscles: ['Chest']),
    ]);
    await oldAccountImport;

    expect(await repo.getWorkoutSessions(), isEmpty);
    repo.dispose();
  });

  test('clearAll rejects an in-flight hydrated session create', () async {
    await getIt.unregister<ExerciseRepository>();
    final repo = LocalWorkoutRepository();
    expect(await repo.getWorkoutSessions(), isEmpty);
    final exercises = _DeferredExerciseRepo();
    getIt.registerSingleton<ExerciseRepository>(exercises);

    final oldAccountCreate = repo.createWorkoutSession(
      WorkoutSession(
        id: 'old-create-session',
        name: 'Private old account draft',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000),
        exercises: const [
          WorkoutExercise(
            id: 'old-exercise',
            exercise: Exercise(name: 'Bench Press', muscles: []),
            sets: [],
          ),
        ],
      ),
    );
    await exercises.started.future;
    await repo.clearAll();
    exercises.finish.complete(const [
      Exercise(name: 'Bench Press', muscles: ['Chest']),
    ]);

    await expectLater(oldAccountCreate, throwsStateError);
    expect(await repo.getWorkoutSessions(), isEmpty);
    repo.dispose();
  });

  test('hydrated reads return a newer same-generation set update', () async {
    await getIt.unregister<ExerciseRepository>();
    final repo = LocalWorkoutRepository();
    final session = await repo.createWorkoutSession(
      WorkoutSession(
        id: 'same-account-session',
        name: 'Current account workout',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000),
        exercises: const [
          WorkoutExercise(
            id: 'bench',
            exercise: Exercise(name: 'Bench Press', muscles: []),
            sets: [WorkoutSet(id: 'bench-set', weight: 40, reps: 5)],
          ),
        ],
      ),
    );
    final exercises = _DeferredExerciseRepo();
    getIt.registerSingleton<ExerciseRepository>(exercises);

    final directRead = repo.getWorkoutSession(session.id);
    final latestRead = repo.getLatestActiveSession();
    final listRead = repo.getWorkoutSessions();
    await exercises.started.future;
    await repo.updateSetsInExercise(session.id, 'bench', {
      0: const WorkoutSet(id: 'bench-set', weight: 40, reps: 6),
    });
    exercises.finish.complete(const [
      Exercise(name: 'Bench Press', muscles: ['Chest']),
    ]);

    final direct = await directRead;
    final latest = await latestRead;
    final listed = await listRead;
    expect(direct, isNotNull);
    expect(latest, isNotNull);
    expect(direct!.exercises.single.sets.single.reps, 6);
    expect(latest!.exercises.single.sets.single.reps, 6);
    expect(listed.single.exercises.single.sets.single.reps, 6);
    repo.dispose();
  });

  // C6 lost-update guard: the phone screen now persists a set completion via the
  // granular updateSetsInExercise (read-modify-write of the STORED session) rather
  // than a whole-session overwrite built from a stale in-memory copy. Two writers
  // completing DIFFERENT sets of the same exercise must both survive.
  test(
    'updateSetsInExercise preserves a concurrently-completed set (no lost update)',
    () async {
      final repo = LocalWorkoutRepository();

      final session = await repo.createWorkoutSession(
        WorkoutSession(
          id: 'concurrent-session',
          name: 'Concurrent',
          startTime: DateTime.now(),
          exercises: const [
            WorkoutExercise(
              id: 'ex1',
              exercise: Exercise(name: 'Bench Press', muscles: ['Chest']),
              sets: [
                WorkoutSet(id: 's1', weight: 100, reps: 5),
                WorkoutSet(id: 's2', weight: 100, reps: 5),
              ],
            ),
          ],
        ),
      );

      // The WATCH completes set 1 granularly.
      await repo.updateSetsInExercise(session.id, 'ex1', {
        0: const WorkoutSet(id: 's1', weight: 100, reps: 5, isCompleted: true),
      });

      // The PHONE, working from a STALE view where set 1 is still incomplete,
      // completes set 2 through the granular path. Its map carries ONLY set 2, so
      // the watch's set-1 completion in the stored session must survive.
      await repo.updateSetsInExercise(session.id, 'ex1', {
        1: const WorkoutSet(id: 's2', weight: 100, reps: 5, isCompleted: true),
      });

      final fetched = await repo.getWorkoutSession(session.id);
      expect(
        fetched!.exercises.single.sets[0].isCompleted,
        isTrue,
        reason: 'watch-completed set 1 must not be clobbered',
      );
      expect(fetched.exercises.single.sets[1].isCompleted, isTrue);
      repo.dispose();
    },
  );

  test('updateSetsInExercise folds in timeline events without overwriting stored '
      'state', () async {
    final repo = LocalWorkoutRepository();

    final session = await repo.createWorkoutSession(
      WorkoutSession(
        id: 'timeline-session',
        name: 'Timeline',
        startTime: DateTime.now(),
        exercises: const [
          WorkoutExercise(
            id: 'ex1',
            exercise: Exercise(name: 'Bench Press', muscles: ['Chest']),
            sets: [
              WorkoutSet(id: 's1', weight: 100, reps: 5),
              WorkoutSet(id: 's2', weight: 100, reps: 5),
            ],
          ),
        ],
        timelineEvents: const [
          ExerciseTimelineEvent(
            tsMs: 1,
            kind: ExerciseTimelineEventKind.workoutStart,
          ),
        ],
      ),
    );

    // Watch completes set 1 (no timeline).
    await repo.updateSetsInExercise(session.id, 'ex1', {
      0: const WorkoutSet(id: 's1', weight: 100, reps: 5, isCompleted: true),
    });

    // Phone completes set 2 AND folds in its setComplete timeline event via the
    // granular path — the pre-existing workoutStart event and set 1 must remain.
    await repo.updateSetsInExercise(
      session.id,
      'ex1',
      {1: const WorkoutSet(id: 's2', weight: 100, reps: 5, isCompleted: true)},
      appendTimelineEvents: const [
        ExerciseTimelineEvent(
          tsMs: 2,
          kind: ExerciseTimelineEventKind.setComplete,
          workoutExerciseId: 'ex1',
        ),
      ],
    );

    final fetched = await repo.getWorkoutSession(session.id);
    expect(fetched!.exercises.single.sets[0].isCompleted, isTrue);
    expect(fetched.exercises.single.sets[1].isCompleted, isTrue);
    expect(fetched.timelineEvents.length, 2);
    expect(
      fetched.timelineEvents.first.kind,
      ExerciseTimelineEventKind.workoutStart,
    );
    expect(
      fetched.timelineEvents.last.kind,
      ExerciseTimelineEventKind.setComplete,
    );
    repo.dispose();
  });

  // REGRESSION (simulator repro 2026-07-03): a watch set completion starts the
  // phone's rest timer, whose status listener persists a restStart timeline
  // event while the screen's in-memory session is still the PRE-SET snapshot.
  // That persist must go through this timeline-only granular path — a
  // whole-session write here clobbered the watch's set back to incomplete.
  test('updateSetsInExercise timeline-only append preserves sets and honors '
      'markDirty: false', () async {
    final repo = LocalWorkoutRepository();

    final session = await repo.createWorkoutSession(
      WorkoutSession(
        id: 'rest-timeline-session',
        name: 'Rest Timeline',
        startTime: DateTime.now(),
        exercises: const [
          WorkoutExercise(
            id: 'ex1',
            exercise: Exercise(name: 'Bench Press', muscles: ['Chest']),
            sets: [WorkoutSet(id: 's1', weight: 100, reps: 5)],
          ),
        ],
      ),
    );

    // The WATCH completes set 1 (this is the write the rest-timer listener's
    // stale whole-session persist used to clobber).
    await repo.updateSetsInExercise(session.id, 'ex1', {
      0: const WorkoutSet(id: 's1', weight: 100, reps: 5, isCompleted: true),
    });

    // The SCREEN's rest-timer listener records restStart with NO set updates
    // and markDirty: false (timeline churn must not schedule a sync upload).
    final before = await repo.getWorkoutSession(session.id);
    await repo.updateSetsInExercise(
      session.id,
      'ex1',
      const {},
      appendTimelineEvents: const [
        ExerciseTimelineEvent(
          tsMs: 2,
          kind: ExerciseTimelineEventKind.restStart,
          workoutExerciseId: 'ex1',
        ),
      ],
      markDirty: false,
    );

    final fetched = await repo.getWorkoutSession(session.id);
    expect(
      fetched!.exercises.single.sets.single.isCompleted,
      isTrue,
      reason: 'watch-completed set must survive the timeline-only persist',
    );
    expect(
      fetched.timelineEvents.last.kind,
      ExerciseTimelineEventKind.restStart,
    );
    expect(
      fetched.dirty,
      before!.dirty,
      reason: 'markDirty: false must leave the sync bit unchanged',
    );
    repo.dispose();
  });

  test(
    'completeWorkoutSession keeps watch capture pending when watch recording was active',
    () async {
      final repo = LocalWorkoutRepository();

      final session = await repo.createWorkoutSession(
        WorkoutSession(
          id: 'watch-active',
          name: 'Watch Active',
          startTime: DateTime.now(),
          exercises: const [],
          watchRecordingActive: true,
          watchRecordingStartMs: 123,
          watchRecordingRequested: true,
        ),
      );

      final completed = await repo.completeWorkoutSession(session.id);

      expect(completed.isCompleted, isTrue);
      expect(completed.watchRecordingRequested, isFalse);
      expect(completed.watchCapturePending, isTrue);
      expect(completed.watchCapturePendingAt, isNotNull);
      repo.dispose();
    },
  );

  test('create preserves provided session id', () async {
    final repo = LocalWorkoutRepository();
    const providedId = 'fixed-id-123';
    final session = await repo.createWorkoutSession(
      WorkoutSession(
        id: providedId,
        name: 'Leg Day',
        startTime: DateTime.now(),
        exercises: const [],
      ),
    );
    expect(session.id, providedId);
    final fetched = await repo.getWorkoutSession(providedId);
    expect(fetched, isNotNull);
    expect(fetched!.id, providedId);
    repo.dispose();
  });

  test('editing a completed workout requeues writeback', () async {
    final coordinator = _MockWorkoutWritebackCoordinator();
    final repo = LocalWorkoutRepository();
    final getIt = GetIt.instance;
    getIt.registerSingleton<WorkoutWritebackCoordinator>(coordinator);
    when(
      () => coordinator.handleWorkoutUpdated(any()),
    ).thenAnswer((_) async {});
    when(
      () => coordinator.handleWorkoutDeleted(any()),
    ).thenAnswer((_) async {});
    when(
      () => coordinator.handleWorkoutCompleted(any()),
    ).thenAnswer((_) async {});

    final session = await repo.createWorkoutSession(
      WorkoutSession(
        id: 'completed-session',
        name: 'Upper Body',
        startTime: DateTime.now(),
        exercises: const [],
      ),
    );

    const benchExercise = WorkoutExercise(
      id: 'bench-exercise',
      exercise: Exercise(name: 'Bench Press', muscles: ['Chest']),
      sets: [WorkoutSet(id: 'set-1', weight: 100, reps: 5, isCompleted: true)],
    );

    await repo.addExerciseToSession(session.id, benchExercise);
    final completed = await repo.completeWorkoutSession(session.id);

    final updatedExercise = benchExercise.copyWith(notes: 'Adjusted load');
    await repo.updateExerciseInSession(
      completed.id,
      benchExercise.id,
      updatedExercise,
    );

    await Future<void>.delayed(Duration.zero);
    verify(() => coordinator.handleWorkoutUpdated(any())).called(1);
    repo.dispose();
  });

  test('create hydrates exercises missing muscle metadata', () async {
    final repo = LocalWorkoutRepository();
    final session = await repo.createWorkoutSession(
      WorkoutSession(
        id: 'tmp',
        name: 'Push Day',
        startTime: DateTime.now(),
        exercises: const [
          WorkoutExercise(
            id: 'ex1',
            exercise: Exercise(name: 'Bench Press', muscles: []),
            sets: [],
          ),
        ],
      ),
    );
    expect(session.exercises.first.exercise.muscles, ['Chest']);
    repo.dispose();
  });

  test(
    'loadFromStorage hydrates legacy exercises with empty muscles',
    () async {
      final stored = WorkoutSession(
        id: 'legacy',
        name: 'Legacy',
        startTime: DateTime.parse('2024-01-01T10:00:00Z'),
        endTime: DateTime.parse('2024-01-01T11:00:00Z'),
        exercises: const [
          WorkoutExercise(
            id: 'ex1',
            exercise: Exercise(name: 'Bench Press', muscles: []),
            sets: [],
          ),
        ],
        dirty: false,
      );
      SharedPreferences.setMockInitialValues({
        'workout_sessions_v1': jsonEncode([stored.toMap()]),
      });
      final repo = LocalWorkoutRepository();
      final sessions = await repo.getWorkoutSessions();
      expect(sessions.first.exercises.first.exercise.muscles, ['Chest']);
      repo.dispose();
    },
  );

  test('checkIfSetIsPR compares against existing history', () async {
    final repo = LocalWorkoutRepository();

    final session = await repo.createWorkoutSession(
      WorkoutSession(
        id: 'tmp',
        name: 'Push Day',
        startTime: DateTime.now(),
        exercises: const [],
      ),
    );

    const bench = WorkoutExercise(
      id: 'ex1',
      exercise: Exercise(name: 'Bench Press', muscles: ['Chest']),
      sets: [],
    );
    final withBench = await repo.addExerciseToSession(session.id, bench);

    const existing = WorkoutSet(
      id: 's1',
      weight: 100,
      reps: 5,
      isCompleted: true,
      isPr: true,
    );
    await repo.addSetToExercise(withBench.id, 'ex1', existing);

    expect(
      await repo.checkIfSetIsPR(
        'Bench Press',
        const WorkoutSet(
          id: 's2',
          weight: 95,
          reps: 5,
          isCompleted: true,
          isPr: false,
        ),
      ),
      isFalse,
    );
    expect(
      await repo.checkIfSetIsPR(
        'Bench Press',
        const WorkoutSet(
          id: 's3',
          weight: 100,
          reps: 4,
          isCompleted: true,
          isPr: false,
        ),
      ),
      isFalse,
    );
    expect(
      await repo.checkIfSetIsPR(
        'Bench Press',
        const WorkoutSet(
          id: 's4',
          weight: 100,
          reps: 6,
          isCompleted: true,
          isPr: false,
        ),
      ),
      isTrue,
    );
    expect(
      await repo.checkIfSetIsPR(
        'Bench Press',
        const WorkoutSet(
          id: 's5',
          weight: 105,
          reps: 5,
          isCompleted: true,
          isPr: false,
        ),
      ),
      isTrue,
    );

    repo.dispose();
  });

  test('checkIfSetIsPR ignores distance-duration logging mode', () async {
    final repo = LocalWorkoutRepository();
    const run = WorkoutExercise(
      id: 'run',
      exercise: Exercise(
        name: 'Custom Run',
        muscles: ['Cardio'],
        loggingMode: ExerciseLoggingMode.distanceDuration,
      ),
      sets: [WorkoutSet(id: 's1', weight: 5, reps: 1500, isCompleted: true)],
    );
    await repo.createWorkoutSession(
      WorkoutSession(
        id: 'run-session',
        name: 'Run',
        startTime: DateTime.now(),
        exercises: const [run],
      ),
    );

    expect(
      await repo.checkIfSetIsPR(
        'Custom Run',
        const WorkoutSet(id: 's2', weight: 6, reps: 1800, isCompleted: true),
      ),
      isFalse,
    );
    expect(await repo.getExercisePr('Custom Run'), isNull);

    repo.dispose();
  });

  test(
    'PR lookups ignore catalog-only distance-duration logging mode',
    () async {
      final repo = LocalWorkoutRepository();

      expect(
        await repo.checkIfSetIsPR(
          'Run',
          const WorkoutSet(id: 's1', weight: 6, reps: 1800, isCompleted: true),
        ),
        isFalse,
      );
      expect(await repo.getExercisePr('Run'), isNull);

      repo.dispose();
    },
  );

  test(
    'getPreviousExerciseSets ignores sessions without completed sets',
    () async {
      final repo = LocalWorkoutRepository();

      final first = await repo.createWorkoutSession(
        WorkoutSession(
          id: 'sess1',
          name: 'Leg Day 1',
          startTime: DateTime(2025, 9, 12, 11, 13),
          exercises: const [
            WorkoutExercise(
              id: 'ex1',
              exercise: Exercise(
                name: 'Leg Extension (Machine)',
                muscles: ['Quads'],
              ),
              sets: [
                WorkoutSet(id: 'set1', weight: 75, reps: 10, isCompleted: true),
              ],
            ),
          ],
        ),
      );
      await repo.completeWorkoutSession(first.id);

      final aborted = await repo.createWorkoutSession(
        WorkoutSession(
          id: 'sess2',
          name: 'Leg Day 2',
          startTime: DateTime(2025, 9, 15, 11, 22),
          exercises: const [
            WorkoutExercise(
              id: 'ex2',
              exercise: Exercise(
                name: 'Leg Extension (Machine)',
                muscles: ['Quads'],
              ),
              sets: [
                WorkoutSet(id: 'set2', weight: 0, reps: 0, isCompleted: false),
              ],
            ),
          ],
        ),
      );
      await repo.completeWorkoutSession(aborted.id);

      final previous = await repo.getPreviousExerciseSets(
        'Leg Extension (Machine)',
      );
      expect(previous, isNotNull);
      expect(previous, hasLength(1));
      expect(previous!.single.weight, 75);
      expect(previous.single.reps, 10);
      repo.dispose();
    },
  );

  test('getPreviousExerciseSets skips a more recent session where the exercise '
      'was completed but left empty (skipped), falling through to the last real '
      'performance', () async {
    final repo = LocalWorkoutRepository();

    // Older session: Plank actually performed — 3 × 30s (duration lives in
    // `reps` for duration-only exercises).
    final real = await repo.createWorkoutSession(
      WorkoutSession(
        id: 'sessReal',
        name: 'Core A',
        startTime: DateTime(2026, 6, 24, 10, 15),
        exercises: const [
          WorkoutExercise(
            id: 'exReal',
            exercise: Exercise(name: 'Plank', muscles: ['Abs']),
            sets: [
              WorkoutSet(id: 'r1', weight: 0, reps: 30, isCompleted: true),
              WorkoutSet(id: 'r2', weight: 0, reps: 30, isCompleted: true),
              WorkoutSet(id: 'r3', weight: 0, reps: 30, isCompleted: true),
            ],
          ),
        ],
      ),
    );
    await repo.completeWorkoutSession(real.id);

    // Newer session: Plank on the plan but skipped — its generated sets got
    // marked complete with no logged value (weight 0 / reps 0). This must NOT
    // become "Previous" (it would render as 00:00).
    final skipped = await repo.createWorkoutSession(
      WorkoutSession(
        id: 'sessSkipped',
        name: 'Core B',
        startTime: DateTime(2026, 6, 27, 9, 5),
        exercises: const [
          WorkoutExercise(
            id: 'exSkipped',
            exercise: Exercise(name: 'Plank', muscles: ['Abs']),
            sets: [
              WorkoutSet(id: 's1', weight: 0, reps: 0, isCompleted: true),
              WorkoutSet(id: 's2', weight: 0, reps: 0, isCompleted: true),
              WorkoutSet(id: 's3', weight: 0, reps: 0, isCompleted: true),
            ],
          ),
        ],
      ),
    );
    await repo.completeWorkoutSession(skipped.id);

    final previous = await repo.getPreviousExerciseSets('Plank');
    expect(previous, isNotNull);
    expect(previous, hasLength(3));
    expect(previous!.every((s) => s.reps == 30), isTrue);
    repo.dispose();
  });

  test('remote stats token failures fall back to local-only data', () async {
    getIt.registerSingleton<token.TokenStorage>(_ThrowingTokenStorage());
    final repo = LocalWorkoutRepository();

    expect(await repo.getPreviousExerciseSets('Squat'), isNull);
    expect(await repo.getExercisePr('Squat'), isNull);

    repo.dispose();
  });

  test(
    'getWorkoutSessions falls back to cached lookup when refresh fails',
    () async {
      final fakeRepo =
          GetIt.instance<ExerciseRepository>() as _FakeExerciseRepo;

      final onlineRepo = LocalWorkoutRepository();
      await onlineRepo.createWorkoutSession(
        WorkoutSession(
          id: 'offline-test',
          name: 'Custom Day',
          startTime: DateTime.now(),
          exercises: const [
            WorkoutExercise(
              id: 'mystery',
              exercise: Exercise(name: 'Mystery Move', muscles: []),
              sets: [],
            ),
          ],
        ),
      );
      onlineRepo.dispose();

      fakeRepo.throwOnFetch = true;
      fakeRepo.fetchCount = 0;

      final offlineRepo = LocalWorkoutRepository();
      final sessions = await offlineRepo.getWorkoutSessions();
      expect(sessions, isNotEmpty);

      fakeRepo.throwOnFetch = false;
      final before = fakeRepo.fetchCount;
      await offlineRepo.getWorkoutSessions();
      expect(fakeRepo.fetchCount, greaterThan(before));
      offlineRepo.dispose();
    },
  );
}
