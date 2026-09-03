import 'package:get_it/get_it.dart';

import '../core/services/preferences_service.dart';
import '../core/webmcp/active_workout_web_mcp_controller.dart';
import '../core/webmcp/coaching_trends_api.dart';
import '../core/webmcp/coaching_trends_web_mcp_service.dart';
import '../core/webmcp/hustl_web_mcp_coordinator.dart';
import '../core/webmcp/template_web_mcp_service.dart';
import '../core/webmcp/today_context_service.dart';
import '../core/webmcp/web_mcp_access_gate.dart';
import '../core/webmcp/workout_history_web_mcp_service.dart';
import '../features/ai_proposals/domain/repositories/food_log_revision_proposal_repository.dart';
import '../features/ai_proposals/domain/repositories/proposals_repository.dart';
import '../features/ai_proposals/presentation/bloc/proposal_history_cubit.dart';
import '../features/ai_proposals/presentation/bloc/proposals_bloc.dart';
import '../features/ai_proposals/services/proposal_count_service.dart';
import '../features/ai_proposals/services/proposal_events_service.dart';
import '../features/health_sync/domain/repositories/health_metrics_repository.dart';
import '../features/health_sync/domain/usecases/load_latest_readiness.dart';
import '../features/exercise_library/data/datasources/exercise_seed_datasource.dart';
import '../features/exercise_library/data/repositories/evaluator_exercise_repository.dart';
import '../features/exercise_library/domain/repositories/exercise_repository.dart';
import '../features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import '../features/nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';
import '../features/nutrition_tracker/presentation/diary_refresh_signal.dart';
import '../features/workout_logging/domain/repositories/workout_repository.dart';
import '../features/workout_logging/domain/services/inactivity_service.dart';
import '../features/workout_logging/domain/services/rest_timer_service.dart';
import '../features/workout_logging/domain/services/workout_events_service.dart';
import '../features/workout_templates/domain/repositories/template_repository.dart';
import '../core/services/notification_service.dart';
import 'demo/demo_coaching_trends_api.dart';
import 'demo/demo_dependencies.dart';

final GetIt getIt = GetIt.instance;

Future<void> setupPublicDependencies() async {
  final preferences = PreferencesService();
  await preferences.init();
  getIt.registerSingleton<PreferencesService>(preferences);

  registerDemoDependencies(getIt, challengeMode: true);
  getIt.registerLazySingleton<ExerciseSeedDataSource>(
    () => const AssetExerciseSeedDataSource(),
  );
  getIt.registerLazySingleton<ExerciseRepository>(
    () => EvaluatorExerciseRepository(seed: getIt<ExerciseSeedDataSource>()),
  );
  getIt.registerSingleton<NotificationService>(const NotificationService());
  getIt.registerLazySingleton<RestTimerService>(
    () => RestTimerService(notificationService: getIt<NotificationService>()),
  );
  getIt.registerFactory<InactivityService>(
    () => InactivityService(
      notificationService: getIt<NotificationService>(),
      preferencesService: preferences,
    ),
  );
  getIt.registerLazySingleton<WorkoutEventsService>(WorkoutEventsService.new);
  getIt.registerLazySingleton<DiaryRefreshSignal>(() => DiaryRefreshSignal());
  getIt.registerLazySingleton<LoadLatestReadinessUseCase>(
    () => LoadLatestReadinessUseCase(getIt<HealthMetricsRepository>()),
  );

  getIt.registerLazySingleton<ProposalEventsService>(ProposalEventsService.new);
  getIt.registerLazySingleton<ProposalCountService>(
    () => ProposalCountService(
      null,
      getIt<ProposalsRepository>(),
      getIt<ProposalEventsService>(),
    )..start(),
  );
  getIt.registerFactory<ProposalsBloc>(
    () => ProposalsBloc(
      repository: getIt<ProposalsRepository>(),
      events: getIt<ProposalEventsService>(),
      templateRepository: getIt<TemplateRepository>(),
      diaryRefreshSignal: getIt<DiaryRefreshSignal>(),
    ),
  );
  getIt.registerFactory<ProposalHistoryCubit>(
    () => ProposalHistoryCubit(
      repository: getIt<ProposalsRepository>(),
      diaryRefreshSignal: getIt<DiaryRefreshSignal>(),
    ),
  );

  final accessGate = WebMcpAccessGate()..setReady(true);
  getIt.registerSingleton<WebMcpAccessGate>(accessGate);
  getIt.registerSingleton<ActiveWorkoutWebMcpController>(
    ActiveWorkoutWebMcpController(accessGate: accessGate),
  );
  getIt.registerLazySingleton<TodayContextService>(
    () => TodayContextService(
      workoutRepository: getIt<WorkoutRepository>() as ReadOnlyWorkoutRepository,
      healthRepository: getIt<HealthMetricsRepository>(),
      foodLogRepository: getIt<FoodLogRepository>() as ReadOnlyFoodLogRepository,
      nutritionTargetsRepository:
          getIt<NutritionTargetsRepository>() as ReadOnlyNutritionTargetsRepository,
      proposalsRepository: getIt<ProposalsRepository>(),
    ),
  );
  getIt.registerLazySingleton<HustlWebMcpCoordinator>(
    () => HustlWebMcpCoordinator(
      todayContextService: getIt<TodayContextService>(),
      accessGate: accessGate,
      activeWorkoutController: getIt<ActiveWorkoutWebMcpController>(),
      proposalsRepository: getIt<ProposalsRepository>(),
      foodLogRevisionRepository:
          getIt<ProposalsRepository>() as FoodLogRevisionProposalRepository,
      foodLogRepository: getIt<FoodLogRepository>() as ReadOnlyFoodLogRepository,
      templateService: TemplateWebMcpService(repository: getIt<TemplateRepository>()),
      workoutHistoryService: getIt<WorkoutHistoryWebMcpReader>(),
      coachingTrendsService: CoachingTrendsWebMcpService(
        api: getIt.isRegistered<CoachingTrendsApi>()
            ? getIt<CoachingTrendsApi>()
            : const DemoCoachingTrendsApi(),
      ),
      proposalCountService: getIt<ProposalCountService>(),
      diaryRefreshSignal: getIt<DiaryRefreshSignal>(),
    ),
  );
}
