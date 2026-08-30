import 'package:get_it/get_it.dart';
import 'data/datasources/hustl_backend_exercise_api.dart';
import 'data/datasources/exercise_cache_local_datasource.dart';
import 'data/datasources/exercise_seed_datasource.dart';
import 'data/datasources/custom_exercise_local_datasource.dart';
import 'data/datasources/exercise_custom_api.dart';
import 'data/repositories/exercise_repository_impl.dart';
import 'domain/repositories/exercise_repository.dart';
import '../../core/services/token_storage.dart';

/// Register all dependencies for the exercise library feature
void setupExerciseLibraryDependencies(GetIt getIt) {
  // Backend + local cache datasources
  getIt.registerLazySingleton<HustlBackendExerciseApi>(
    () => HustlBackendExerciseApi(),
  );
  getIt.registerLazySingleton<ExerciseCustomApi>(() => ExerciseCustomApi());
  getIt.registerLazySingleton<ExerciseCacheDataSource>(
    () => ExerciseCacheLocalDataSource(),
  );
  getIt.registerLazySingleton<ExerciseSeedDataSource>(
    () => const AssetExerciseSeedDataSource(),
  );
  getIt.registerLazySingleton<CustomExerciseDataSource>(
    () => CustomExerciseLocalDataSource(),
  );
  if (!getIt.isRegistered<TokenStorage>()) {
    getIt.registerLazySingleton<TokenStorage>(() => TokenStorage());
  }

  // Repository with backend + offline cache + static fallback
  getIt.registerLazySingleton<ExerciseRepository>(
    () => ExerciseRepositoryImpl(
      backendApi: getIt<HustlBackendExerciseApi>(),
      customApi: getIt<ExerciseCustomApi>(),
      cache: getIt<ExerciseCacheDataSource>(),
      seed: getIt<ExerciseSeedDataSource>(),
      tokens: getIt<TokenStorage>(),
      custom: getIt<CustomExerciseDataSource>(),
    ),
  );
}
