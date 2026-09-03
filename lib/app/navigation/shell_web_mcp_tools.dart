import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/analytics_service.dart';
import '../../core/webmcp/hustl_web_mcp_coordinator.dart';
import '../../core/webmcp/web_mcp_config.dart';
import '../../core/webmcp/web_mcp_host.dart';
import '../../core/webmcp/web_mcp_models.dart';

/// Resolves the top routed location while retaining a usable path for router
/// error states, whose match list is empty.
String webMcpRouteForRouter(GoRouter router) {
  final configuration = router.routerDelegate.currentConfiguration;
  if (configuration.matches.isEmpty) return configuration.uri.path;
  return configuration.last.matchedLocation;
}

/// Owns browser tool registrations for exactly the lifetime of the routed app.
/// This widget is visually transparent and inert in default builds.
class ShellWebMcpTools extends StatefulWidget {
  const ShellWebMcpTools({
    super.key,
    required this.child,
    this.enabled = kWebMcpEnabled,
    this.host,
    this.coordinator,
    this.navigate,
    this.currentRoute,
    @visibleForTesting this.tools,
    this.navigationChanges,
  });

  final Widget child;
  final bool enabled;
  final WebMcpHost? host;
  final HustlWebMcpCoordinator? coordinator;
  final WebMcpNavigate? navigate;
  final WebMcpCurrentRoute? currentRoute;
  final List<WebMcpToolDefinition>? tools;
  final Listenable? navigationChanges;

  @override
  State<ShellWebMcpTools> createState() => _ShellWebMcpToolsState();
}

