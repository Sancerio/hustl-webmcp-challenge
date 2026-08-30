import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/features/workout_logging/data/services/workout_sync_service.dart';
import 'package:hustl_app/features/workout_logging/data/datasources/workout_sync_api.dart';
import 'package:hustl_app/features/workout_logging/data/repositories/local_workout_repository.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/exercise_library/domain/repositories/exercise_repository.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/token_storage.dart' as token;

/// Repro + regression for the production WEB post-login freeze: the workout
/// sync used to pull ALL (~450) server workouts in ONE response, then decode +
/// hydrate + persist that whole blob inline. On Flutter web (no isolates) that
/// single synchronous burst froze the tab.
///
/// These tests prove:
///  1. The sync now PAGES the server delta in small batches (no single
///     huge-body decode/import over all ~450).
///  2. The longest synchronous burst on the event loop stays bounded — the
///     frame loop runs between pages (a yielding probe keeps firing).
///  3. All sessions are imported, idempotently (dedupe by id).

const int kTotalSessions = 455; // realistic large-history account

class _FakeTokenStorage implements token.TokenStorage {
  String? access = 'acc';
  @override
  Future<String?> getAccessToken() async => access;
  @override
  Future<String?> getRefreshToken() async => null;
  @override
  Future<void> saveTokenPair({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
  }) async {
    access = accessToken;
  }

  @override
  Future<void> clearAccessToken() async => access = null;
  @override
  Future<void> clearAll() async => access = null;
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

/// A server-side store of workout maps that the fake API pages over using the
/// same `last_sync_version` + `limit` cursor semantics as the real backend
/// (`sync.ts`): rows are ordered by sync_version and each call returns at most
/// `limit` rows whose sync_version > last_sync_version, advancing
/// new_sync_version to the cutoff.
class _PagingFakeApi implements WorkoutSyncApi {
  final List<Map<String, dynamic>> _rows; // each has a synthetic sync_version
  final List<int> requestedLimits = [];
  final List<int> pageSizesReturned = [];

  _PagingFakeApi(this._rows);

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
    // Mimic real network round-trip yielding to the event loop.
    await Future<void>.delayed(Duration.zero);
    final pageLimit = (limit == null || limit <= 0) ? 100 : limit;
    requestedLimits.add(pageLimit);

    final pending =
        _rows.where((r) => (r['_sv'] as int) > lastSyncVersion).toList()
          ..sort((a, b) => (a['_sv'] as int).compareTo(b['_sv'] as int));
    final page = pending.take(pageLimit).toList();
    pageSizesReturned.add(page.length);

    final newVersion = page.isEmpty ? lastSyncVersion : page.last['_sv'] as int;

    final serverWorkouts = page
        .map((r) => Map<String, dynamic>.from(r)..remove('_sv'))
        .toList();

    return (
      serverWorkouts: serverWorkouts,
      deletedWorkoutIds: const <String>[],
      newSyncVersion: newVersion,
    );
  }
}

