import '../../../../app/navigation/app_routes.dart';

/// Stores the route to navigate back to after authentication completes.
class AuthRedirectService {
  String? _afterLoginRoute;

  void setAfterLoginRoute(String route) {
    _afterLoginRoute = route;
  }

  String consumeAfterLoginRoute() {
    final route = _afterLoginRoute;
    _afterLoginRoute = null;
    if (route != null && AppRoutes.validAfterLoginRoutes.contains(route)) {
      return route;
    }
    return AppRoutes.defaultAfterLoginRoute;
  }
}
