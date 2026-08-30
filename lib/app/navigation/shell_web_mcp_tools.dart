import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/analytics_service.dart';
import '../../core/webmcp/hustl_web_mcp_coordinator.dart';
import '../../core/webmcp/web_mcp_config.dart';
import '../../core/webmcp/web_mcp_host.dart';
import '../../core/webmcp/web_mcp_models.dart';

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
    if (replace) {
      _disposeRegistrations();
      // AbortController-based unregistration settles in the browser on a
      // microtask boundary. Leave a small gap before reusing the same names.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted || !widget.enabled) return;
    }

    final host = widget.host ?? createWebMcpHost();
    if (!host.isSupported) {
      _logAvailability('api_missing');
      return;
    }

    final definitions = widget.tools ?? _resolveTools();
    if (definitions == null) {
      _logAvailability('dependencies_missing');
      return;
    }

    for (final definition in definitions) {
      if (!mounted || !widget.enabled) return;
      final registration = await host.registerTool(definition);
      if (!mounted || !widget.enabled) {
        registration?.dispose();
        return;
      }
      if (registration == null) {
        _logRegistration(definition.name, 'failed');
        continue;
      }
      _registrations.add(registration);
      _logRegistration(definition.name, 'registered');
    }
  }

  void _disposeRegistrations() {
    for (final registration in _registrations.reversed) {
      registration.dispose();
    }
    _registrations.clear();
  }

  List<WebMcpToolDefinition>? _resolveTools() {
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
        (router == null
            ? null
            : () => router
                  .routerDelegate
                  .currentConfiguration
                  .last
                  .matchedLocation);
    final navigate = widget.navigate ?? router?.go;
    if (currentRoute == null || navigate == null) return null;
    return coordinator.toolsForRoute(
      route: currentRoute(),
      currentRoute: currentRoute,
      navigate: navigate,
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