List<Map<String, dynamic>> _buildServerRows(int count) {
  final base = DateTime.parse('2023-01-01T10:00:00Z');
  final rows = <Map<String, dynamic>>[];
  for (int i = 0; i < count; i++) {
    final start = base.add(Duration(hours: i));
    final end = start.add(const Duration(hours: 1));
    rows.add({
      '_sv': i + 1, // monotonic sync_version
      'id': 'srv-$i',
      'name': 'Workout $i',
      'start_time': start.toUtc().toIso8601String(),
      'end_time': end.toUtc().toIso8601String(),
      'status': 'completed',
      // ~5 exercises x ~4 sets — realistic body that makes the blob large.
      'exercises': [
        for (int e = 0; e < 5; e++)
          {
            'id': 'srv-$i-ex-$e',
            'exercise_name': 'Exercise $e',
            'order_index': e,
            'primary_muscles': const ['Chest', 'Triceps'],
            'sets': [
              for (int s = 0; s < 4; s++)
                {
                  'id': 'srv-$i-ex-$e-set-$s',
                  'set_number': s + 1,
                  'weight': 100.0 + s,
                  'reps': 8,
                  'is_completed': true,
                  'set_type': 'normal',
                },
            ],
          },
      ],
    });
  }
  return rows;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService prefs;
  late _FakeTokenStorage tokens;
  late LocalWorkoutRepository repo;
  late _PagingFakeApi api;
  late WorkoutSyncService svc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final gi = GetIt.instance;
    if (gi.isRegistered<ExerciseRepository>()) {
      gi.unregister<ExerciseRepository>();
    }
    gi.registerLazySingleton<ExerciseRepository>(() => _FakeExerciseRepo());

    prefs = PreferencesService();
    await prefs.init();
    tokens = _FakeTokenStorage();
    // Large cap so capacity trimming doesn't drop the synthetic history.
    repo = LocalWorkoutRepository(maxSessions: 1000);
    api = _PagingFakeApi(_buildServerRows(kTotalSessions));
    svc = WorkoutSyncService(prefs, tokens, repo, api);
  });

  tearDown(() {
    final gi = GetIt.instance;
    if (gi.isRegistered<ExerciseRepository>()) {
      gi.unregister<ExerciseRepository>();
    }
  });

  test(
    'sync pages the server delta in small batches (no single huge body)',
    () async {
      await svc.syncNow();

      // Every requested page must be small — the fix lowers the page limit well
      // below the whole history so no single decode/import spans all ~450.
      expect(api.requestedLimits, isNotEmpty);
      for (final lim in api.requestedLimits) {
        expect(
          lim,
          lessThanOrEqualTo(100),
          reason: 'page limit must be small (was $lim)',
        );
      }
      // The whole history must not arrive in one page.
      for (final size in api.pageSizesReturned) {
        expect(
          size,
          lessThan(kTotalSessions),
          reason: 'a single page returned the entire history ($size)',
        );
      }
      // Multiple pages were needed to drain ~455 sessions.
      expect(
        api.pageSizesReturned.where((s) => s > 0).length,
        greaterThan(1),
        reason: 'expected the delta to be drained across multiple pages',
      );
    },
  );

  test('all sessions are imported across pages, idempotently', () async {
    await svc.syncNow();
    final stored = await repo.getWorkoutSessions(limit: kTotalSessions * 2);
    expect(stored.length, kTotalSessions);

    // Run again: a second sync over the same (already-imported) data must not
    // duplicate anything (dedupe by id).
    // Reset the cursor so the second run re-pulls everything from scratch.
    await prefs.setWorkoutsSyncVersion(0);
    await svc.syncNow();
    final stored2 = await repo.getWorkoutSessions(limit: kTotalSessions * 2);
    expect(stored2.length, kTotalSessions);
    final ids = stored2.map((s) => s.id).toSet();
    expect(ids.length, kTotalSessions);
  });

  test(
    'the event loop keeps running during sync (no long synchronous burst)',
    () async {
      // A periodic probe fires every few ms. If a synchronous burst blocks the
      // single event loop (as the old all-at-once decode/hydrate/persist did),
      // the probe cannot fire and the gap between consecutive fires spikes.
      final fireTimes = <DateTime>[];
      final probe = Timer.periodic(const Duration(milliseconds: 4), (_) {
        fireTimes.add(DateTime.now());
      });

      await svc.syncNow();
      probe.cancel();

      expect(
        fireTimes.length,
        greaterThan(3),
        reason: 'probe should fire many times across a paged, yielding sync',
      );

      Duration maxGap = Duration.zero;
      for (int i = 1; i < fireTimes.length; i++) {
        final gap = fireTimes[i].difference(fireTimes[i - 1]);
        if (gap > maxGap) maxGap = gap;
      }

      // The longest the loop was blocked must stay well under a "frozen tab"
      // threshold. Importing all ~455 at once previously blocked for seconds;
      // a paged + yielding import keeps each burst short. Generous bound to stay
      // stable on slow CI while still failing on a whole-history burst.
      expect(
        maxGap,
        lessThan(const Duration(milliseconds: 800)),
        reason: 'longest synchronous burst was $maxGap — sync did not yield',
      );
    },
  );
}
