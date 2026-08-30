import 'package:get_it/get_it.dart';
import '../../core/services/analytics_service.dart';
import '../../core/services/preferences_service.dart';
import '../../features/exercise_library/di.dart';
import '../../features/workout_logging/di.dart';
import '../../features/workout_logging/domain/repositories/workout_repository.dart';
import '../../features/workout_templates/di.dart';
import '../../features/nutrition_tracker/di.dart';
import '../../features/onboarding/di.dart';
import '../../features/ai_proposals/di.dart';
import '../../features/connections/di.dart';
import '../../features/auth/data/repositories/api_auth_repository.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/domain/services/account_migration_service.dart';
import '../../features/workout_logging/data/repositories/local_workout_repository.dart';
import '../../features/workout_templates/data/repositories/local_template_repository.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/theme_service.dart';
import '../../features/auth/domain/services/auth_redirect_service.dart';
import '../../core/navigation/current_route_service.dart';
import '../../core/navigation/last_training_route_service.dart';
import '../../features/workout_templates/data/services/template_sync_service.dart';
import '../../features/workout_templates/data/datasources/template_sync_api.dart';
import '../../features/workout_templates/domain/repositories/template_repository.dart';
import '../../core/services/token_storage.dart';
import '../../core/services/token_refresh.dart';
import '../../core/services/workout_widget_service.dart';
import '../../core/services/nutrition_widget_service.dart';
import '../../core/services/watch_bridge/watch_bridge_service.dart';
import '../../features/health_sync/di.dart';
import '../demo/demo_mode.dart';
import '../demo/demo_dependencies.dart';
import '../../features/nutrition_tracker/data/services/offline_food_log_queue.dart';
import '../../core/webmcp/hustl_web_mcp_coordinator.dart';
import '../../core/webmcp/today_context_service.dart';
import '../../core/webmcp/template_web_mcp_service.dart';
import '../../core/webmcp/web_mcp_config.dart';
import '../../core/webmcp/web_mcp_access_gate.dart';
import '../../core/webmcp/active_workout_web_mcp_controller.dart';
import '../../core/webmcp/workout_history_web_mcp_service.dart';
import '../../core/webmcp/coaching_trends_api.dart';
import '../../core/webmcp/coaching_trends_web_mcp_service.dart';
import '../../features/ai_proposals/domain/repositories/proposals_repository.dart';
import '../../features/ai_proposals/domain/repositories/food_log_revision_proposal_repository.dart';
import '../../features/ai_proposals/services/proposal_count_service.dart';
import '../../features/health_sync/domain/repositories/health_metrics_repository.dart';
import '../../features/nutrition_tracker/domain/repositories/food_log_repository.dart';
import '../../features/nutrition_tracker/domain/repositories/nutrition_targets_repository.dart';
import '../../features/nutrition_tracker/presentation/diary_refresh_signal.dart';
import '../../features/workout_logging/data/datasources/hustl_backend_workout_history_api.dart';
import '../../features/workout_logging/data/datasources/hustl_backend_exercise_history_api.dart';

final GetIt getIt = GetIt.instance;

/// One-time seed: mark the v3 onboarding gate "seen" for any user who is clearly
/// not a first-run user, so the default-on intro never replays for them. Checks
/// (cheapest first): a returning-user signal (web session / persisted non-guest),
/// then a completed-workout in local history (the native signal). Demo mode skips
/// onboarding outright. Bounded + best-effort: never throws, never blocks the
/// first frame for long.
Future<void> _seedOnboardingSeenForExistingUsers() async {
  final prefs = getIt<PreferencesService>();
  if (prefs.onboardingIntroSeen) return;
  if (kDemoMode) {
    await prefs.setOnboardingIntroSeen(true);
    return;
  }
  var returning = prefs.hasReturningUserSignal;
  if (!returning) {
    try {
      returning = await prefs.getHasWebSession();
    } catch (_) {}
  }
  // Native auth-token signal: a stored access/refresh token means this device has
  // a real (or refreshable) session, so the user is returning even before any
  // workout is logged. Bounded + best-effort; never throws.
  if (!returning) {
    try {
      final tokens = TokenStorage();
      final access = await tokens.getAccessToken().timeout(
        const Duration(seconds: 2),
      );
      if (access != null && access.isNotEmpty) {
        returning = true;
      } else {
        final refresh = await tokens.getRefreshToken().timeout(
          const Duration(seconds: 2),
        );
        returning = refresh != null && refresh.isNotEmpty;
      }
    } catch (_) {}
  }
  if (!returning && getIt.isRegistered<WorkoutRepository>()) {
    try {
      // ANY local session (not only a completed one) is returning evidence — an
      // existing user mid-workout, or with only in-progress history, must never
      // be re-onboarded.
      final sessions = await getIt<WorkoutRepository>()
          .getWorkoutSessions(limit: 5)
          .timeout(const Duration(seconds: 2));
      returning = sessions.isNotEmpty;
    } catch (_) {}
  }
  if (returning) await prefs.setOnboardingIntroSeen(true);
}

