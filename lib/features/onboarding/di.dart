import 'package:get_it/get_it.dart';

import '../../core/services/analytics_service.dart';
import '../../core/services/preferences_service.dart';
import '../health_sync/domain/repositories/health_metrics_repository.dart';
import '../nutrition_tracker/domain/repositories/food_log_repository.dart';
import '../workout_logging/domain/repositories/workout_repository.dart';
import 'domain/coach_readiness_service.dart';
import 'domain/onboarding_proposal_gate.dart';
import 'domain/onboarding_telemetry.dart';

/// Registers the onboarding feature's runtime services. Currently the coach-
/// readiness estimator that powers the first-win "Building your plan" summary.
/// Registered as a lazy singleton: the repository lookups inside the factory run
/// when the summary first reads it (well after DI), so registration order here
/// does not matter. Each optional repo is resolved defensively so a missing
/// module degrades to 0/false instead of throwing.
void registerOnboarding(GetIt getIt) {
  if (getIt.isRegistered<CoachReadinessService>()) return;
  getIt.registerLazySingleton<CoachReadinessService>(
    () => CoachReadinessService(
      workoutRepository: getIt<WorkoutRepository>(),
      foodLogRepository: getIt.isRegistered<FoodLogRepository>()
          ? getIt<FoodLogRepository>()
          : null,
      healthMetricsRepository: getIt.isRegistered<HealthMetricsRepository>()
          ? getIt<HealthMetricsRepository>()
          : null,
    ),
  );
  getIt.registerLazySingleton<OnboardingProposalGate>(
    () => OnboardingProposalGate(
      preferences: getIt<PreferencesService>(),
      readinessService: getIt<CoachReadinessService>(),
    ),
  );
  // Typed funnel telemetry wrapper over the core AnalyticsService.
  getIt.registerLazySingleton<OnboardingTelemetry>(
    () => OnboardingTelemetry(getIt<AnalyticsService>()),
  );
}
