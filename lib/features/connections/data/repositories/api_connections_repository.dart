import '../../domain/models/connection.dart';
import '../../domain/repositories/connections_repository.dart';
import '../datasources/connections_api.dart';

/// [ConnectionsRepository] backed by the backend app-plane endpoints via
/// [ConnectionsApi]. Maps the raw envelope payloads onto domain models.
class ApiConnectionsRepository implements ConnectionsRepository {
  ApiConnectionsRepository(this._api);

  final ConnectionsApi _api;

  @override
  Future<List<Connection>> list() async {
    final items = await _api.list();
    return items.map(Connection.fromJson).toList(growable: false);
  }

  @override
  Future<bool> getWebMcpFoodAutoLog() => _api.getWebMcpFoodAutoLog();

  @override
  Future<bool> setWebMcpFoodAutoLog(bool enabled) =>
      _api.setWebMcpFoodAutoLog(enabled);

  @override
  Future<void> stepDown(String clientId) async {
    await _api.stepDown(clientId);
  }

  @override
  Future<void> stepUp(String clientId) async {
    await _api.stepUp(clientId);
  }

  @override
  Future<void> revoke(String clientId) async {
    await _api.revoke(clientId);
  }

  @override
  Future<void> setAutoApprove({
    required String clientId,
    required String kind,
    required bool enabled,
  }) async {
    await _api.setAutoApprove(clientId: clientId, kind: kind, enabled: enabled);
  }
}
