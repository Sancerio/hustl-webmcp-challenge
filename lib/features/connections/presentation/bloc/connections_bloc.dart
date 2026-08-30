import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/webmcp/web_mcp_access_gate.dart';
import '../../../../core/webmcp/web_mcp_config.dart';
import '../../data/datasources/connections_api.dart';
import '../../domain/models/connection.dart';
import '../../domain/repositories/connections_repository.dart';
import 'connections_event.dart';
import 'connections_state.dart';

/// Drives the connected-apps screen. Modeled on `ProposalsBloc` (flutter_bloc +
/// Equatable): a load/refresh pair plus two mutating actions that flip a
/// per-row in-flight flag, mutate locally on success, and surface a one-shot
/// outcome for the screen's toast.
///
/// Step-down removes the connection's `propose:` scopes (the row stays, now
/// read-only). Revoke removes the connection entirely AND retracts its pending
/// proposals server-side, so the row drops from the list.
class ConnectionsBloc extends Bloc<ConnectionsEvent, ConnectionsState> {
  ConnectionsBloc({
    required ConnectionsRepository repository,
    this.webMcpEnabled = kWebMcpEnabled,
    WebMcpAccessGate? accessGate,
  }) : _repository = repository,
       _accessGate = accessGate,
       super(const ConnectionsInitial()) {
    on<LoadConnections>(_onLoad);
    on<RefreshConnections>(_onRefresh);
    on<StepDownConnection>(_onStepDown);
    on<StepUpConnection>(_onStepUp);
    on<RevokeConnection>(_onRevoke);
    on<SetAutoApprove>(_onSetAutoApprove);
    on<SetWebMcpFoodAutoLog>(_onSetWebMcpFoodAutoLog);
    on<_WebMcpAccessChanged>(_onWebMcpAccessChanged);

    if (webMcpEnabled && accessGate != null) {
      _accessGateListener = () {
        if (isClosed) return;
        add(
          _WebMcpAccessChanged(
            ready: accessGate.ready.value,
            generation: accessGate.generation,
          ),
        );
      };
      accessGate.ready.addListener(_accessGateListener!);
    }
  }

  final ConnectionsRepository _repository;
  final WebMcpAccessGate? _accessGate;
  final bool webMcpEnabled;
  VoidCallback? _accessGateListener;

  Future<void> _onLoad(
    LoadConnections event,
    Emitter<ConnectionsState> emit,
  ) async {
    emit(const ConnectionsLoading());
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshConnections event,
    Emitter<ConnectionsState> emit,
  ) async {
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<ConnectionsState> emit) async {
    final generation = _captureAccessGeneration();
    if (!_isAccessCurrent(generation)) return;
    try {
      final items = await _repository.list();
      if (emit.isDone || !_isAccessCurrent(generation)) return;
      final webMcpFoodAutoLogEnabled = webMcpEnabled
          ? await _repository.getWebMcpFoodAutoLog()
          : false;
      if (emit.isDone || !_isAccessCurrent(generation)) return;
      emit(
        ConnectionsLoaded(
          items: items,
          webMcpFoodAutoLogEnabled: webMcpFoodAutoLogEnabled,
        ),
      );
    } on ConnectionsApiException catch (e) {
      if (emit.isDone || !_isAccessCurrent(generation)) return;
      emit(ConnectionsFailure(code: e.code, message: e.message));
    } catch (e) {
      if (emit.isDone || !_isAccessCurrent(generation)) return;
      emit(ConnectionsFailure(code: 'unknown', message: e.toString()));
    }
  }

  Future<void> _onWebMcpAccessChanged(
    _WebMcpAccessChanged event,
    Emitter<ConnectionsState> emit,
  ) async {
    if (!event.ready || !_isAccessCurrent(event.generation)) {
      emit(const ConnectionsLoading());
      return;
    }
    await _fetch(emit);
  }

