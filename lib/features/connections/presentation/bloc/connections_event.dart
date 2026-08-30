import 'package:equatable/equatable.dart';

abstract class ConnectionsEvent extends Equatable {
  const ConnectionsEvent();

  @override
  List<Object?> get props => [];
}

/// Initial load of the connected-apps list.
class LoadConnections extends ConnectionsEvent {
  const LoadConnections();
}

/// Pull-to-refresh / silent re-fetch.
class RefreshConnections extends ConnectionsEvent {
  const RefreshConnections();
}

/// Set the authenticated account's first-party WebMCP food auto-log choice.
class SetWebMcpFoodAutoLog extends ConnectionsEvent {
  const SetWebMcpFoodAutoLog(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

/// Limit a connection to read-only (drop its `propose:` scopes).
class StepDownConnection extends ConnectionsEvent {
  const StepDownConnection(this.clientId);

  final String clientId;

  @override
  List<Object?> get props => [clientId];
}

/// Grant a connection the `propose:` scope (the inverse of [StepDownConnection]).
class StepUpConnection extends ConnectionsEvent {
  const StepUpConnection(this.clientId);

  final String clientId;

  @override
  List<Object?> get props => [clientId];
}

/// Disconnect (revoke) a connection. Also retracts its pending proposals.
class RevokeConnection extends ConnectionsEvent {
  const RevokeConnection(this.clientId);

  final String clientId;

  @override
  List<Object?> get props => [clientId];
}

/// Toggle auto-approve for one log kind on a connection. [kind] is 'food_log'
/// or 'workout_log'. Optimistically flips the flag; reverts on failure.
class SetAutoApprove extends ConnectionsEvent {
  const SetAutoApprove({
    required this.clientId,
    required this.kind,
    required this.enabled,
  });

  final String clientId;
  final String kind;
  final bool enabled;

  @override
  List<Object?> get props => [clientId, kind, enabled];
}
