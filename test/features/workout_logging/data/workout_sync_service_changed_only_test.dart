import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/features/workout_logging/data/services/workout_sync_service.dart';
import 'package:hustl_app/features/workout_logging/data/datasources/workout_sync_api.dart';
import 'package:hustl_app/features/workout_logging/data/repositories/local_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/token_storage.dart' as token;
import 'package:get_it/get_it.dart';
import 'package:hustl_app/features/exercise_library/domain/repositories/exercise_repository.dart';

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

class _FakeExerciseRepo implements ExerciseRepository {
  @override
  Future<List<Exercise>> getAllExercises() async => const [];
  @override
  Future<List<Exercise>> getExercisesByMuscle(String muscle) async => const [];
  @override
  Future<List<Exercise>> searchExercises(String query) async => const [];
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

class _RecordingApi implements WorkoutSyncApi {
  final List<List<Map<String, dynamic>>> callPayloads = [];
  final List<int> versionCalls = [];
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
    callPayloads.add(List<Map<String, dynamic>>.from(clientWorkouts));
    versionCalls.add(lastSyncVersion);
    final server = nextServerPayload ?? const [];
    nextServerPayload = null; // one-shot
    return (
      serverWorkouts: server,
      deletedWorkoutIds: const <String>[],
      newSyncVersion: lastSyncVersion + 1,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Changed-only upload + resume', () {
    late PreferencesService prefs;
    late _FakeTokenStorage tokens;
    late LocalWorkoutRepository repo;
    late _RecordingApi api;
    late WorkoutSyncService svc;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      // Wire exercise repo needed by LocalWorkoutRepository
      final gi = GetIt.instance;
      if (gi.isRegistered<ExerciseRepository>()) {
        gi.unregister<ExerciseRepository>();
      }
      gi.registerLazySingleton<ExerciseRepository>(() => _FakeExerciseRepo());

      prefs = PreferencesService();
      await prefs.init();
      tokens = _FakeTokenStorage().._access = 'acc';
      repo = LocalWorkoutRepository();
      api = _RecordingApi();
      svc = WorkoutSyncService(prefs, tokens, repo, api);
    });

    test('signature change resets resume cursor (order changed)', () async {
      final base = DateTime.parse('2024-04-01T10:00:00Z');
      await repo.createWorkoutSession(
        WorkoutSession(
          id: 'a',
          name: 'A',
          startTime: base,
          endTime: base.add(const Duration(hours: 1)),
          exercises: const [],
          dirty: true,
        ),
      );
      await repo.createWorkoutSession(
        WorkoutSession(
          id: 'b',
          name: 'B',
          startTime: base.add(const Duration(minutes: 1)),
          endTime: base.add(const Duration(hours: 1, minutes: 1)),
          exercises: const [],
          dirty: true,
        ),
      );

      // Saved state says 'a' already uploaded (offset=1 for signature 'a|b')
      await prefs.setWorkoutsUploadSignature('a|b');
      await prefs.setWorkoutsUploadOffset(1);

      // Change order by making 'a' start later than 'b'
      final a = await repo.getWorkoutSession('a');
      await repo.updateWorkoutSession(
        a!.copyWith(
          startTime: base.add(const Duration(minutes: 2)),
          dirty: true,
        ),
      );

      await svc.syncNow();

      // Because signature changed from 'a|b' to 'b|a', cursor resets and 'a' is re-sent
      final sentIds = api.callPayloads
          .expand((x) => x.map((m) => m['id'] as String))
          .toList();
      expect(sentIds.contains('a'), isTrue);
      expect(sentIds.contains('b'), isTrue);
    });

    test(
      'deterministic order uses id as tiebreaker and resume skips prefix',
      () async {
        final base = DateTime.parse('2024-04-02T10:00:00Z');
        // Same startTime, ids a < b → order is a,b
        await repo.createWorkoutSession(
          WorkoutSession(
            id: 'b',
            name: 'B',
            startTime: base,
            endTime: base.add(const Duration(hours: 1)),
            exercises: const [],
            dirty: true,
          ),
        );
        await repo.createWorkoutSession(
          WorkoutSession(
            id: 'a',
            name: 'A',
            startTime: base,
            endTime: base.add(const Duration(hours: 1, minutes: 1)),
            exercises: const [],
            dirty: true,
          ),
        );

        // Saved state: signature 'a|b' offset 1 → skip 'a'
        await prefs.setWorkoutsUploadSignature('a|b');
        await prefs.setWorkoutsUploadOffset(1);

        await svc.syncNow();

        final sentIds = api.callPayloads
            .expand((x) => x.map((m) => m['id'] as String))
            .toList();
        expect(sentIds.contains('a'), isFalse);
        expect(sentIds.contains('b'), isTrue);
      },
    );

    test(
      'active sessions are excluded even if dirty; only completed uploaded',
      () async {
        final base = DateTime.parse('2024-04-03T10:00:00Z');
        // Active session (no endTime)
        await repo.createWorkoutSession(
          WorkoutSession(
            id: 'active',
            name: 'Active',
            startTime: base,
            endTime: null,
            exercises: const [],
            dirty: true,
          ),
        );
        await repo.createWorkoutSession(
          WorkoutSession(
            id: 'done',
            name: 'Done',
            startTime: base,
            endTime: base.add(const Duration(hours: 1)),
            exercises: const [],
            dirty: true,
          ),
        );

        await svc.syncNow();

        expect(api.callPayloads.length, greaterThan(0));
        final sentIds = api.callPayloads
            .expand((x) => x.map((m) => m['id'] as String))
            .toList();
        expect(sentIds, contains('done'));
        expect(sentIds, isNot(contains('active')));
      },
    );