  Future<void> _onSetWebMcpFoodAutoLog(
    SetWebMcpFoodAutoLog event,
    Emitter<ConnectionsState> emit,
  ) async {
    final current = state;
    if (!webMcpEnabled || current is! ConnectionsLoaded) return;
    final generation = _captureAccessGeneration();
    if (!_isAccessCurrent(generation)) return;
    // Pessimistic: display the new choice only after the authoritative write.
    emit(
      current.copyWith(
        webMcpFoodAutoLogBusy: true,
        clearWebMcpSettingError: true,
      ),
    );
    try {
      final enabled = await _repository.setWebMcpFoodAutoLog(event.enabled);
      if (emit.isDone || !_isAccessCurrent(generation)) return;
      emit(
        current.copyWith(
          webMcpFoodAutoLogEnabled: enabled,
          webMcpFoodAutoLogBusy: false,
          clearWebMcpSettingError: true,
        ),
      );
    } on ConnectionsApiException catch (e) {
      if (emit.isDone || !_isAccessCurrent(generation)) return;
      emit(
        current.copyWith(
          webMcpFoodAutoLogBusy: false,
          webMcpSettingError: e.message,
        ),
      );
    } catch (_) {
      if (emit.isDone || !_isAccessCurrent(generation)) return;
      emit(
        current.copyWith(
          webMcpFoodAutoLogBusy: false,
          webMcpSettingError: 'We couldn\'t update Web auto-log',
        ),
      );
    }
  }

  Future<void> _onStepDown(
    StepDownConnection event,
    Emitter<ConnectionsState> emit,
  ) async {
    final current = state;
    if (current is! ConnectionsLoaded) return;
    final generation = _captureAccessGeneration();
    if (!_isAccessCurrent(generation)) return;
    final target = _find(current.items, event.clientId);
    if (target == null) return;
    emit(
      current.copyWith(
        inFlightIds: {...current.inFlightIds, event.clientId},
        clearOutcome: true,
      ),
    );
    try {
      await _repository.stepDown(event.clientId);
      if (emit.isDone || !_isAccessCurrent(generation)) return;
      // Drop the `propose:` scopes locally so the row reads as read-only without
      // a round-trip; the next refresh reconciles with the server.
      final updated = [
        for (final c in _items)
          if (c.clientId == event.clientId)
            c.copyWith(scope: _readOnlyScope(c.scope))
          else
            c,
      ];
      emit(
        current.copyWith(
          items: updated,
          inFlightIds: const {},
          lastOutcome: ConnectionActionOutcome(
            kind: ConnectionActionKind.steppedDown,
            clientName: target.clientName,
          ),
        ),
      );
    } on ConnectionsApiException catch (e) {
      if (emit.isDone || !_isAccessCurrent(generation)) return;
      _clearInFlight(emit, event.clientId);
      emit(ConnectionsFailure(code: e.code, message: e.message));
    } catch (e) {
      if (emit.isDone || !_isAccessCurrent(generation)) return;
      _clearInFlight(emit, event.clientId);
      emit(ConnectionsFailure(code: 'unknown', message: e.toString()));
    }
  }

  Future<void> _onStepUp(
    StepUpConnection event,
    Emitter<ConnectionsState> emit,
  ) async {
    final current = state;
    if (current is! ConnectionsLoaded) return;
    final generation = _captureAccessGeneration();
    if (!_isAccessCurrent(generation)) return;
    final target = _find(current.items, event.clientId);
    if (target == null) return;
    emit(
      current.copyWith(
        inFlightIds: {...current.inFlightIds, event.clientId},
        clearOutcome: true,
      ),
    );
    try {
      await _repository.stepUp(event.clientId);
      if (emit.isDone || !_isAccessCurrent(generation)) return;
      // Add the propose scope locally so the row flips to "Can propose" without a
      // round-trip; the next refresh reconciles with the server.
      final updated = [
        for (final c in _items)
          if (c.clientId == event.clientId)
            c.copyWith(scope: _withPropose(c.scope))
          else
            c,
      ];
      emit(
        current.copyWith(
          items: updated,
          inFlightIds: const {},
          lastOutcome: ConnectionActionOutcome(
            kind: ConnectionActionKind.steppedUp,
            clientName: target.clientName,
          ),
        ),
      );
    } on ConnectionsApiException catch (e) {
      if (emit.isDone || !_isAccessCurrent(generation)) return;
      _clearInFlight(emit, event.clientId);
      emit(ConnectionsFailure(code: e.code, message: e.message));
    } catch (e) {
      if (emit.isDone || !_isAccessCurrent(generation)) return;
      _clearInFlight(emit, event.clientId);
      emit(ConnectionsFailure(code: 'unknown', message: e.toString()));
    }
  }

