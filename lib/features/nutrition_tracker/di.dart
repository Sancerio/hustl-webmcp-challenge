import 'package:get_it/get_it.dart';

import '../../core/services/token_storage.dart';
import 'data/datasources/hustl_backend_nutrition_api.dart';
import 'data/repositories/food_log_repository_impl.dart';
import 'data/repositories/food_repository_impl.dart';
import 'data/repositories/meal_scan_repository_impl.dart';
import 'data/repositories/nutrition_targets_repository_impl.dart';
import 'data/repositories/recipes_repository_impl.dart';
import 'data/services/offline_food_log_queue.dart';
import 'data/sources/local_food_index.dart';
import 'domain/repositories/food_log_repository.dart';
import 'domain/repositories/food_repository.dart';
import 'domain/repositories/meal_scan_repository.dart';
import 'domain/repositories/nutrition_targets_repository.dart';
import 'domain/repositories/recipes_repository.dart';
import 'presentation/diary_refresh_signal.dart';

void setupNutritionTrackerDependencies(GetIt getIt) {
  if (!getIt.isRegistered<TokenStorage>()) {
    getIt.registerLazySingleton<TokenStorage>(() => TokenStorage());
  }

  if (!getIt.isRegistered<DiaryRefreshSignal>()) {
    getIt.registerLazySingleton<DiaryRefreshSignal>(() => DiaryRefreshSignal());
  }

  if (!getIt.isRegistered<HustlBackendNutritionApi>()) {
    getIt.registerLazySingleton<HustlBackendNutritionApi>(
      () => HustlBackendNutritionApi(tokens: getIt<TokenStorage>()),
    );
  }

  if (!getIt.isRegistered<LocalFoodIndex>()) {
    getIt.registerLazySingleton<LocalFoodIndex>(() => LocalFoodIndex());
  }

  if (!getIt.isRegistered<FoodRepository>()) {
    getIt.registerLazySingleton<FoodRepository>(
      () => FoodRepositoryImpl(
        api: getIt<HustlBackendNutritionApi>(),
        localFoodIndex: getIt<LocalFoodIndex>(),
      ),
    );
  }

  if (!getIt.isRegistered<OfflineFoodLogQueue>()) {
    getIt.registerLazySingleton<OfflineFoodLogQueue>(
      () => OfflineFoodLogQueue(),
    );
  }

  if (!getIt.isRegistered<FoodLogRepository>()) {
    getIt.registerLazySingleton<FoodLogRepository>(
      () => FoodLogRepositoryImpl(
        api: getIt<HustlBackendNutritionApi>(),
        offlineQueue: getIt<OfflineFoodLogQueue>(),
      ),
    );
  }

  if (!getIt.isRegistered<NutritionTargetsRepository>()) {
    getIt.registerLazySingleton<NutritionTargetsRepository>(
      () => NutritionTargetsRepositoryImpl(
        api: getIt<HustlBackendNutritionApi>(),
      ),
    );
  }

  if (!getIt.isRegistered<RecipesRepository>()) {
    getIt.registerLazySingleton<RecipesRepository>(
      () => RecipesRepositoryImpl(api: getIt<HustlBackendNutritionApi>()),
    );
  }

  if (!getIt.isRegistered<MealScanRepository>()) {
    getIt.registerLazySingleton<MealScanRepository>(
      () => MealScanRepositoryImpl(api: getIt<HustlBackendNutritionApi>()),
    );
  }
}
