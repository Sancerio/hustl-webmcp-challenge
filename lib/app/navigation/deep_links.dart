import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/hustl_inline_skeleton.dart';
import '../../core/widgets/hustl_menu_button.dart';
import '../../features/auth/presentation/screens/account_screen.dart';
import '../../features/exercise_library/domain/models/exercise.dart';
import '../../features/exercise_library/domain/repositories/exercise_repository.dart';
import '../../features/exercise_library/presentation/screens/exercise_detail_screen.dart';
import '../../features/workout_logging/domain/models/workout_session.dart';
import '../../features/workout_logging/domain/repositories/workout_repository.dart';
import '../../features/workout_logging/domain/services/rest_timer_service.dart';

/// Routes an external deep link (widget tap, live-activity action, …) to the
/// in-app route. Uses the global router so initial-route and warm-start links
/// follow the same path.
Future<void> handleExternalDeepLink(GoRouter router, Uri uri) async {
  if (_isRestSkipLink(uri)) {
    router.go('/skip');
    return;
  }
  if (_isWidgetNutritionLink(uri)) {
    router.go('/nutrition');
    return;
  }
  if (_isWidgetWorkoutLink(uri)) {
    await _openWidgetWorkout(router);
    return;
  }
  // AI proposal deep links: hustl://proposal/<id> opens a single proposal's
  // approval card; hustl://proposals (allowlisted below) opens the inbox.
  final proposalId = _proposalIdFromLink(uri);
  if (proposalId != null) {
    await _openProposalLink(router, proposalId);
    return;
  }
  // Quick-action launcher widget tiles (both platforms) deep-link straight to an
  // existing app route, e.g. hustl:///add-food. Only an allowlist is honored —
  // never an arbitrary path from an external URI.
  if (uri.scheme == 'hustl' || uri.scheme == 'https') {
    final route = _launcherRoute(uri);
    if (_launcherRoutes.contains(route)) {
      router.go(route);
    }
  }
}

Future<void> _openProposalLink(GoRouter router, String proposalId) async {
  final wasMounted = _routerContext(router) != null;
  if (!wasMounted) await _waitForRouterMount(router);

  final location = '/proposals/${Uri.encodeComponent(proposalId)}';
  if (wasMounted) {
    router.push(location);
    return;
  }

  // Cold-start links can arrive while the bootstrapper is still rendering its
  // splash placeholder. Build the normal shell first, then push the proposal
  // route above it so iOS has a stable Navigator stack to render.
  router.go('/');
  await Future<void>.delayed(Duration.zero);
  router.push(location);
}

BuildContext? _routerContext(GoRouter router) =>
    router.configuration.navigatorKey.currentContext;

