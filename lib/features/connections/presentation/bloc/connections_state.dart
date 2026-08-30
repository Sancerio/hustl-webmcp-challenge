import 'package:equatable/equatable.dart';

import '../../domain/models/connection.dart';

/// The result of a just-completed connection action, carried on
/// [ConnectionsLoaded] so the screen can surface a one-shot [HustlSnack].
enum ConnectionActionKind { steppedDown, steppedUp, revoked }

class ConnectionActionOutcome extends Equatable {
  const ConnectionActionOutcome({required this.kind, required this.clientName});

  final ConnectionActionKind kind;

  /// The (untrusted) display name of the affected connection, for the toast.
  final String clientName;

  @override
  List<Object?> get props => [kind, clientName];
}

abstract class ConnectionsState extends Equatable {
  const ConnectionsState();

  @override
  List<Object?> get props => [];
}

class ConnectionsInitial extends ConnectionsState {
  const ConnectionsInitial();
}

class ConnectionsLoading extends ConnectionsState {
  const ConnectionsLoading();
}

/// Loaded list.
///
/// [inFlightIds] are connections with a step-down/revoke in progress (used to
/// disable per-row actions and show a spinner). [lastOutcome] is a one-shot
/// success marker consumed by a `BlocListener` to show a toast; it is cleared on
/// the next emit so it never re-fires.
class ConnectionsLoaded extends ConnectionsState {
  const ConnectionsLoaded({
    required this.items,
    this.inFlightIds = const {},
    this.lastOutcome,
    this.webMcpFoodAutoLogEnabled = false,
    this.webMcpFoodAutoLogBusy = false,
    this.webMcpSettingError,
  });

  final List<Connection> items;
  final Set<String> inFlightIds;
  final ConnectionActionOutcome? lastOutcome;
  final bool webMcpFoodAutoLogEnabled;
  final bool webMcpFoodAutoLogBusy;
  final String? webMcpSettingError;

  ConnectionsLoaded copyWith({
    List<Connection>? items,
    Set<String>? inFlightIds,
    ConnectionActionOutcome? lastOutcome,
    bool clearOutcome = false,
    bool? webMcpFoodAutoLogEnabled,
    bool? webMcpFoodAutoLogBusy,
    String? webMcpSettingError,
    bool clearWebMcpSettingError = false,
  }) {
    return ConnectionsLoaded(
      items: items ?? this.items,
      inFlightIds: inFlightIds ?? this.inFlightIds,
      lastOutcome: clearOutcome ? null : (lastOutcome ?? this.lastOutcome),
      webMcpFoodAutoLogEnabled:
          webMcpFoodAutoLogEnabled ?? this.webMcpFoodAutoLogEnabled,
      webMcpFoodAutoLogBusy:
          webMcpFoodAutoLogBusy ?? this.webMcpFoodAutoLogBusy,
      webMcpSettingError: clearWebMcpSettingError
          ? null
          : (webMcpSettingError ?? this.webMcpSettingError),
    );
  }

  @override
  List<Object?> get props => [
    items,
    inFlightIds,
    lastOutcome,
    webMcpFoodAutoLogEnabled,
    webMcpFoodAutoLogBusy,
    webMcpSettingError,
  ];
}

class ConnectionsFailure extends ConnectionsState {
  const ConnectionsFailure({required this.code, required this.message});

  final String code;
  final String message;

  @override
  List<Object?> get props => [code, message];
}
