// Reproduction + regression suite for the SECOND post-login web freeze on large
// histories (~455 sessions): `recomputeAllPrFlags`.
//
// On Flutter web there are no isolates, so `compute()` runs inline on the single
// UI thread and `unawaited(...)` does not move work off the frame loop -- it just
// defers WHEN the synchronous work runs. The legacy PR-flag migration
// (`recomputeAllPrFlags`) rebuilt every session's sets AND did one giant
// ~1.6MB `_persist()` (jsonEncode of the whole store) in a single synchronous
// burst, freezing the frame for seconds the first time a large-history account
// opened the Account screen on web.
//
// The fix chunks the recompute and yields to the event loop between batches so
// no single synchronous run blocks the frame. These tests prove the migration
// (a) still computes identical PR flags, and (b) yields control to the event
// loop while running, where the pre-fix version ran the whole 455-session
// rebuild + persist without yielding.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:hustl_app/features/workout_logging/data/repositories/local_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/core/services/preferences_service.dart';

// Legacy SharedPreferences prefixes every key with 'flutter.'.
const String _storageKey = 'flutter.workout_sessions_v1';

class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _data = {};
  final Map<String, int> setCount = {};

  void seed(String key, Object value) => _data[key] = value;
  int persistsOf(String key) => setCount[key] ?? 0;

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    setCount[key] = (setCount[key] ?? 0) + 1;
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> clear() async {
    _data.clear();
    return true;
  }

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    _data.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => Map<String, Object>.from(_data);

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async => Map<String, Object>.from(_data);
}

