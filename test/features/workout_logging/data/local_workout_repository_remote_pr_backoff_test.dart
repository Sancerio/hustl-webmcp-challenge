import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/token_storage.dart' as token;
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/exercise_library/domain/repositories/exercise_repository.dart';
import 'package:hustl_app/features/workout_logging/data/datasources/hustl_backend_workout_exercise_stats_api.dart';
import 'package:hustl_app/features/workout_logging/data/repositories/local_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';

class _FakeExerciseRepo extends ExerciseRepository {
  @override
  Future<List<Exercise>> getAllExercises() async => const [];

  @override
  Future<List<Exercise>> getExercisesByMuscle(String muscle) async => const [];

  @override
  Future<List<Exercise>> searchExercises(String query) async => const [];

  @override
  Future<List<Exercise>> getCustomExercises() async => const [];

  @override
  Future<Exercise> addCustomExercise(Exercise exercise) async => exercise;

  @override
  Future<void> removeCustomExercise(Exercise exercise) async {}
}

class _FakeTokenStorage implements token.TokenStorage {
  _FakeTokenStorage(this._access);

  String? _access;

  void setAccessToken(String? value) {
    _access = value;
  }

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

class _FakeStatsApi extends HustlBackendWorkoutExerciseStatsApi {
  _FakeStatsApi({required super.tokens, required this.onFetchPr});

  final Future<ExercisePr?> Function(String name, {String? exerciseSlug})
  onFetchPr;

  @override
  Future<ExercisePr?> fetchExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) {
    return onFetchPr(exerciseName, exerciseSlug: exerciseSlug);
  }

  @override
  Future<List<WorkoutSet>> fetchPreviousExerciseSets(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    return const <WorkoutSet>[];
  }
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    SharedPreferences.setMockInitialValues({});
    GetIt.I.registerLazySingleton<ExerciseRepository>(
      () => _FakeExerciseRepo(),
    );
    GetIt.I.registerSingleton<token.TokenStorage>(_FakeTokenStorage('token'));
  });

  test('does not spam remote PR requests after failure', () async {
    var attempts = 0;

    final repo = LocalWorkoutRepository(
      statsApiFactory: (tokens) => _FakeStatsApi(
        tokens: tokens,
        onFetchPr: (name, {exerciseSlug}) async {
          attempts += 1;
          throw Exception('offline');
        },
      ),
    );

    final pr1 = await repo.getExercisePr('Bench Press');
    expect(pr1, isNull);
    expect(attempts, 1);

    final pr2 = await repo.getExercisePr('Bench Press');
    expect(pr2, isNull);
    expect(attempts, 1, reason: 'second call should be backoff-cached');
  });

  test('clears PR cache when auth token changes', () async {
    final tokens = GetIt.I<token.TokenStorage>() as _FakeTokenStorage;
    var user = 1;

    final repo = LocalWorkoutRepository(
      statsApiFactory: (tokens) => _FakeStatsApi(
        tokens: tokens,
        onFetchPr: (name, {exerciseSlug}) async {
          if (user == 1) {
            return const ExercisePr(weight: 200, reps: 1);
          }
          return null;
        },
      ),
    );

    final pr1 = await repo.getExercisePr('Bench Press');
    expect(pr1, isNotNull);
    expect(pr1!.weight, 200);

    // Simulate sign-out/account switch by changing the access token, then
    // returning null for the new user.
    user = 2;
    tokens.setAccessToken('token-2');

    final pr2 = await repo.getExercisePr('Bench Press');
    expect(
      pr2,
      isNull,
      reason: 'old user PR must not leak across token change',
    );
  });
}
