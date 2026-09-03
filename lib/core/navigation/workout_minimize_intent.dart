import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

enum WorkoutMinimizeDirection { push, pop }

/// Route-extra marker for a workout opened from the already-mounted
/// MiniPlayer. Unlike the short-lived intent above, this travels with the route
/// so the expansion cannot expire while the destination builds its first frame.
const workoutExpandFromMiniPlayerExtraKey = 'expandFromMiniPlayer';

/// Route-extra marker used to restore the surface that opened a canonical
/// active-workout route after minimize, cancel, or native back.
const workoutReturnLocationExtraKey = 'workoutReturnLocation';

Map<String, dynamic> workoutRouteExtra(
  BuildContext context, [
  Map<String, dynamic>? extra,
]) {
  final router = GoRouter.of(context);
  final uri = _workoutOriginUri(context, router);
  final result = <String, dynamic>{...?extra};
  if (uri.path != '/workout' && uri.path != '/workout_session') {
    result[workoutReturnLocationExtraKey] = uri.toString();
  }
  return result;
}

Uri _workoutOriginUri(BuildContext context, GoRouter router) {
  try {
    // Use the route associated with the caller. The browser-facing route
    // information can intentionally remain on the underlying page while a
    // destination opened with push owns the visible screen.
    return GoRouterState.of(context).uri;
  } on GoError {
    // Root navigator contexts used by notification and watch handoffs are not
    // necessarily below a GoRoute builder. The delegate still knows the
    // internal top match, including imperative (push) routes.
    return router.routerDelegate.state.uri;
  }
}

String? workoutReturnLocationFromExtra(Map<String, dynamic>? extra) {
  final candidate = extra?[workoutReturnLocationExtraKey];
  if (candidate is! String ||
      !candidate.startsWith('/') ||
      candidate.startsWith('//')) {
    return null;
  }
  final uri = Uri.tryParse(candidate);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.path == '/workout' ||
      uri.path == '/workout_session') {
    return null;
  }
  return candidate;
}

/// One-frame navigation intent used to reserve the persistent-player motion
/// for banner Resume and the workout's explicit minimize interaction.
abstract final class WorkoutMinimizeIntent {
  static const Duration _validity = Duration(milliseconds: 800);

  static DateTime? _armedAt;
  static WorkoutMinimizeDirection? _direction;

  static void arm(WorkoutMinimizeDirection direction) {
    _armedAt = DateTime.now();
    _direction = direction;
  }

  static bool consume(WorkoutMinimizeDirection direction) {
    final armedAt = _armedAt;
    final armedDirection = _direction;
    _armedAt = null;
    _direction = null;
    return armedAt != null &&
        armedDirection == direction &&
        DateTime.now().difference(armedAt) < _validity;
  }
}