/// Initialize all dependencies
Future<void> setupDependencies() async {
  // Register core services
  getIt.registerSingleton<PreferencesService>(PreferencesService());
  // Initialize preference service eagerly and await to avoid timing issues
  await getIt<PreferencesService>().init();

  // Privacy-safe, fire-and-forget client telemetry (no-op when compiled off or
  // the user opts out). Lazy so it's only built once a call site logs.
  getIt.registerLazySingleton<AnalyticsService>(
    () => AnalyticsService(preferences: getIt<PreferencesService>()),
  );

  // Register other services needed by features
  getIt.registerSingleton<NotificationService>(NotificationService());
  getIt.registerLazySingleton<AuthRedirectService>(() => AuthRedirectService());
  // Track current route globally for robust auth redirects
  getIt.registerSingleton<CurrentRouteService>(CurrentRouteService());
  // Track last visited Training tab for drawer navigation
  getIt.registerSingleton<LastTrainingRouteService>(LastTrainingRouteService());

  // Register feature dependencies
  setupExerciseLibraryDependencies(getIt);
  setupWorkoutLoggingDependencies(getIt);
  setupWorkoutTemplatesDependencies(getIt);
  setupHealthSyncDependencies(getIt);
  setupNutritionTrackerDependencies(getIt);
  registerOnboarding(getIt);

  // Seed the v3 onboarding gate as "seen" for already-onboarded users so the
  // default-on intro never replays for them. Awaited (inside runCriticalInit,
  // before the first frame) so the router's first redirect sees the seeded flag.
  await _seedOnboardingSeenForExistingUsers();

  // Register remaining services
  final themeService = ThemeService(getIt<PreferencesService>());
  await themeService.init();
  getIt.registerSingleton<ThemeService>(themeService);

  // Auth: backend-driven OAuth/auth API only
  getIt.registerLazySingleton<AuthRepository>(
    () => ApiAuthRepository(getIt<PreferencesService>()),
  );
  // Let any feature data source's getAccessToken() self-heal an expired token by
  // refreshing in place (single-flight) instead of dropping the bearer header
  // and 401-ing the request. Resolved lazily so the repo isn't built early.
  TokenRefreshCoordinator.refresher = () {
    final repo = getIt<AuthRepository>();
    return repo is ApiAuthRepository
        ? repo.ensureFreshToken()
        : Future<bool>.value(false);
  };
  // Wire the destructive local-data wipe to the EXPLICIT sign-out path only
  // (AuthBloc._onSignOut), so a transient auth-check/refresh failure that maps to
  // AuthUnauthenticated can never delete a returning user's local data. The
  // account-switch branch in AccountMigrationService.onAuthenticated remains the
  // primary guard against cross-account data bleed.
  getIt.registerFactory<AuthBloc>(
    () => AuthBloc(
      getIt<AuthRepository>(),
      onExplicitSignOut: () async {
        if (getIt.isRegistered<AccountMigrationService>()) {
          await getIt<AccountMigrationService>().onUnauthenticated();
        }
      },
    ),
  );

  // Guest→account upgrade + safe data migration across account switch/sign-out.
  // Resolves repos lazily at call time so it picks up the active (real or demo)
  // registration; wipe no-ops when the repo isn't a local store (e.g. demo).
  getIt.registerLazySingleton<AccountMigrationService>(
    () => AccountMigrationService(
      preferences: getIt<PreferencesService>(),
      wipeLocalWorkouts: () async {
        final repo = getIt.isRegistered<WorkoutRepository>()
            ? getIt<WorkoutRepository>()
            : null;
        if (repo is LocalWorkoutRepository) await repo.clearAll();
      },
      wipeLocalTemplates: () async {
        final repo = getIt.isRegistered<TemplateRepository>()
            ? getIt<TemplateRepository>()
            : null;
        if (repo is LocalTemplateRepository) await repo.clearAll();
      },
      wipeNutrition: () => OfflineFoodLogQueue().clear(),
    ),
  );

  // Demo mode: replace the real repositories with deterministic in-memory
  // demo implementations (no-op when HUSTL_DEMO is not set). Runs after the
  // feature modules + auth so it cleanly overrides their registrations.
  if (kDemoMode) {
    registerDemoDependencies(getIt, challengeMode: kChallengeMode);
  }

  // Template sync service (local-first; backend later)
  if (getIt.isRegistered<PreferencesService>() &&
      getIt.isRegistered<TemplateRepository>()) {
    getIt.registerLazySingleton<TemplateSyncService>(
      () => TemplateSyncService(
        getIt<PreferencesService>(),
        TokenStorage(),
        getIt<TemplateRepository>(),
        TemplateSyncApi(),
        getIt.isRegistered<NotificationService>()
            ? getIt<NotificationService>()
            : null,
      ),
    );
  }

  // AI proposals (approval surface for connector-proposed template writes).
  // Registered after TemplateRepository + TemplateSyncService so the bloc's
  // dependencies resolve when a screen later constructs it.
  setupAiProposalsDependencies(getIt);

  // Connected AI apps (connector management: list / step-down / revoke).
  setupConnectionsDependencies(getIt);

  // Browser-provided WebMCP tools are compiled off by default. Register their
  // read model after demo overrides and all consumed repositories so the same
  // coordinator naturally serves real or deterministic demo data.
  if (kWebMcpEnabled) {
    getIt.registerSingleton<WebMcpAccessGate>(WebMcpAccessGate());
    getIt.registerSingleton<ActiveWorkoutWebMcpController>(
      ActiveWorkoutWebMcpController(accessGate: getIt<WebMcpAccessGate>()),
      dispose: (controller) => controller.dispose(),
    );
    getIt.registerLazySingleton<TodayContextService>(
      () => TodayContextService(
        workoutRepository:
            getIt<WorkoutRepository>() as ReadOnlyWorkoutRepository,
        healthRepository: getIt<HealthMetricsRepository>(),
        foodLogRepository:
            getIt<FoodLogRepository>() as ReadOnlyFoodLogRepository,
        nutritionTargetsRepository:
            getIt<NutritionTargetsRepository>()
                as ReadOnlyNutritionTargetsRepository,
        proposalsRepository: getIt<ProposalsRepository>(),
      ),
    );
    getIt.registerLazySingleton<HustlWebMcpCoordinator>(
      () => HustlWebMcpCoordinator(
        todayContextService: getIt<TodayContextService>(),
        accessGate: getIt<WebMcpAccessGate>(),
        activeWorkoutController: getIt<ActiveWorkoutWebMcpController>(),
        proposalsRepository: getIt<ProposalsRepository>(),
        foodLogRevisionRepository:
            getIt<ProposalsRepository>() as FoodLogRevisionProposalRepository,
        foodLogRepository:
            getIt<FoodLogRepository>() as ReadOnlyFoodLogRepository,
        templateService: TemplateWebMcpService(
          repository: getIt<TemplateRepository>(),
          isSyncedForEdit: kDemoMode
              ? (_) async => true
              : (templateId) async {
                  final preferences = getIt<PreferencesService>();
                  final version = await preferences.getTemplateSyncVersion(
                    templateId,
                  );
                  if (version == null) return false;
                  final dirtyIds = await preferences.getTemplatesDirtyIds();
                  return !dirtyIds.contains(templateId);
                },
        ),
        workoutHistoryService: kDemoMode
            ? getIt<WorkoutHistoryWebMcpReader>()
            : WorkoutHistoryWebMcpService(
                historyApi: HustlBackendWorkoutHistoryApi(
                  tokens: TokenStorage(),
                ),
                exerciseApi: HustlBackendExerciseHistoryApi(
                  tokens: TokenStorage(),
                ),
              ),
        coachingTrendsService: CoachingTrendsWebMcpService(
          api: kDemoMode
              ? getIt<CoachingTrendsApi>()
              : HustlBackendCoachingTrendsApi(tokens: TokenStorage()),
        ),
        proposalCountService: getIt.isRegistered<ProposalCountService>()
            ? getIt<ProposalCountService>()
            : null,
        diaryRefreshSignal: getIt.isRegistered<DiaryRefreshSignal>()
            ? getIt<DiaryRefreshSignal>()
            : null,
        telemetry: (name, properties) =>
            getIt<AnalyticsService>().logEvent(name, props: properties),
      ),
    );
  }

  if (!getIt.isRegistered<WorkoutWidgetService>()) {
    getIt.registerLazySingleton<WorkoutWidgetService>(
      () => WorkoutWidgetService(),
    );
  }

  if (!getIt.isRegistered<NutritionWidgetService>()) {
    getIt.registerLazySingleton<NutritionWidgetService>(
      () => NutritionWidgetService(),
    );
  }

  if (!getIt.isRegistered<WatchBridgeService>()) {
    getIt.registerLazySingleton<WatchBridgeService>(
      () => WatchBridgeService(preferences: getIt<PreferencesService>()),
    );
    // No-op safely when unsupported (non-iOS/web).
    // ignore: discarded_futures
    getIt<WatchBridgeService>().init();
  }
}