  Future<void> _onRevoke(
    RevokeConnection event,
    Emitter<ConnectionsState> emit,
  ) async {
    final current = state;
    if (current is! ConnectionsLoaded) return;
    final generation = _captureAccessGeneration();
    if (!_isAccessCurrent(generation)) return;
    final target = _find(current.items, event.clientId);
    if (target == null) return;
    emit(
      current.copyWith(
        inFlightIds: {...current.inFlightIds, event.clientId},
        clearOutcome: true,
      ),
    );
    try {
      await _repository.revoke(event.clientId);
      if (emit.isDone || !_isAccessCurrent(generation)) return;
      final remaining = _items
          .where((c) => c.clientId != event.clientId)
          .toList();
      emit(
        current.copyWith(
          items: remaining,
          inFlightIds: const {},
          lastOutcome: ConnectionActionOutcome(
            kind: ConnectionActionKind.revoked,
            clientName: target.clientName,
          ),
        ),
      );
    } on ConnectionsApiException catch (e) {
      if (emit.isDone || !_isAccessCurrent(generation)) return;
      _clearInFlight(emit, event.clientId);
      emit(ConnectionsFailure(code: e.code, message: e.message));
    } catch (e) {
      if (emit.isDone || !_isAccessCurrent(generation)) return;
      _clearInFlight(emit, event.clientId);
      emit(ConnectionsFailure(code: 'unknown', message: e.toString()));
    }
  }

  Future<void> _onSetAutoApprove(
    SetAutoApprove event,
    Emitter<ConnectionsState> emit,
  ) async {
    final current = state;
    if (current is! ConnectionsLoaded) return;
    final generation = _captureAccessGeneration();
    if (!_isAccessCurrent(generation)) return;
    if (_find(current.items, event.clientId) == null) return;

    // Optimistically flip the matching flag so the Switch responds instantly.
    final optimistic = [
      for (final c in current.items)
        if (c.clientId == event.clientId)
          (event.kind == 'food_log'
              ? c.copyWith(autoApproveFoodLog: event.enabled)
              : c.copyWith(autoApproveWorkoutLog: event.enabled))
        else
          c,
    ];
    emit(current.copyWith(items: optimistic, clearOutcome: true));

    try {
      await _repository.setAutoApprove(
        clientId: event.clientId,
        kind: event.kind,
        enabled: event.enabled,
      );
    } on ConnectionsApiException catch (e) {
      if (emit.isDone || !_isAccessCurrent(generation)) return;
      // Mirror the other mutations: surface the failure (the screen offers a
      // retry, whose reload reconciles the toggle with the server's true state).
      emit(ConnectionsFailure(code: e.code, message: e.message));
    } catch (e) {
      if (emit.isDone || !_isAccessCurrent(generation)) return;
      emit(ConnectionsFailure(code: 'unknown', message: e.toString()));
    }
  }

  List<Connection> get _items {
    final s = state;
    return s is ConnectionsLoaded ? s.items : const [];
  }

  Connection? _find(List<Connection> items, String clientId) {
    final matches = items.where((c) => c.clientId == clientId);
    return matches.isEmpty ? null : matches.first;
  }

  String _readOnlyScope(String scope) => scope
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty && !s.startsWith('propose:'))
      .join(' ');

  String _withPropose(String scope) {
    final parts = scope
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toSet();
    // Backend step-up grants READ + ALL write scopes, so mirror the full set here
    // — otherwise the food/workout auto-log toggles (gated on those scopes) stay
    // hidden until the next connection refresh. Keep in sync with backend
    // WRITE_SCOPES (lib/mcp/scopes.ts).
    parts.addAll(const [
      'propose:templates',
      'propose:nutrition_targets',
      'propose:food_log',
      'propose:workout_log',
    ]);
    return parts.join(' ');
  }

  void _clearInFlight(Emitter<ConnectionsState> emit, String id) {
    final current = state;
    if (current is ConnectionsLoaded) {
      emit(
        current.copyWith(
          inFlightIds: current.inFlightIds.where((x) => x != id).toSet(),
        ),
      );
    }
  }

  int? _captureAccessGeneration() {
    if (!webMcpEnabled || _accessGate == null) return null;
    return _accessGate.generation;
  }

  bool _isAccessCurrent(int? generation) {
    if (!webMcpEnabled || _accessGate == null) return true;
    return generation != null && _accessGate.isReadyFor(generation);
  }

  @override
  Future<void> close() {
    final listener = _accessGateListener;
    if (listener != null) _accessGate?.ready.removeListener(listener);
    return super.close();
  }
}

class _WebMcpAccessChanged extends ConnectionsEvent {
  const _WebMcpAccessChanged({required this.ready, required this.generation});

  final bool ready;
  final int generation;

  @override
  List<Object?> get props => [ready, generation];
}
