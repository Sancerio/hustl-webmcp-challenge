import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get_it/get_it.dart';

import '../../core/services/preferences_service.dart';
import '../../core/services/token_storage.dart';
import '../workout_logging/domain/repositories/workout_repository.dart';
import 'data/datasources/hustl_backend_health_api.dart';
import 'data/repositories/backend_health_metrics_repository.dart';
import 'data/repositories/health_metrics_repository_impl.dart';
import 'data/services/health_cache_service.dart';
import 'data/services/health_backend_sync_service.dart';
import 'data/sources/external_activity_reader.dart';
import 'data/sources/health_platform_source.dart';
import 'data/writeback/health_workout_write_service.dart';
import 'data/writeback/workout_write_queue.dart';
import 'data/writeback/workout_writeback_coordinator.dart';
import 'domain/repositories/health_metrics_repository.dart';
import 'domain/services/external_activity_filter.dart';
import 'domain/services/strain_attribution_service.dart';
import 'domain/usecases/derive_health_insights.dart';
import 'domain/usecases/load_latest_readiness.dart';
import 'domain/usecases/load_recovery_trend.dart';
import 'domain/writeback/workout_write_service.dart';
import 'presentation/bloc/health_overview_bloc.dart';
import 'presentation/bloc/health_permissions_bloc.dart';

void setupHealthSyncDependencies(GetIt getIt) {
  if (!getIt.isRegistered<TokenStorage>()) {
    getIt.registerLazySingleton<TokenStorage>(() => TokenStorage());
  }

  if (!getIt.isRegistered<HealthPlatformSource>()) {
    getIt.registerLazySingleton<HealthPlatformSource>(
      () => HealthPlatformSource(),
    );
  }

  if (!getIt.isRegistered<HealthCacheService>()) {
    getIt.registerLazySingleton<HealthCacheService>(
      () => HealthCacheService(getIt<PreferencesService>()),
    );
  }

  if (!getIt.isRegistered<HustlBackendHealthApi>()) {
    getIt.registerLazySingleton<HustlBackendHealthApi>(
      () => HustlBackendHealthApi(tokens: getIt<TokenStorage>()),
    );
  }

  if (!getIt.isRegistered<HealthMetricsRepository>()) {
    getIt.registerLazySingleton<HealthMetricsRepository>(
      () => kIsWeb
          ? BackendHealthMetricsRepository(api: getIt<HustlBackendHealthApi>())
          : HealthMetricsRepositoryImpl(
              platformSource: getIt<HealthPlatformSource>(),
              cacheService: getIt<HealthCacheService>(),
              preferencesService: getIt<PreferencesService>(),
            ),
    );
  }

  if (!getIt.isRegistered<HealthBackendSyncService>()) {
    getIt.registerLazySingleton<HealthBackendSyncService>(
      () => HealthBackendSyncService(
        platformSource: getIt<HealthPlatformSource>(),
        api: getIt<HustlBackendHealthApi>(),
        tokens: getIt<TokenStorage>(),
        preferences: getIt<PreferencesService>(),
        externalActivityReader: getIt<ExternalActivityReader>(),
        externalActivityFilter: getIt<ExternalActivityFilter>(),
        workoutRepository: getIt<WorkoutRepository>(),
        enableCrossPlatformHealthSync: true,
      ),
    );
  }

  if (!getIt.isRegistered<WorkoutWriteService>()) {
    getIt.registerLazySingleton<WorkoutWriteService>(
      () => HealthWorkoutWriteService(preferences: getIt<PreferencesService>()),
    );
  }

  if (!getIt.isRegistered<WorkoutWriteQueue>()) {
    getIt.registerLazySingleton<WorkoutWriteQueue>(
      () => WorkoutWriteQueue(
        getIt<PreferencesService>(),
        getIt<WorkoutWriteService>(),
      ),
    );
  }

  if (!getIt.isRegistered<WorkoutWritebackCoordinator>()) {
    getIt.registerLazySingleton<WorkoutWritebackCoordinator>(
      () => WorkoutWritebackCoordinator(
        queue: getIt<WorkoutWriteQueue>(),
        service: getIt<WorkoutWriteService>(),
        preferences: getIt<PreferencesService>(),
        workoutRepository: getIt<WorkoutRepository>(),
      ),
    );
  }

  // External-activity read path + strain attribution (plan 011). The reader
  // fetches platform workouts on demand; the filter and attribution service are
  // pure and stateless. Registered as lazy singletons matching this file's
  // idiom and guarded so re-entrant setup is a no-op.
  if (!getIt.isRegistered<ExternalActivityReader>()) {
    getIt.registerLazySingleton<ExternalActivityReader>(
      () => ExternalActivityReader(),
    );
  }

  if (!getIt.isRegistered<ExternalActivityFilter>()) {
    getIt.registerLazySingleton<ExternalActivityFilter>(
      () => const ExternalActivityFilter(),
    );
  }

  if (!getIt.isRegistered<StrainAttributionService>()) {
    getIt.registerLazySingleton<StrainAttributionService>(
      () => const StrainAttributionService(),
    );
  }

  if (!getIt.isRegistered<DeriveHealthInsightsUseCase>()) {
    getIt.registerLazySingleton<DeriveHealthInsightsUseCase>(
      () => DeriveHealthInsightsUseCase(),
    );
  }

  // Lightweight latest-readiness read for the Train home (R2). Reuses the same
  // repository the dashboard uses; never blocks or duplicates scoring logic.
  if (!getIt.isRegistered<LoadLatestReadinessUseCase>()) {
    getIt.registerLazySingleton<LoadLatestReadinessUseCase>(
      () => LoadLatestReadinessUseCase(getIt<HealthMetricsRepository>()),
    );
  }

  // Compact recovery-trend read for the Progress "Recovery trend" card (R3).
  // Reuses the same repository so Progress and Health never disagree.
  if (!getIt.isRegistered<LoadRecoveryTrendUseCase>()) {
    getIt.registerLazySingleton<LoadRecoveryTrendUseCase>(
      () => LoadRecoveryTrendUseCase(getIt<HealthMetricsRepository>()),
    );
  }

  getIt.registerFactory<HealthPermissionsBloc>(
    () => HealthPermissionsBloc(getIt<HealthMetricsRepository>()),
  );

  getIt.registerFactory<HealthOverviewBloc>(
    () => HealthOverviewBloc(
      getIt<HealthMetricsRepository>(),
      deriveInsights: getIt<DeriveHealthInsightsUseCase>(),
    ),
  );
}
