import '../models/connection.dart';

abstract class ConnectionsRepository {
  /// List the user's connected AI apps.
  Future<List<Connection>> list();

  /// Read the authenticated account's first-party WebMCP food auto-log setting.
  /// Missing server state is returned as false.
  Future<bool> getWebMcpFoodAutoLog();

  /// Save the first-party WebMCP food auto-log setting. The server response is
  /// authoritative and no client/kind can be supplied by this call.
  Future<bool> setWebMcpFoodAutoLog(bool enabled);

  /// Step a connection down to read-only (drop its `propose:` scopes).
  Future<void> stepDown(String clientId);

  /// Grant a connection the `propose:` scope (the inverse of [stepDown]). Takes
  /// effect on the app's next token refresh.
  Future<void> stepUp(String clientId);

  /// Revoke (disconnect) a connection. Also retracts that connection's pending
  /// proposals server-side.
  Future<void> revoke(String clientId);

  /// Toggle a connection's auto-approve for one log kind ('food_log' /
  /// 'workout_log'). When enabled, that kind applies on arrival instead of
  /// waiting in the inbox; logs stay undoable in the app.
  Future<void> setAutoApprove({
    required String clientId,
    required String kind,
    required bool enabled,
  });
}