    test('clears resume cursor after successful full run', () async {
      final base = DateTime.parse('2024-04-04T10:00:00Z');
      await repo.createWorkoutSession(
        WorkoutSession(
          id: 'x',
          name: 'X',
          startTime: base,
          endTime: base.add(const Duration(hours: 1)),
          exercises: const [],
          dirty: true,
        ),
      );

      // Pre-set some cursor
      await prefs.setWorkoutsUploadSignature('x');
      await prefs.setWorkoutsUploadOffset(0);

      await svc.syncNow();

      final sig = await prefs.getWorkoutsUploadSignature();
      final off = await prefs.getWorkoutsUploadOffset();
      expect(sig, isNull);
      expect(off, 0);
    });

    test(
      'editing a completed session marks it dirty and uploads again next sync',
      () async {
        final base = DateTime.parse('2024-04-05T10:00:00Z');
        await repo.createWorkoutSession(
          WorkoutSession(
            id: 'e1',
            name: 'E1',
            startTime: base,
            endTime: base.add(const Duration(hours: 1)),
            exercises: const [],
            dirty: true,
          ),
        );
        await svc.syncNow();
        api.callPayloads.clear();

        // Edit session: add an exercise → dirty should become true
        await repo.addExerciseToSession(
          'e1',
          const WorkoutExercise(
            id: 'we-added',
            exercise: Exercise(name: 'Squat', muscles: []),
            sets: [WorkoutSet(id: 's', weight: 50, reps: 5, isCompleted: true)],
          ),
        );

        await svc.syncNow();

        final sentIds = api.callPayloads
            .expand((x) => x.map((m) => m['id'] as String))
            .toList();
        expect(sentIds, contains('e1'));
      },
    );
    test(
      'uploads only dirty completed sessions and clears dirty after upload',
      () async {
        // Create three completed sessions: two already synced (dirty=false), one dirty=true
        final base = DateTime.parse('2024-01-01T10:00:00Z');
        await repo.createWorkoutSession(
          WorkoutSession(
            id: 'a',
            name: 'A',
            startTime: base,
            endTime: base.add(const Duration(hours: 1)),
            exercises: const [
              WorkoutExercise(
                id: 'we1',
                exercise: Exercise(name: 'E', muscles: []),
                sets: [
                  WorkoutSet(id: 's1', weight: 10, reps: 5, isCompleted: true),
                ],
              ),
            ],
            dirty: false,
          ),
        );
        await repo.createWorkoutSession(
          WorkoutSession(
            id: 'b',
            name: 'B',
            startTime: base.add(const Duration(minutes: 10)),
            endTime: base.add(const Duration(hours: 1, minutes: 10)),
            exercises: const [],
            dirty: false,
          ),
        );
        await repo.createWorkoutSession(
          WorkoutSession(
            id: 'c',
            name: 'C',
            startTime: base.add(const Duration(minutes: 20)),
            endTime: base.add(const Duration(hours: 1, minutes: 20)),
            exercises: const [],
            dirty: true,
          ),
        );

        await svc.syncNow();

        final uploadCalls = api.callPayloads
            .where((payload) => payload.isNotEmpty)
            .toList();
        expect(uploadCalls.length, 1);
        expect(uploadCalls.first.length, 1);
        expect(uploadCalls.first.first['id'], 'c');

        // Dirty should be cleared for 'c'
        final c = await repo.getWorkoutSession('c');
        expect(c!.dirty, isFalse);
      },
    );

    test('imported server workouts are marked clean (dirty=false)', () async {
      // Arrange server to return one workout while client sends none
      final base = DateTime.parse('2024-02-01T10:00:00Z');
      api.nextServerPayload = [
        {
          'id': 'srv-1',
          'name': 'Server Imported',
          'start_time': base.toUtc().toIso8601String(),
          'end_time': base
              .add(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
          'status': 'completed',
          'exercises': const <Map<String, dynamic>>[],
        },
      ];
      await svc.syncNow();
      final s = await repo.getWorkoutSession('srv-1');
      expect(s, isNotNull);
      expect(s!.dirty, isFalse);
    });

    test(
      'resume uses saved signature+offset to skip already-uploaded prefix',
      () async {
        final base = DateTime.parse('2024-03-01T10:00:00Z');
        // Three dirty completed sessions with deterministic order by startTime then id: a, b, c
        await repo.createWorkoutSession(
          WorkoutSession(
            id: 'a',
            name: 'A',
            startTime: base,
            endTime: base.add(const Duration(hours: 1)),
            exercises: const [],
            dirty: true,
          ),
        );
        await repo.createWorkoutSession(
          WorkoutSession(
            id: 'b',
            name: 'B',
            startTime: base.add(const Duration(minutes: 1)),
            endTime: base.add(const Duration(hours: 1, minutes: 1)),
            exercises: const [],
            dirty: true,
          ),
        );
        await repo.createWorkoutSession(
          WorkoutSession(
            id: 'c',
            name: 'C',
            startTime: base.add(const Duration(minutes: 2)),
            endTime: base.add(const Duration(hours: 1, minutes: 2)),
            exercises: const [],
            dirty: true,
          ),
        );

        // Save signature for [a,b,c] and set offset=1, meaning a is already uploaded
        await prefs.setWorkoutsUploadSignature('a|b|c');
        await prefs.setWorkoutsUploadOffset(1);

        await svc.syncNow();

        // Expect the first call to contain b and c, not a
        expect(api.callPayloads.isNotEmpty, isTrue);
        final sentIds = api.callPayloads
            .expand((x) => x.map((m) => m['id'] as String))
            .toList();
        expect(sentIds.contains('a'), isFalse);
        expect(sentIds.contains('b'), isTrue);
        expect(sentIds.contains('c'), isTrue);
      },
    );
  });
}
