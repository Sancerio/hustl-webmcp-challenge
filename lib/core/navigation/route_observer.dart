import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'current_route_service.dart';
import 'last_training_route_service.dart';

/// Root-navigator page name reserved for the stateful app shell.
const appShellRouteName = 'app-shell';

/// Custom RouteObserver that tracks the current route for post-auth redirects.
class HustlRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  final Map<Route<dynamic>, String?> _predecessorNames = {};

  /// Name of the root-navigator route immediately below [route].
  ///
  /// The stateful app shell's root page carries [appShellRouteName]. The
  /// workout player checks that exact marker so named and unnamed root
  /// overlays both receive the safe fallback destination.
  String? predecessorNameOf(Route<dynamic> route) => _predecessorNames[route];

  void _update(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null) return;
    if (GetIt.I.isRegistered<CurrentRouteService>()) {
      GetIt.I<CurrentRouteService>().update(name);
    }
    if (GetIt.I.isRegistered<LastTrainingRouteService>()) {
      GetIt.I<LastTrainingRouteService>().update(name);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _predecessorNames[route] = previousRoute?.settings.name;
    _update(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    final predecessorName = oldRoute == null
        ? null
        : _predecessorNames.remove(oldRoute);
    if (newRoute != null) _predecessorNames[newRoute] = predecessorName;
    _update(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _predecessorNames.remove(route);
    _update(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _predecessorNames.remove(route);
    _update(previousRoute);
  }
}

/// Global route observer instance.
final HustlRouteObserver routeObserver = HustlRouteObserver();
