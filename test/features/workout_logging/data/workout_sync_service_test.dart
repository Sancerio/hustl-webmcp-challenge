import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/features/workout_logging/data/services/workout_sync_service.dart';
import 'package:hustl_app/features/workout_logging/data/datasources/workout_sync_api.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/core/services/token_storage.dart' as token;
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/workout_logging/data/repositories/local_workout_repository.dart';

class _FakeTokenStorage implements token.TokenStorage {
  String? _access;
  @override
  Future<String?> getAccessToken() async => _access;
  @override
  Future<String?> getRefreshToken() async => null;
  @override
  Future<void> saveTokenPair({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
  }) async {
    _access = accessToken;
  }

  @override
  Future<void> clearAccessToken() async {
    _access = null;
  }

  @override
  Future<void> clearAll() async {
    _access = null;
  }
}

class _FakeRepo implements WorkoutRepository {
  final Map<String, WorkoutSession> store = {};
  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession session) async {
    store[session.id] = session;
    return session;
  }

  @override
  Future<void> deleteWorkoutSession(String id) async {
    store.remove(id);
  }

  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async => store[id];
  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => store.values.toList();
  @override
  Future<WorkoutSession?> getLatestActiveSession() async {
    for (final s in store.values) {
      if (s.endTime == null) return s;
    }
    return null;
  }

  @override
  Future<WorkoutExercise> addSetToExercise(
    String sessionId,
    String exerciseId,
    WorkoutSet set,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<WorkoutSession> addExerciseToSession(
    String sessionId,
    WorkoutExercise exercise,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession session, {
    bool markDirty = true,
  }) async {
    store[session.id] = session;
    return session;
  }

  @override
  Future<WorkoutExercise> updateSetInExercise(
    String sessionId,
    String exerciseId,
    int setIndex,
    WorkoutSet set,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<WorkoutSession> completeWorkoutSession(String sessionId) async {
    final s = store[sessionId]!;
    final completed = s.copyWith(endTime: DateTime.now());
    store[sessionId] = completed;
    return completed;
  }

  @override
  Future<List<WorkoutSet>?> getPreviousExerciseSets(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;
  @override
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  }) async => false;
  @override
  Future<void> recomputeAllPrFlags() async {}
  @override
  Future<WorkoutSession> updateExerciseInSession(
    String sessionId,
    String exerciseId,
    WorkoutExercise exercise,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<WorkoutSession> removeExerciseFromSession(
    String sessionId,
    String exerciseId,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<DateTime?> getLastPerformedDate(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    return null;
  }

  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;
}

/// A real [LocalWorkoutRepository] (so the sync service takes the single-batch
/// fast path) whose batch persist always throws — simulating a transient web
/// IndexedDB failure that drops the whole page. [getWorkoutSessions] returns
/// empty so [syncNow] runs the pull-only loop with no local upload payload.
class _PersistFailLocalRepo extends LocalWorkoutRepository {
  int importCalls = 0;

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => const <WorkoutSession>[];

  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async => null;

  @override
  Future<void> importServerSessions(List<WorkoutSession> sessions) async {
    importCalls += 1;
    throw StateError('simulated persist failure');
  }
}

class _FakeApi implements WorkoutSyncApi {
  List<Map<String, dynamic>>? lastClientPayload;
  int? lastVersion;
  List<String>? lastDeleted;
  final List<List<Map<String, dynamic>>> callPayloads = [];
  final List<int> versionCalls = [];
  // Optional server payload to return regardless of client payload
  List<Map<String, dynamic>>? nextServerPayload;
  @override
  Future<
    ({
      List<Map<String, dynamic>> serverWorkouts,
      List<String> deletedWorkoutIds,
      int newSyncVersion,
    })
  >
  sync({
    required String accessToken,
    required int lastSyncVersion,
    required List<Map<String, dynamic>> clientWorkouts,
    List<String>? deletedIds,
    int? limit,
  }) async {
    lastClientPayload = clientWorkouts;
    lastVersion = lastSyncVersion;
    lastDeleted = deletedIds;
    callPayloads.add(List<Map<String, dynamic>>.from(clientWorkouts));
    versionCalls.add(lastSyncVersion);
    // Return a dummy updated server workout, or a preset server payload if provided
    final List<Map<String, dynamic>> server;
    if (nextServerPayload != null) {
      server = nextServerPayload!;
    } else {
      server = [
        if (clientWorkouts.isNotEmpty)
          {...clientWorkouts.first, 'name': 'Server Copy'},
      ];
    }
    final newVersion =
        server.isEmpty && (deletedIds == null || deletedIds.isEmpty)
        ? lastSyncVersion
        : (lastSyncVersion + 1);
    return (
      serverWorkouts: server,
      deletedWorkoutIds: const <String>[],
      newSyncVersion: newVersion,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkoutSyncService', () {
    late PreferencesService prefs;
    late _FakeTokenStorage tokens;
    late _FakeRepo repo;
    late _FakeApi api;
    late WorkoutSyncService svc;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = PreferencesService();
      await prefs.init();
      tokens = _FakeTokenStorage().._access = 'acc';
      repo = _FakeRepo();
      api = _FakeApi();
      svc = WorkoutSyncService(prefs, tokens, repo, api);
    });

    test(
      'pull-only sync imports server workouts when no local changes',
      () async {
        // Seed server to return one workout even when client payload is empty
        api.nextServerPayload = [
          {
            'id': 'server-1',
            'name': 'Server Only',
            'start_time': '2024-02-01T10:00:00Z',
            'end_time': '2024-02-01T11:00:00Z',
            'status': 'completed',
            'exercises': [],
          },
        ];

        // No local sessions
        await svc.syncNow();

        final v = await prefs.getWorkoutsSyncVersion();
        expect(v, 1); // version bumped even on pull-only
        final imported = await repo.getWorkoutSession('server-1');
        expect(imported, isNotNull);
        expect(imported!.name, 'Server Only');
      },
    );

    test('imports new server workouts preserving IDs', () async {
      // Server returns one workout with id that does not exist locally
      api.nextServerPayload = [
        {
          'id': 'srv-keep-id',
          'name': 'Remote',
          'start_time': '2024-03-01T10:00:00Z',
          'end_time': '2024-03-01T11:00:00Z',
          'status': 'completed',
          'exercises': [],
        },
      ];
      await svc.syncNow();
      final got = await repo.getWorkoutSession('srv-keep-id');
      expect(got, isNotNull);
      expect(got!.id, 'srv-keep-id');
    });

    test('exports local completed sessions into client payload', () async {
      final s = WorkoutSession(
        id: 'w1',
        name: 'Test',
        startTime: DateTime.parse('2024-01-01T10:00:00Z'),
        endTime: DateTime.parse('2024-01-01T11:00:00Z'),
        exercises: [
          const WorkoutExercise(
            id: 'we1',
            exercise: Exercise(name: 'Bench Press', muscles: []),
            sets: [
              WorkoutSet(id: 's1', weight: 100, reps: 5, isCompleted: true),
            ],
          ),
        ],
      );
      await repo.createWorkoutSession(s);
      await svc.syncNow();
      final payload = api.callPayloads.firstWhere(
        (call) => call.isNotEmpty,
        orElse: () => const [],
      );
      expect(payload, isNotEmpty);
      final first = payload.first;
      expect(first['id'], 'w1');
      expect(first['exercises'][0]['exercise_name'], 'Bench Press');
      expect(first['exercises'][0]['sets'][0]['reps'], 5);
    });

    test('sync payload includes exercise muscles and slug metadata', () async {
      final session = WorkoutSession(
        id: 'meta-1',
        name: 'Meta',
        startTime: DateTime.parse('2024-04-01T08:00:00Z'),
        endTime: DateTime.parse('2024-04-01T09:00:00Z'),
        exercises: const [
          WorkoutExercise(
            id: 'meta-ex',
            exercise: Exercise(
              name: 'Bench Press',
              muscles: ['Chest', 'Triceps'],
              slug: 'bench-press',
            ),
            sets: [
              WorkoutSet(
                id: 'meta-set',
                weight: 50,
                reps: 8,
                isCompleted: true,
              ),
            ],
          ),
        ],
        isCompleted: true,
        dirty: true,
      );
      await repo.createWorkoutSession(session);
      await svc.syncNow();
      final payload = api.callPayloads.firstWhere(
        (call) => call.isNotEmpty,
        orElse: () => const [],
      );
      expect(payload, isNotEmpty);
      final exercise =
          (payload.first['exercises'] as List).first as Map<String, dynamic>;
      expect(exercise['primary_muscles'], ['Chest', 'Triceps']);
      expect(exercise['exercise_slug'], 'bench-press');
    });

    test('imports server workouts and updates last sync data', () async {
      final s = WorkoutSession(
        id: 'w1',
        name: 'Local Name',
        startTime: DateTime.parse('2024-01-01T10:00:00Z'),
        endTime: DateTime.parse('2024-01-01T11:00:00Z'),
        exercises: const [],
      );
      await repo.createWorkoutSession(s);
      await svc.syncNow();

      // Repo should have server-updated name
      final updated = await repo.getWorkoutSession('w1');
      expect(updated!.name, 'Server Copy');

      // Version bumped
      final v = await prefs.getWorkoutsSyncVersion();
      expect(v, 1);

      // Last sync timestamp set
      final last = await prefs.getWorkoutsLastSyncAt();
      expect(last, isNotNull);
    });

    test('batches large uploads to respect server limit', () async {
      // Create 344 completed workouts (batch size is implementation-defined)
      for (int i = 0; i < 344; i++) {
        final s = WorkoutSession(
          id: 'w$i',
          name: 'N$i',
          startTime: DateTime.parse(
            '2024-01-01T10:00:00Z',
          ).add(Duration(minutes: i)),
          endTime: DateTime.parse(
            '2024-01-01T11:00:00Z',
          ).add(Duration(minutes: i)),
          exercises: const [],
        );
        await repo.createWorkoutSession(s);
      }
      await svc.syncNow();

      // Compute expected batch count based on observed first batch size
      final uploadCalls = api.callPayloads
          .where((payload) => payload.isNotEmpty)
          .toList();
      final firstBatch = uploadCalls.first.length;
      expect(firstBatch, greaterThan(0));
      final expectedBatches = (344 + firstBatch - 1) ~/ firstBatch;
      expect(uploadCalls.length, expectedBatches);
      // Last batch size equals remainder (or full batch if divisible)
      final remainder = 344 % firstBatch;
      final expectedLastBatch = remainder == 0 ? firstBatch : remainder;
      expect(uploadCalls.last.length, expectedLastBatch);

      // Sync version should have incremented once per batch
      final v = await prefs.getWorkoutsSyncVersion();
      expect(v, expectedBatches);
    });

    test(
      'persist failure does NOT advance the sync cursor (re-pull next run)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final localPrefs = PreferencesService();
        await localPrefs.init();
        // Start the cursor at a known prior value.
        await localPrefs.setWorkoutsSyncVersion(7);

        final failingRepo = _PersistFailLocalRepo();
        final failApi = _FakeApi();
        // Server returns a page of real workouts at a HIGHER newSyncVersion than
        // the starting cursor; persisting it will throw.
        failApi.nextServerPayload = [
          {
            'id': 'server-persist-fail',
            'name': 'Unsaved Remote',
            'start_time': '2024-05-01T10:00:00Z',
            'end_time': '2024-05-01T11:00:00Z',
            'status': 'completed',
            'exercises': [],
          },
        ];

        final failingSvc = WorkoutSyncService(
          localPrefs,
          _FakeTokenStorage().._access = 'acc',
          failingRepo,
          failApi,
        );

        await failingSvc.syncNow();

        // The batch persist threw, so the cursor must stay at the prior value
        // (7) — the page must be re-pulled next run, never skipped.
        final v = await localPrefs.getWorkoutsSyncVersion();
        expect(v, 7);
        expect(failingRepo.importCalls, greaterThan(0));
        // A clear error was surfaced for the UI.
        expect(failingSvc.errors.value, isNotEmpty);
        expect(failingSvc.status.value, SyncStatus.degraded);
      },
    );

    test('parse-skip still advances the cursor (one bad row does not wedge)', () async {
      // Page with one parseable workout and one malformed row. The good row
      // persists via the fallback path; persistFailed stays false; the cursor
      // advances despite the per-row parse error.
      api.nextServerPayload = [
        {
          'id': 'good-row',
          'name': 'Parseable',
          'start_time': '2024-06-01T10:00:00Z',
          'end_time': '2024-06-01T11:00:00Z',
          'status': 'completed',
          'exercises': [],
        },
        {'bad': 'data'}, // missing id/start_time -> parse failure (skipped)
      ];

      await svc.syncNow();

      // Cursor advanced (the bad row did not block it).
      final v = await prefs.getWorkoutsSyncVersion();
      expect(v, 1);
      // The good row was imported.
      final got = await repo.getWorkoutSession('good-row');
      expect(got, isNotNull);
      // A per-row parse error was still surfaced.
      expect(svc.errors.value, isNotEmpty);
    });
  });
}
