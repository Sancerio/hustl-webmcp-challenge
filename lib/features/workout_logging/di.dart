import 'package:get_it/get_it.dart';
import 'domain/repositories/workout_repository.dart';
import 'domain/services/rest_timer_service.dart';
import 'domain/services/inactivity_service.dart';
import 'domain/services/workout_events_service.dart';
import '../../core/services/notification_service.dart';
import 'data/repositories/local_workout_repository.dart';
import 'domain/services/strong_csv_import_service.dart';
import 'data/datasources/workout_sync_api.dart';
import 'data/services/workout_sync_service.dart';
import '../../core/services/token_storage.dart';
import '../../core/services/preferences_service.dart';

/// Setup dependencies for workout logging
void setupWorkoutLoggingDependencies(GetIt getIt) {
  // Cross-feature notifications for workout mutations (e.g. watch bridge).
  if (!getIt.isRegistered<WorkoutEventsService>()) {
    getIt.registerLazySingleton<WorkoutEventsService>(
      () => WorkoutEventsService(),
      dispose: (s) => s.dispose(),
    );
  }

  // Register repositories
  getIt.registerLazySingleton<WorkoutRepository>(
    () => LocalWorkoutRepository(),
    dispose: (repo) {
      if (repo is LocalWorkoutRepository) {
        repo.dispose();
      }
    },
  );

  // Register services
  // RestTimerService is a shared singleton so a single timer instance
  // can survive screen/background transitions without being disposed.
  getIt.registerLazySingleton<RestTimerService>(
    () => RestTimerService(notificationService: getIt<NotificationService>()),
    dispose: (s) => s.dispose(),
  );
  getIt.registerFactory<InactivityService>(
    () => InactivityService(
      notificationService: getIt<NotificationService>(),
      preferencesService: getIt<PreferencesService>(),
    ),
  );
  getIt.registerLazySingleton<StrongCsvImportService>(
    () => StrongCsvImportService(),
  );
  getIt.registerLazySingleton<StrongCsvExportService>(
    () => StrongCsvExportService(),
  );

  // Sync API + Service
  getIt.registerLazySingleton<WorkoutSyncApi>(() => WorkoutSyncApi());
  getIt.registerLazySingleton<WorkoutSyncService>(
    () => WorkoutSyncService(
      getIt<PreferencesService>(),
      TokenStorage(),
      getIt<WorkoutRepository>(),
      getIt<WorkoutSyncApi>(),
      getIt<NotificationService>(),
    ),
  );

  // Register BLoCs and use cases in the future
}