/// Builds [count] completed sessions with `isPr: false` on every set, so the
/// migration has real work to do. Each session has [exPerSession] exercises of
/// [setsPerSession] ascending-weight sets, which makes the first set per
/// exercise per session a fresh PR for that exercise key (deterministic).
List<Map<String, dynamic>> _buildSeed(
  int count, {
  int exPerSession = 4,
  int setsPerSession = 4,
}) {
  const pool = [
    Exercise(name: 'Bench Press', slug: 'bench-press', muscles: ['Chest']),
    Exercise(name: 'Squat', slug: 'squat', muscles: ['Quads']),
    Exercise(name: 'Deadlift', slug: 'deadlift', muscles: ['Back']),
    Exercise(name: 'Overhead Press', slug: 'overhead-press', muscles: ['Shoulders']),
  ];
  final List<Map<String, dynamic>> seed = [];
  final DateTime base = DateTime(2023, 1, 1, 9, 0, 0);
  for (int i = 0; i < count; i++) {
    final sessionStart = base.add(Duration(hours: i * 30));
    final exercises = <WorkoutExercise>[];
    for (int e = 0; e < exPerSession; e++) {
      final ex = pool[(i + e) % pool.length];
      final sets = <WorkoutSet>[
        for (int sIdx = 0; sIdx < setsPerSession; sIdx++)
          WorkoutSet(
            // Ascending weight across sessions guarantees deterministic PRs:
            // weight strictly increases with `i`, so the first completed set of
            // each exercise per session is a new PR for that exercise.
            id: 's-$i-$e-$sIdx',
            weight: 60.0 + i + sIdx * 5,
            reps: 8 - sIdx,
            isCompleted: true,
            isPr: false,
          ),
      ];
      exercises.add(WorkoutExercise(id: 'ex-$i-$e', exercise: ex, sets: sets));
    }
    seed.add(
      WorkoutSession(
        id: 'session-$i',
        name: 'Workout $i',
        startTime: sessionStart,
        endTime: sessionStart.add(const Duration(hours: 1)),
        exercises: exercises,
        isCompleted: true,
        dirty: false,
      ).toMap(),
    );
  }
  return seed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Store store;

  Future<void> seedAndInstall(List<Map<String, dynamic>> seed) async {
    store.seed(_storageKey, jsonEncode(seed));
    SharedPreferences.resetStatic();
    GetIt.instance.registerSingleton<PreferencesService>(PreferencesService());
    await GetIt.instance<PreferencesService>().init();
    store.setCount.clear();
  }

  setUp(() async {
    await GetIt.instance.reset();
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.resetStatic();
    // No ExerciseRepository registered: recompute does not need the catalog, and
    // leaving it out keeps this test focused on the migration's CPU/persist cost.
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  test(
    'recomputeAllPrFlags over 455 sessions yields to the event loop '
    '(no multi-second main-thread block)',
    () async {
      await seedAndInstall(_buildSeed(455));
      final repo = LocalWorkoutRepository();
      // Prime init so the first read is done before we time the migration.
      await repo.getWorkoutSessions();

      // A competing async loop that ticks via `Future.delayed(Duration.zero)`.
      // On the single event loop, this can only advance when `recomputeAllPrFlags`
      // YIELDS. If the migration runs as one synchronous burst, this loop gets
      // zero ticks until the migration finishes -- proving a frame-blocking stall.
      var competingTicks = 0;
      var keepTicking = true;
      Future<void> competing() async {
        while (keepTicking) {
          await Future<void>.delayed(Duration.zero);
          competingTicks++;
        }
      }

      final loop = competing();
      final sw = Stopwatch()..start();
      await repo.recomputeAllPrFlags();
      sw.stop();
      keepTicking = false;
      await loop;

      // ignore: avoid_print
      print('recomputeAllPrFlags(455): ${sw.elapsedMilliseconds}ms, '
          'competing ticks during migration=$competingTicks');

      // The migration must yield control while running: the competing loop must
      // have advanced multiple times mid-migration. (Pre-fix this is ~0.)
      expect(
        competingTicks,
        greaterThanOrEqualTo(2),
        reason: 'recomputeAllPrFlags must yield to the event loop between '
            'batches so it never blocks the frame as one synchronous burst',
      );
    },
  );

  test('recomputeAllPrFlags persists exactly once (single blob write)', () async {
    await seedAndInstall(_buildSeed(455));
    final repo = LocalWorkoutRepository();
    await repo.getWorkoutSessions();
    store.setCount.clear();

    await repo.recomputeAllPrFlags();

    expect(
      store.persistsOf(_storageKey),
      1,
      reason: 'Chunked recompute must still persist the store exactly once',
    );
  });

  test('recomputeAllPrFlags computes identical PR flags to a single-pass scan',
      () async {
    final seed = _buildSeed(60, exPerSession: 3, setsPerSession: 3);
    await seedAndInstall(seed);
    final repo = LocalWorkoutRepository();
    await repo.getWorkoutSessions();

    await repo.recomputeAllPrFlags();

    // Recompute the expected flags with a straightforward single-pass reference
    // implementation over sessions sorted oldest-first, then compare every set.
    final sessions = await repo.getWorkoutSessions();
    final byStartAsc = List<WorkoutSession>.from(sessions)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final Map<String, double> bestWeight = {};
    final Map<String, int> bestReps = {};
    final Map<String, bool> expectedPrBySetId = {};
    for (final s in byStartAsc) {
      for (final ex in s.exercises) {
        // Mirror LocalWorkoutRepository._keyForExercise exactly.
        final canonical = ex.exercise.canonicalKey;
        final String key = (canonical != null && canonical.isNotEmpty)
            ? canonical
            : (ex.exercise.name.trim().toLowerCase().isNotEmpty
                ? ex.exercise.name.trim().toLowerCase()
                : ex.exercise.name);
        var bw = bestWeight[key] ?? double.negativeInfinity;
        var br = bestReps[key] ?? -1;
        final assisted = ex.exercise.kind == ExerciseKind.assisted;
        for (final set in ex.sets) {
          var isPr = false;
          if (set.isCompleted &&
              set.setType != SetType.warmup &&
              set.setType != SetType.dropset) {
            if (assisted && set.weight >= 0) {
              isPr = false;
            } else if (set.weight > bw ||
                (set.weight == bw && set.reps > br)) {
              isPr = true;
              bw = set.weight;
              br = set.reps;
            }
          }
          expectedPrBySetId[set.id] = isPr;
        }
        bestWeight[key] = bw;
        bestReps[key] = br;
      }
    }

    var compared = 0;
    for (final s in sessions) {
      for (final ex in s.exercises) {
        for (final set in ex.sets) {
          expect(
            set.isPr,
            expectedPrBySetId[set.id],
            reason: 'PR flag mismatch for set ${set.id}',
          );
          compared++;
        }
      }
    }
    expect(compared, 60 * 3 * 3);
  });

  // P1 regression (data-loss race introduced by the chunked-migration web-freeze
  // fix): the migration snapshots `_sessions`, then yields between chunks. A
  // normal repository mutation (e.g. the user logging a workout right after login
  // while the migration runs in the background) can persist during a yield
  // window. The pre-fix migration then replaced `_sessions` wholesale from the
  // STALE snapshot, DROPPING the newly created workout. This proves the fix:
  // the concurrent create SURVIVES, and the migration still applies PR flags.
  test(
    'concurrent createWorkoutSession during a mid-migration yield SURVIVES '
    '(not clobbered by the stale snapshot) and PR flags are still applied',
    () async {
      // >50 sessions => the chunked migration crosses chunk boundaries and
      // yields to the event loop, opening the race window the concurrent
      // mutation lands in. All seed sets start `isPr: false` so the migration
      // has real work and flips at least one flag to true.
      await seedAndInstall(_buildSeed(140));
      // maxSessions high enough that the +1 concurrent session never triggers
      // LRU eviction of itself or the seeded history.
      final repo = LocalWorkoutRepository(maxSessions: 1000);
      await repo.getWorkoutSessions();

      // The brand-new workout the user logs while the migration is running.
      // Its set id is NOT in the migration's snapshot, so the merge must keep it.
      final concurrent = WorkoutSession(
        id: 'concurrent-new-session',
        name: 'Logged right after login',
        startTime: DateTime(2024, 6, 1, 18, 0, 0),
        endTime: DateTime(2024, 6, 1, 19, 0, 0),
        exercises: const [
          WorkoutExercise(
            id: 'ex-concurrent',
            exercise: Exercise(
              name: 'Bench Press',
              slug: 'bench-press',
              muscles: ['Chest'],
            ),
            sets: [
              WorkoutSet(
                id: 'set-concurrent',
                weight: 999.0, // heaviest ever => a PR for bench-press
                reps: 5,
                isCompleted: true,
                isPr: false,
              ),
            ],
          ),
        ],
        isCompleted: true,
        dirty: false,
      );

      // Start the migration WITHOUT awaiting, then immediately perform the
      // concurrent mutation. On the single event loop, the create interleaves
      // with the migration's between-chunk yields. We await the create first
      // (it persists during a yield window), then let the migration finish.
      final migration = repo.recomputeAllPrFlags();
      await repo.createWorkoutSession(concurrent);
      await migration;

      // 1) The concurrent session SURVIVES the migration (not dropped by a
      //    stale-snapshot replacement). This is the core data-loss assertion.
      final survivors = await repo.getWorkoutSessions();
      final survived = survivors.where(
        (s) => s.id == 'concurrent-new-session',
      );
      expect(
        survived.length,
        1,
        reason: 'A workout created during a mid-migration yield must NOT be '
            'dropped when the migration finishes',
      );

      // It must also be PERSISTED, not just live in memory: re-read from a fresh
      // repository instance backed by the same store.
      final repo2 = LocalWorkoutRepository(maxSessions: 1000);
      final reloaded = await repo2.getWorkoutSessions();
      expect(
        reloaded.any((s) => s.id == 'concurrent-new-session'),
        isTrue,
        reason: 'The concurrent workout must be durably persisted, not '
            'overwritten by the migration persisting the stale snapshot',
      );

      // 2) The migration still did its job: PR flags were applied to the seeded
      //    history. Seed weights ascend with session index, so the first
      //    completed set of each exercise per session is a PR; at minimum many
      //    flags must now be true (pre-migration they were all false).
      final prCount = survivors
          .where((s) => s.id != 'concurrent-new-session')
          .expand((s) => s.exercises)
          .expand((ex) => ex.sets)
          .where((set) => set.isPr)
          .length;
      expect(
        prCount,
        greaterThan(0),
        reason: 'recomputeAllPrFlags must still apply PR flags to the existing '
            'history while preserving the concurrent mutation',
      );
    },
  );
}