class _ShellWebMcpToolsState extends State<ShellWebMcpTools> {
  final List<WebMcpRegistration> _registrations = [];
  List<String> _registrationDescriptors = const [];
  String? _stableRegistrationScope;
  _ShellWebMcpHandlerRouter? _handlerRouter;
  List<WebMcpRegistration>? _pendingRegistrations;
  _ShellWebMcpHandlerRouter? _pendingHandlerRouter;
  bool _registrationStarted = false;
  Listenable? _navigationChanges;
  Timer? _navigationRefreshTimer;
  Future<void> _registrationQueue = Future.value();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_registrationStarted || !widget.enabled) return;
    _registrationStarted = true;
    _navigationChanges =
        widget.navigationChanges ??
        (widget.tools == null ? GoRouter.of(context).routerDelegate : null);
    _navigationChanges?.addListener(_scheduleNavigationRefresh);
    _queueRegistration();
  }

  @override
  void didUpdateWidget(covariant ShellWebMcpTools oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled == widget.enabled) return;
    if (widget.enabled) {
      if (!_registrationStarted) {
        _registrationStarted = true;
        _navigationChanges =
            widget.navigationChanges ??
            (widget.tools == null ? GoRouter.of(context).routerDelegate : null);
        _navigationChanges?.addListener(_scheduleNavigationRefresh);
      }
      _queueRegistration(replace: true);
    } else {
      _navigationRefreshTimer?.cancel();
      _navigationRefreshTimer = null;
      _queueTeardown();
    }
  }

  void _scheduleNavigationRefresh() {
    if (!widget.enabled) return;
    _navigationRefreshTimer?.cancel();
    _navigationRefreshTimer = Timer(const Duration(milliseconds: 250), () {
      _navigationRefreshTimer = null;
      if (mounted && widget.enabled) {
        _queueRegistration(replace: true);
      }
    });
  }

  void _queueTeardown() {
    _registrationQueue = _registrationQueue.catchError((_) {}).then((_) {
      _disposeRegistrations();
    });
    unawaited(_registrationQueue);
  }

  void _queueRegistration({bool replace = false}) {
    _registrationQueue = _registrationQueue
        .catchError((_) {})
        .then((_) => _registerTools(replace: replace));
    unawaited(_registrationQueue);
  }

  Future<void> _registerTools({required bool replace}) async {
    if (!mounted || !widget.enabled) return;
    _ResolvedWebMcpCatalog? catalog;
    try {
      catalog = _resolveCatalog();
    } catch (_) {
      if (replace) _disposeRegistrations();
      _logAvailability('dependencies_missing');
      return;
    }
    if (replace && catalog != null && _canRebind(catalog)) {
      _handlerRouter!.rebind(catalog.definitions);
      return;
    }
    if (replace) {
      _disposeRegistrations();
      // AbortController-based unregistration settles in the browser on a
      // microtask boundary. Leave a small gap before reusing the same names.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted || !widget.enabled) return;
    }

    if (catalog == null) {
      _logAvailability('dependencies_missing');
      return;
    }

    final host = widget.host ?? createWebMcpHost();
    if (!host.isSupported) {
      _logAvailability('api_missing');
      return;
    }

    final handlerRouter = _ShellWebMcpHandlerRouter(catalog.definitions);
    _pendingHandlerRouter = handlerRouter;
    _pendingRegistrations = [];
    for (var index = 0; index < catalog.definitions.length; index += 1) {
      final definition = catalog.definitions[index];
      WebMcpRegistration? registration;
      try {
        registration = await host.registerTool(
          handlerRouter.registrationDefinition(index),
        );
      } catch (_) {
        registration = null;
      }
      if (!mounted || !widget.enabled) {
        registration?.dispose();
        _disposePendingRegistrations();
        return;
      }
      if (registration == null) {
        _logRegistration(definition.name, 'failed');
        _disposePendingRegistrations();
        return;
      }
      final pendingRegistrations = _pendingRegistrations;
      if (pendingRegistrations == null) {
        registration.dispose();
        return;
      }
      pendingRegistrations.add(registration);
      _logRegistration(definition.name, 'registered');
    }
    final pendingRegistrations = _pendingRegistrations;
    if (pendingRegistrations == null) return;
    _registrations.addAll(pendingRegistrations);
    _pendingRegistrations = null;
    _pendingHandlerRouter = null;
    _registrationDescriptors = catalog.descriptors;
    _stableRegistrationScope = catalog.stableRegistrationScope;
    _handlerRouter = handlerRouter;
    handlerRouter.activate();
  }

  void _disposeRegistrations() {
    _disposePendingRegistrations();
    _handlerRouter?.deactivate();
    _handlerRouter = null;
    for (final registration in _registrations.reversed) {
      registration.dispose();
    }
    _registrations.clear();
    _registrationDescriptors = const [];
    _stableRegistrationScope = null;
  }

  void _disposePendingRegistrations() {
    _pendingHandlerRouter?.deactivate();
    _pendingHandlerRouter = null;
    final registrations = _pendingRegistrations;
    _pendingRegistrations = null;
    if (registrations == null) return;
    for (final registration in registrations.reversed) {
      registration.dispose();
    }
  }

  bool _canRebind(_ResolvedWebMcpCatalog catalog) {
    final scope = catalog.stableRegistrationScope;
    if (scope == null || scope != _stableRegistrationScope) return false;
    if (_handlerRouter == null ||
        catalog.descriptors.length != _registrationDescriptors.length) {
      return false;
    }
    for (var index = 0; index < catalog.descriptors.length; index += 1) {
      if (catalog.descriptors[index] != _registrationDescriptors[index]) {
        return false;
      }
    }
    return true;
  }

  _ResolvedWebMcpCatalog? _resolveCatalog() {
    if (widget.tools case final tools?) {
      return _ResolvedWebMcpCatalog(tools);
    }
    final getIt = GetIt.instance;
    final coordinator =
        widget.coordinator ??
        (getIt.isRegistered<HustlWebMcpCoordinator>()
            ? getIt<HustlWebMcpCoordinator>()
            : null);
    if (coordinator == null) return null;
    final router = GoRouter.maybeOf(context);
    final currentRoute =
        widget.currentRoute ??
        (router == null ? null : () => webMcpRouteForRouter(router));
    final navigate = widget.navigate ?? router?.go;
    if (currentRoute == null || navigate == null) return null;
    final route = currentRoute();
    return _ResolvedWebMcpCatalog(
      coordinator.toolsForRoute(
        route: route,
        currentRoute: currentRoute,
        navigate: navigate,
      ),
      stableRegistrationScope: coordinator.stableRegistrationScopeForRoute(
        route,
      ),
    );
  }

  void _logAvailability(String reason) {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<AnalyticsService>()) return;
    getIt<AnalyticsService>().logEvent(
      'webmcp_availability',
      props: {'status': 'unavailable', 'reason': reason},
    );
  }

  void _logRegistration(String tool, String status) {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<AnalyticsService>()) return;
    getIt<AnalyticsService>().logEvent(
      'webmcp_registration',
      props: {'tool': tool, 'status': status},
    );
  }

  @override
  void dispose() {
    _navigationRefreshTimer?.cancel();
    _navigationChanges?.removeListener(_scheduleNavigationRefresh);
    _disposeRegistrations();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ResolvedWebMcpCatalog {
  _ResolvedWebMcpCatalog(this.definitions, {this.stableRegistrationScope})
    : descriptors = List.unmodifiable(
        definitions.map((tool) => jsonEncode(tool.toRegistrationJson())),
      );

  final List<WebMcpToolDefinition> definitions;
  final List<String> descriptors;
  final String? stableRegistrationScope;
}

class _ShellWebMcpHandlerRouter {
  _ShellWebMcpHandlerRouter(List<WebMcpToolDefinition> definitions)
    : _snapshot = const _ShellWebMcpHandlerSnapshot.inactive(),
      _registrationDefinitions = List.unmodifiable(definitions);

  final List<WebMcpToolDefinition> _registrationDefinitions;
  _ShellWebMcpHandlerSnapshot _snapshot;

  WebMcpToolDefinition registrationDefinition(int index) {
    final definition = _registrationDefinitions[index];
    return WebMcpToolDefinition(
      name: definition.name,
      title: definition.title,
      description: definition.description,
      inputSchema: definition.inputSchema,
      handler: (arguments) => _invoke(index, arguments),
      readOnlyHint: definition.readOnlyHint,
      destructiveHint: definition.destructiveHint,
      idempotentHint: definition.idempotentHint,
      openWorldHint: definition.openWorldHint,
      untrustedContentHint: definition.untrustedContentHint,
    );
  }

  void activate() {
    _snapshot = _ShellWebMcpHandlerSnapshot.active(_registrationDefinitions);
  }

  void rebind(List<WebMcpToolDefinition> definitions) {
    _snapshot = _ShellWebMcpHandlerSnapshot.active(definitions);
  }

  void deactivate() {
    _snapshot = const _ShellWebMcpHandlerSnapshot.inactive();
  }

  Future<Map<String, Object?>> _invoke(
    int index,
    Map<String, Object?> arguments,
  ) {
    final snapshot = _snapshot;
    if (!snapshot.isActive || index >= snapshot.handlers.length) {
      return Future.value(const {
        'status': 'unavailable',
        'code': 'stale_route',
      });
    }
    final handler = snapshot.handlers[index];
    return handler(arguments);
  }
}

class _ShellWebMcpHandlerSnapshot {
  _ShellWebMcpHandlerSnapshot.active(List<WebMcpToolDefinition> definitions)
    : isActive = true,
      handlers = List.unmodifiable(definitions.map((tool) => tool.handler));

  const _ShellWebMcpHandlerSnapshot.inactive()
    : isActive = false,
      handlers = const [];

  final bool isActive;
  final List<WebMcpToolHandler> handlers;
}
