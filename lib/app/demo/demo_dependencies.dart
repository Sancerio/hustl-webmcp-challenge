import 'package:get_it/get_it.dart';

import '../../features/ai_proposals/domain/repositories/proposals_repository.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/connections/domain/repositories/connections_repository.dart';
import '../../features/health_sync/domain/repositories/health_metrics_repository.dart';
import '../../features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import '../../features/nutrition_tracker/domain/repositories/food_repository.dart';
import '../../features/nutrition_tracker/domain/repositories/meal_scan_repository.dart';
import '../../features/nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';
import '../../features/nutrition_tracker/domain/repositories/recipes_repository.dart';
import '../../features/workout_logging/domain/repositories/workout_repository.dart';
import '../../features/workout_templates/domain/repositories/template_repository.dart';
import '../../core/webmcp/coaching_trends_api.dart';
import '../../core/webmcp/workout_history_web_mcp_service.dart';
import 'demo_auth_repository.dart';
import 'demo_coaching_trends_api.dart';
import 'demo_connections_repository.dart';
import 'demo_food_log_repository.dart';
import 'demo_food_repository.dart';
import 'demo_health_metrics_repository.dart';
import 'demo_meal_scan_repository.dart';
import 'demo_nutrition_targets_repository.dart';
import 'demo_proposals_repository.dart';
import 'demo_recipes_repository.dart';
import 'demo_state.dart';
import 'demo_template_repository.dart';
import 'demo_workout_repository.dart';
import 'demo_workout_history_web_mcp_service.dart';

/// Local midnight of "today" used to anchor all demo seeds.
///
/// Anchoring on the current day is the only `DateTime.now()` dependence allowed
/// by spec §10 — every other value is derived deterministically from this
/// anchor, so the same day always yields identical screens.
DateTime demoAnchor() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Registers the deterministic `Demo*` repositories in place of the real ones.
///
/// Called from `setupDependencies()` only when `kDemoMode` is true, *after* the
/// feature DI modules run, with reassignment enabled so the demo repositories
/// replace the real registrations regardless of whether a given feature module
/// registered its repository conditionally or unconditionally. The demo
/// implementations are lazily consumed by blocs/services, so overwriting the
/// (still-uninstantiated) lazy singletons is safe. When the flag is off this is
/// never called and behavior is unchanged.
void registerDemoDependencies(
  GetIt getIt, {
  DateTime? anchor,
  bool challengeMode = false,
}) {
  final resolvedAnchor = anchor ?? demoAnchor();
  final previousAllowReassignment = getIt.allowReassignment;
  getIt.allowReassignment = true;

  void put<T extends Object>(T instance) {
    getIt.registerSingleton<T>(instance);
  }

  // Auth: instantly authenticated persona.
  put<AuthRepository>(DemoAuthRepository());

  // Workout history + templates (drive Train, History, Progress, Body score,
  // and the workout summary heatmap).
  final workoutRepository = DemoWorkoutRepository(anchor: resolvedAnchor);
  final state = DemoState();
  final templateRepository = DemoTemplateRepository(anchor: resolvedAnchor);
  final foodLogRepository = DemoFoodLogRepository(anchor: resolvedAnchor);
  final nutritionTargetsRepository = DemoNutritionTargetsRepository(
    anchor: resolvedAnchor,
  );
  put<WorkoutRepository>(workoutRepository);
  put<TemplateRepository>(templateRepository);

  // WebMCP history/trends use explicit in-memory adapters so the evaluator
  // never constructs token storage or backend API clients for these reads.
  put<WorkoutHistoryWebMcpReader>(
    DemoWorkoutHistoryWebMcpService(
      repository: workoutRepository,
      anchor: resolvedAnchor,
    ),
  );
  put<CoachingTrendsApi>(const DemoCoachingTrendsApi());

  // Nutrition (diary, add-food, insights, weight).
  put<FoodLogRepository>(foodLogRepository);
  put<FoodRepository>(DemoFoodRepository());
  put<NutritionTargetsRepository>(nutritionTargetsRepository);
  put<RecipesRepository>(DemoRecipesRepository());
  put<MealScanRepository>(const DemoMealScanRepository());

  // Health metrics (overview, sleep, readiness, steps, weight track).
  put<HealthMetricsRepository>(
    DemoHealthMetricsRepository(poorRecovery: challengeMode),
  );

  // Connected AI apps (the connector-management surface). Registered here so the
  // later `setupConnectionsDependencies` call — which guards on isRegistered —
  // keeps this demo repo instead of the backend-backed Api implementation that
  // errors offline.
  put<ConnectionsRepository>(
    DemoConnectionsRepository(anchor: resolvedAnchor, state: state),
  );

  // AI proposals (the /proposals inbox + approval surface). Registered here so
  // the later `setupAiProposalsDependencies` call — which guards on isRegistered
  // — keeps this demo repo instead of the backend-backed Api implementation that
  // errors offline. The `ProposalCountService` poller reads pending counts off
  // this repo, so the inbox badge reflects the seeded proposals automatically.
  put<ProposalsRepository>(
    DemoProposalsRepository(
      anchor: resolvedAnchor,
      state: state,
      foodLogRepository: foodLogRepository,
      nutritionTargetsRepository: nutritionTargetsRepository,
      templateRepository: templateRepository,
    ),
  );

  getIt.allowReassignment = previousAllowReassignment;
}
