import '../../app/navigation/app_routes.dart';

/// Tracks the most recent route name for robust post-login redirects.
class CurrentRouteService {
  String _lastRoute = '/';

  /// Update the current route; callers can pass full names including query.
  void update(String name) {
    // Normalize by stripping query parameters to match allow-list entries.
    final sanitized = name.split('?').first;
    _lastRoute = sanitized.isNotEmpty ? sanitized : '/';
  }

  /// Returns a safe, allowed route for after-login navigation.
  String getAllowedRoute() {
    if (AppRoutes.validAfterLoginRoutes.contains(_lastRoute)) {
      return _lastRoute;
    }
    return AppRoutes.defaultAfterLoginRoute;
  }
}
