import 'package:get_it/get_it.dart';

import '../../core/services/token_storage.dart';
import '../../core/webmcp/web_mcp_access_gate.dart';
import 'data/datasources/connections_api.dart';
import 'data/repositories/api_connections_repository.dart';
import 'domain/repositories/connections_repository.dart';
import 'presentation/bloc/connections_bloc.dart';

/// Registers the connected-apps (connector management) feature. Mirrors
/// `setupAiProposalsDependencies`: API + repository as lazy singletons and the
/// bloc as a factory (fresh per screen). Guards every registration so it's safe
/// to call more than once.
void setupConnectionsDependencies(GetIt getIt) {
  if (!getIt.isRegistered<ConnectionsApi>()) {
    getIt.registerLazySingleton<ConnectionsApi>(
      () => ConnectionsApi(tokens: TokenStorage()),
    );
  }

  if (!getIt.isRegistered<ConnectionsRepository>()) {
    getIt.registerLazySingleton<ConnectionsRepository>(
      () => ApiConnectionsRepository(getIt<ConnectionsApi>()),
    );
  }

  getIt.registerFactory<ConnectionsBloc>(
    () => ConnectionsBloc(
      repository: getIt<ConnectionsRepository>(),
      accessGate: getIt.isRegistered<WebMcpAccessGate>()
          ? getIt<WebMcpAccessGate>()
          : null,
    ),
  );
}
