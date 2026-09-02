import 'dart:async';
import 'dart:convert';

import '../model/evaluator_state.dart';
import 'tool.dart';
import 'tool_catalog.dart';

class WebMcpController {
  WebMcpController({
    required EvaluatorState state,
    required ToolHost host,
    required CurrentRoute currentRoute,
    required Navigate navigate,
  }) : _state = state,
       _host = host,
       _currentRoute = currentRoute {
    _catalog = ToolCatalog(
      state: state,
      currentRoute: currentRoute,
      currentGeneration: () => _generation,
      navigate: navigate,
    );
    _state.addListener(_stateChanged);
  }

  final EvaluatorState _state;
  final ToolHost _host;
  final CurrentRoute _currentRoute;
  late final ToolCatalog _catalog;
  final List<ToolRegistration> _registrations = [];
  List<String> _registrationDescriptors = const [];
  String? _registrationScope;
  _ToolHandlerRouter? _handlerRouter;
  Future<void> _refreshQueue = Future<void>.value();
  int _generation = 0;
  bool _stateRefreshScheduled = false;
  bool _disposed = false;

  int get generation => _generation;

  List<ToolDefinition> definitionsForTesting(String route) =>
      _catalog.forRoute(route, _generation);

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    final generation = ++_generation;
    final route = _currentRoute();
    final previous = _refreshQueue;
    final next = () async {
      try {
        await previous;
      } catch (_) {
        // A failed earlier host refresh must not block a newer route snapshot.
      }
      if (_disposed || generation != _generation || _currentRoute() != route) {
        return;
      }
      await _refreshGeneration(route, generation);
    }();
    _refreshQueue = next;
    return next;
  }

  Future<void> _refreshGeneration(String route, int generation) async {
    final definitions = _catalog.forRoute(route, generation);
    final descriptors = definitions
        .map((definition) => jsonEncode(definition.registrationJson()))
        .toList(growable: false);
    final scope = _catalog.registrationScopeForRoute(route);

    if (_canRebind(scope, descriptors)) {
      _handlerRouter!.rebind(definitions);
      return;
    }

    _disposeRegistrations();
    if (!_host.supported) return;

    final router = _ToolHandlerRouter(definitions);
    final provisional = <ToolRegistration>[];
    for (var index = 0; index < definitions.length; index++) {
      ToolRegistration? registration;
      try {
        registration = await _host.register(
          router.registrationDefinition(index),
        );
      } catch (_) {
        _disposeProvisional(router, provisional);
        return;
      }
      if (_disposed || generation != _generation || _currentRoute() != route) {
        if (registration != null) provisional.add(registration);
        _disposeProvisional(router, provisional);
        return;
      }
      if (registration == null) {
        _disposeProvisional(router, provisional);
        return;
      }
      provisional.add(registration);
    }

    _registrations.addAll(provisional);
    _registrationDescriptors = descriptors;
    _registrationScope = scope;
    _handlerRouter = router;
    router.activate();
  }

  bool _canRebind(String scope, List<String> descriptors) {
    if (_handlerRouter == null ||
        _registrationScope != scope ||
        _registrationDescriptors.length != descriptors.length) {
      return false;
    }
    for (var index = 0; index < descriptors.length; index++) {
      if (_registrationDescriptors[index] != descriptors[index]) return false;
    }
    return true;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _state.removeListener(_stateChanged);
    _generation += 1;
    _disposeRegistrations();
  }

  void _stateChanged() {
    if (_stateRefreshScheduled || _disposed) return;
    _stateRefreshScheduled = true;
    Timer.run(() {
      _stateRefreshScheduled = false;
      if (!_disposed) unawaited(refresh());
    });
  }

  void _disposeRegistrations() {
    _handlerRouter?.deactivate();
    _handlerRouter = null;
    for (final registration in _registrations) {
      try {
        registration.dispose();
      } catch (_) {
        // Teardown is best-effort; handler deactivation is the safety boundary.
      }
    }
    _registrations.clear();
    _registrationDescriptors = const [];
    _registrationScope = null;
  }

  void _disposeProvisional(
    _ToolHandlerRouter router,
    List<ToolRegistration> registrations,
  ) {
    router.deactivate();
    for (final registration in registrations) {
      try {
        registration.dispose();
      } catch (_) {
        // A partial catalog is never activated even when host cleanup fails.
      }
    }
  }
}

class _ToolHandlerRouter {
  _ToolHandlerRouter(List<ToolDefinition> definitions)
    : _definitions = List<ToolDefinition>.unmodifiable(definitions);

  List<ToolDefinition> _definitions;
  bool _active = false;

  ToolDefinition registrationDefinition(int index) => _definitions[index]
      .withHandler((arguments) => _dispatch(index, arguments));

  void activate() => _active = true;

  void deactivate() => _active = false;

  void rebind(List<ToolDefinition> definitions) {
    _definitions = List<ToolDefinition>.unmodifiable(definitions);
  }

  Future<Map<String, Object?>> _dispatch(
    int index,
    Map<String, Object?> arguments,
  ) async {
    final definitions = _definitions;
    if (!_active || index >= definitions.length) {
      return const {'status': 'unavailable', 'code': 'stale_route'};
    }
    // Route and generation postconditions belong to the catalog handler.
    // Navigation handlers intentionally opt out after changing route, because
    // that change disposes this router before their truthful result returns.
    return definitions[index].handler(arguments);
  }
}
