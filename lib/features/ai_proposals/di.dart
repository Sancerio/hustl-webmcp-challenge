import 'package:get_it/get_it.dart';

import '../../core/services/notification_service.dart';
import '../../core/services/preferences_service.dart';
import '../../core/services/token_storage.dart';
import '../nutrition_tracker/presentation/diary_refresh_signal.dart';
import '../workout_logging/data/services/workout_sync_service.dart';
import '../workout_templates/data/services/template_sync_service.dart';
import '../workout_templates/domain/repositories/template_repository.dart';
import 'data/datasources/proposals_api.dart';
import 'data/repositories/api_proposals_repository.dart';
import 'domain/repositories/proposals_repository.dart';
import 'presentation/bloc/proposal_history_cubit.dart';
import 'presentation/bloc/proposals_bloc.dart';
import 'services/proposal_count_service.dart';
import 'services/proposal_events_service.dart';

/// Registers the AI-proposals feature. Mirrors the other `setupX(getIt)`
/// modules: API + repository as lazy singletons, the events/count services as
/// singletons, and the bloc as a factory (fresh per screen). Guards every
/// registration so it's safe to call more than once.
void setupAiProposalsDependencies(GetIt getIt) {
  if (!getIt.isRegistered<ProposalsApi>()) {
    getIt.registerLazySingleton<ProposalsApi>(
      () => ProposalsApi(tokens: TokenStorage()),
    );
  }

  if (!getIt.isRegistered<ProposalsRepository>()) {
    getIt.registerLazySingleton<ProposalsRepository>(
      () => ApiProposalsRepository(getIt<ProposalsApi>()),
    );
  }

  if (!getIt.isRegistered<ProposalEventsService>()) {
    getIt.registerLazySingleton<ProposalEventsService>(
      () => ProposalEventsService(),
      dispose: (s) => s.dispose(),
    );
  }

  if (!getIt.isRegistered<ProposalCountService>()) {
    getIt.registerLazySingleton<ProposalCountService>(
      () => ProposalCountService(
        TokenStorage(),
        getIt<ProposalsRepository>(),
        getIt<ProposalEventsService>(),
        notifications: NotificationService(),
        preferences: PreferencesService(),
      ),
      dispose: (s) => s.stop(),
    );
  }

  getIt.registerFactory<ProposalsBloc>(
    () => ProposalsBloc(
      repository: getIt<ProposalsRepository>(),
      events: getIt<ProposalEventsService>(),
      templateRepository: getIt<TemplateRepository>(),
      syncService: getIt.isRegistered<TemplateSyncService>()
          ? getIt<TemplateSyncService>()
          : null,
      diaryRefreshSignal: getIt.isRegistered<DiaryRefreshSignal>()
          ? getIt<DiaryRefreshSignal>()
          : null,
      workoutSyncService: getIt.isRegistered<WorkoutSyncService>()
          ? getIt<WorkoutSyncService>()
          : null,
      preferences: PreferencesService(),
    ),
  );

  getIt.registerFactory<ProposalHistoryCubit>(
    () => ProposalHistoryCubit(
      repository: getIt<ProposalsRepository>(),
      diaryRefreshSignal: getIt.isRegistered<DiaryRefreshSignal>()
          ? getIt<DiaryRefreshSignal>()
          : null,
      workoutSyncService: getIt.isRegistered<WorkoutSyncService>()
          ? getIt<WorkoutSyncService>()
          : null,
    ),
  );
}
