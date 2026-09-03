/// Tracks the most recently visited *Train tab* route so the shell can return
/// users to where they left off within the Train branch.
///
/// With the `StatefulShellRoute` the Train branch preserves its own navigation
/// stack automatically; this service remains as the source of truth for the
/// last train sub-route used by post-auth redirects and any future deep-restore.
class LastTrainingRouteService {
  static const Set<String> trainingTabRoutes = {'/'};

  String _lastTrainingTabRoute = '/';

  void update(String routeName) {
    final sanitized = routeName.split('?').first;
    if (trainingTabRoutes.contains(sanitized)) {
      _lastTrainingTabRoute = sanitized;
    }
  }

  String get lastTrainingTabRoute => _lastTrainingTabRoute;
}