Future<void> _waitForRouterMount(GoRouter router) async {
  while (_routerContext(router) == null) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// App routes the quick-action launcher widget is allowed to open directly.
const Set<String> _launcherRoutes = {
  '/add-food',
  '/nutrition/weight',
  '/proposals',
};

/// Extracts the proposal id from a `hustl://proposal/<id>` link, tolerating both
/// the host (`hustl://proposal/<id>`) and path (`hustl:///proposal/<id>`) forms.
/// Returns null when the URI isn't a single-proposal deep link.
String? _proposalIdFromLink(Uri uri) {
  if (uri.scheme != 'hustl' && uri.scheme != 'https') return null;
  final segments = [if (uri.host.isNotEmpty) uri.host, ...uri.pathSegments];
  if (segments.length >= 2 && segments.first == 'proposal') {
    final id = segments[1].trim();
    return id.isEmpty ? null : id;
  }
  return null;
}

/// Reconstructs the full app route from a widget deep-link URI, tolerating both
/// the `hustl:///add-food` (path) and `hustl://add-food` (host) forms.
String _launcherRoute(Uri uri) {
  final segments = [if (uri.host.isNotEmpty) uri.host, ...uri.pathSegments];
  return '/${segments.join('/')}';
}

/// Resolves the active-session decision and navigates DIRECTLY to the
/// destination, instead of bouncing through the out-of-shell
/// `/widget/workouts` launch route.
///
/// That bounce was the real warm-launch bug: navigating to a top-level route
/// tears the [StatefulShellRoute] out of the match list, and the subsequent
/// `go('/')` reselected the Train branch without rebuilding its inner
/// navigator — a visible nav bar over a blank body that only a branch reselect
/// (a nav-bar tap) recovered. Going straight to `/workout_session` or `/` keeps
/// the shell mounted, so the branch stays populated.
Future<void> _openWidgetWorkout(GoRouter router) async {
  WorkoutSession? active;
  try {
    active = await GetIt.I<WorkoutRepository>()
        .getLatestActiveSession()
        .timeout(const Duration(seconds: 6));
  } catch (_) {
    active = null;
  }

  if (active != null && !active.isCompleted && active.endTime == null) {
    router.go(
      '/workout_session',
      extra: {'sessionId': active.id, 'initialName': active.name},
    );
    return;
  }
  router.go('/');
}

bool _matchesHost(Uri uri, String host, String firstSegment) {
  if (uri.scheme != 'hustl' && uri.scheme != 'https') return false;
  final segments = uri.pathSegments;
  if (uri.host == host) {
    return segments.isNotEmpty && segments.first == firstSegment;
  }
  return segments.length >= 2 &&
      segments.first == host &&
      segments[1] == firstSegment;
}

bool _isWidgetWorkoutLink(Uri uri) => _matchesHost(uri, 'widget', 'workouts');

bool _isWidgetNutritionLink(Uri uri) =>
    _matchesHost(uri, 'widget', 'nutrition');

bool _isRestSkipLink(Uri uri) => _matchesHost(uri, 'rest', 'skip');

/// Landing screen for widget / live-activity launches. Resolves whether there
/// is an active workout to resume and routes accordingly.
class WidgetWorkoutLaunchScreen extends StatefulWidget {
  const WidgetWorkoutLaunchScreen({super.key, this.stopRestTimer = false});

  final bool stopRestTimer;

  @override
  State<WidgetWorkoutLaunchScreen> createState() =>
      _WidgetWorkoutLaunchScreenState();
}

class _WidgetWorkoutLaunchScreenState extends State<WidgetWorkoutLaunchScreen> {
  // The launch screen only shows a skeleton, so the active-session lookup must
  // never hang here — a stalled lookup (seen on warm resume) would otherwise
  // strand the user on a blank loading screen. Fall back to home after this.
  static const _resolveTimeout = Duration(seconds: 6);

  bool _handled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleNavigation());
  }

  Future<void> _handleNavigation() async {
    if (_handled || !mounted) return;
    _handled = true;

    if (widget.stopRestTimer) {
      try {
        GetIt.I<RestTimerService>().stopTimer();
      } catch (_) {}
    }

    WorkoutSession? active;
    try {
      active = await GetIt.I<WorkoutRepository>()
          .getLatestActiveSession()
          .timeout(_resolveTimeout);
    } catch (_) {
      active = null;
    }

    // If the launcher was superseded (another deep link or user navigation)
    // while the lookup was pending it is no longer mounted — skip the redirect
    // so a late or timed-out result never steals a newer destination. When it
    // is still on screen, the timeout above guarantees we always get here and
    // redirect rather than hang on the skeleton.
    if (!mounted) return;
    final router = GoRouter.of(context);

    if (active != null && !active.isCompleted && active.endTime == null) {
      router.go(
        '/workout_session',
        extra: {'sessionId': active.id, 'initialName': active.name},
      );
      return;
    }
    router.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: HustlInlineSkeleton(liveRegion: true));
  }
}

/// Resolves an exercise-detail route by slug, loading the catalogue lazily.
class ExerciseDetailBySlugScreen extends StatelessWidget {
  const ExerciseDetailBySlugScreen({
    super.key,
    required this.slug,
    required this.initialTabIndex,
  });

  final String slug;
  final int initialTabIndex;

  @override
  Widget build(BuildContext context) {
    if (!GetIt.I.isRegistered<ExerciseRepository>()) {
      return const AccountScreen();
    }
    final repo = GetIt.I<ExerciseRepository>();

    return FutureBuilder<List<Exercise>>(
      future: repo.getAllExercises(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // Always give the transient loading route a back affordance so a
          // pushed exercise-detail-by-slug isn't a dead-end while it resolves —
          // matches the loaded ExerciseDetailScreen's HustlMenuButton leading.
          return Scaffold(
            appBar: AppBar(leading: const HustlMenuButton()),
            body: const HustlInlineSkeleton(liveRegion: true),
          );
        }
        final list = snapshot.data ?? const <Exercise>[];
        final match =
            list.cast<Exercise?>().firstWhere(
              (e) => e?.matchesIdentity(slug: slug) == true,
              orElse: () => null,
            ) ??
            list.cast<Exercise?>().firstWhere(
              (e) => (e?.canonicalKey ?? '') == slug.toLowerCase(),
              orElse: () => null,
            );

        if (match == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Exercise')),
            body: Center(child: Text('Exercise not found: $slug')),
          );
        }

        return ExerciseDetailScreen(
          exercise: match,
          initialTabIndex: initialTabIndex,
        );
      },
    );
  }
}
