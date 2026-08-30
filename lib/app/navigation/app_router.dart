import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/route_observer.dart';
import '../../core/navigation/workout_minimize_intent.dart';
import '../../core/navigation/workout_minimize_transition.dart';
import '../../core/services/preferences_service.dart';
import '../../core/widgets/screen_empty_state.dart';
import '../../features/onboarding/domain/import_summary.dart';
import '../../features/onboarding/domain/workout_import_runner.dart';
import '../../features/onboarding/onboarding_flags.dart';
import '../../features/onboarding/presentation/first_win/onboarding_first_win_summary_screen.dart';
import '../../features/onboarding/presentation/import/onboarding_import_preview_screen.dart';
import '../../features/onboarding/presentation/import/onboarding_import_restored_screen.dart';
import '../../features/onboarding/presentation/import/onboarding_import_screen.dart';
import '../../features/onboarding/presentation/intro/onboarding_intro_screen.dart';
import '../../features/onboarding/presentation/intro/onboarding_welcome_screen.dart';
import '../../features/onboarding/presentation/proposal/onboarding_proposal_screen.dart';
import '../di/service_locator.dart';
import '../../features/ai_proposals/presentation/screens/proposal_approval_screen.dart';
import '../../features/ai_proposals/presentation/screens/proposals_inbox_screen.dart';
import '../../features/auth/presentation/screens/account_screen.dart';
import '../../features/auth/presentation/screens/oauth_callback_screen.dart';
import '../../features/connections/presentation/screens/connect_ai_help_screen.dart';
import '../../features/connections/presentation/screens/connections_screen.dart';
import '../../features/connections/presentation/widgets/connect_help_data.dart'
    show connectHelpClientById;
import '../../features/exercise_library/domain/models/exercise.dart';
import '../../features/exercise_library/presentation/screens/exercise_detail_screen.dart';
import '../../features/exercise_library/presentation/screens/exercise_library_screen.dart';
import '../../features/health_sync/presentation/screens/health_overview_screen.dart';
import '../../features/health_sync/presentation/screens/night_detail_screen.dart';
import '../../features/learn/presentation/screens/article_screen.dart';
import '../../features/nutrition_tracker/presentation/screens/diary_screen.dart';
import '../../features/nutrition_tracker/presentation/screens/expenditure_trend_screen.dart';
import '../../features/nutrition_tracker/presentation/screens/global_add_food_screen.dart';
import '../../features/nutrition_tracker/presentation/screens/insights_screen.dart';
import '../../features/nutrition_tracker/presentation/screens/nutrition_sign_in_required_screen.dart';
import '../../features/nutrition_tracker/presentation/screens/strategy_screen.dart';
import '../../features/nutrition_tracker/presentation/screens/weight_trend_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/data_import_export_screen.dart';
import '../../features/workout_log/domain/services/body_score_service.dart';
import '../../features/workout_log/presentation/screens/body_score_screen.dart';
import '../../features/workout_log/presentation/screens/workout_edit_screen.dart';
import '../../features/workout_log/presentation/screens/workout_history_screen.dart';
import '../../features/workout_log/presentation/screens/workout_progress_screen.dart';
import '../../features/workout_logging/domain/models/workout_session.dart';
import '../../features/workout_logging/presentation/screens/active_workout_screen.dart';
import '../../features/workout_logging/presentation/screens/exercise_selection_screen.dart';
import '../../features/workout_logging/presentation/screens/workout_home_screen.dart';
import '../../features/workout_logging/presentation/screens/workout_summary_screen.dart';
import '../../features/workout_templates/presentation/screens/template_detail_screen.dart';
import '../../features/workout_templates/presentation/screens/templates_screen.dart';
import '../demo/demo_landing_screen.dart';
import '../demo/demo_mode.dart';
import '../theme/app_motion.dart';
import 'app_shell.dart';
import 'deep_links.dart';

/// Global navigator key for navigation from services / non-widget layers.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final GlobalKey<NavigatorState> _shellNavigatorTrain =
    GlobalKey<NavigatorState>(debugLabel: 'train');
final GlobalKey<NavigatorState> _shellNavigatorNutrition =
    GlobalKey<NavigatorState>(debugLabel: 'nutrition');
final GlobalKey<NavigatorState> _shellNavigatorHistory =
    GlobalKey<NavigatorState>(debugLabel: 'history');
final GlobalKey<NavigatorState> _shellNavigatorProgress =
    GlobalKey<NavigatorState>(debugLabel: 'progress');
final GlobalKey<NavigatorState> _shellNavigatorLibrary =
    GlobalKey<NavigatorState>(debugLabel: 'library');

Page<void> _appPage(GoRouterState state, Widget child) {
  // On iOS, use a Cupertino page so pushed screens get the native interactive
  // edge-swipe-back gesture — a CustomTransitionPage (below) silently drops it.
  // Web and Android keep the brand fade-slide. Tab roots switch via the shell's
  // IndexedStack (no page transition plays), so this only changes what users
  // actually see on pushed iOS screens: a native slide-in they can swipe back.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return CupertinoPage<void>(
      key: state.pageKey,
      name: state.name ?? state.fullPath,
      child: child,
    );
  }
  return CustomTransitionPage<void>(
    key: state.pageKey,
    name: state.name ?? state.fullPath,
    transitionDuration: AppMotion.medium,
    reverseTransitionDuration: AppMotion.fast,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) return child;
      return appFadeSlideTransition(child, animation);
    },
  );
}

Page<void> _nutritionGate(
  GoRouterState state,
  Widget Function(BuildContext) authed,
) {
  return _appPage(
    state,
    NutritionAuthGate(
      authenticatedBuilder: authed,
      unauthenticatedBuilder: (_) => const NutritionSignInRequiredScreen(),
    ),
  );
}

/// Pure gating logic for the v3 branded onboarding, extracted so it can be unit
/// tested without the compile-time flag.
///
/// Allowlist, not denylist: a new user is only intercepted on a plain cold start
/// (`/`). Every deep link (widget / notification / launcher / OAuth → its own
/// route) and the in-onboarding routes pass straight through, so onboarding can
/// never swallow a deep link. Returning users (seen) are bounced out of
/// `/onboarding/*` and otherwise untouched.
@visibleForTesting
String? onboardingRedirectTarget({
  required bool enabled,
  required bool seen,
  required String location,
}) {
  if (!enabled) return null;
  if (seen) {
    // The post-onboarding first-win summary ("Building your plan"), the AI
    // "magic moment" starter proposal, and the Strong import flow are all
    // reached by already-seen users: intro-seen is marked before entering each
    // of these (not just on their own completion), so an app-kill mid-flow
    // resumes past the carousel instead of replaying it. Let them through so
    // their `go`/`push` are not bounced home; only the first-run intro/welcome
    // are bounced for seen users.
    if (location.startsWith('/onboarding/first-win')) return null;
    if (location.startsWith('/onboarding/proposal')) return null;
    if (location.startsWith('/onboarding/import')) return null;
    return location.startsWith('/onboarding') ? '/' : null;
  }
  if (location == '/') return '/onboarding/intro';
  return null;
}

/// First-run gate (on by default). Runs after DI, so prefs are populated and the
/// sync getters are safe to read. An already-onboarded user (intro seen, v2
/// entry seen, or any returning-user signal) is treated as seen, so v3 never
/// re-onboards an existing user.
String? _onboardingRedirect(BuildContext context, GoRouterState state) {
  // Kill switch first: a flag-off build never gates and never touches DI, so
  // lightweight/OAuth-callback router tests (which don't run full DI) are safe.
  if (!kOnboardingV3Enabled) return null;
  // Never gate inside the test harness — full-router widget/golden tests mount
  // at '/' and would otherwise mass-redirect into the intro. The gate logic is
  // covered directly by onboardingRedirectTarget unit tests.
  final binding = WidgetsBinding.instance.runtimeType.toString();
  if (binding.contains('TestWidgetsFlutterBinding') ||
      binding.contains('AutomatedTestWidgetsFlutterBinding')) {
    return null;
  }
  if (!getIt.isRegistered<PreferencesService>()) return null;
  final prefs = getIt<PreferencesService>();
  return onboardingRedirectTarget(
    enabled: kOnboardingV3Enabled,
    seen:
        prefs.onboardingIntroSeen ||
        prefs.onboardingV2SeenEntrySync ||
        prefs.hasReturningUserSignal,
    location: state.matchedLocation,
  );
}

GoRouter createRouter({
  Widget Function(BuildContext, GoRouterState)? oauthCallbackBuilder,
  bool challengeMode = kChallengeMode,
}) {
  return GoRouter(
    navigatorKey: navigatorKey,
    observers: [routeObserver],
    errorBuilder: (context, state) => const _RouteNotFoundScreen(),
    redirect: challengeMode ? null : _onboardingRedirect,
    routes: [
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, navigationShell) => NoTransitionPage(
          key: state.pageKey,
          name: appShellRouteName,
          child: AppShell(navigationShell: navigationShell),
        ),
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellNavigatorTrain,
            routes: [
              GoRoute(
                path: '/',
                name: '/',
                pageBuilder: (context, state) =>
                    _appPage(state, const WorkoutHomeScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _shellNavigatorNutrition,
            routes: [
              GoRoute(
                path: '/nutrition',
                name: '/nutrition',
                // Gate the diary tab itself. Everything reachable from it
                // (targets, add-food, weight, insights) already requires
                // sign-in, so an ungated diary only dangled CTAs ("Set my
                // targets", "Just log a food") that dead-ended at the sign-in
                // wall. Show that wall up front instead of behind a teaser.
                pageBuilder: (context, state) =>
                    _nutritionGate(state, (_) => const DiaryScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _shellNavigatorHistory,
            routes: [
              GoRoute(
                path: '/history',
                name: '/history',
                pageBuilder: (context, state) {
                  final regionParam = state.uri.queryParameters['region'];
                  final rangeParam = state.uri.queryParameters['range'];
                  return _appPage(
                    state,
                    WorkoutHistoryScreen(
                      initialRegion: regionParam == null
                          ? null
                          : displayRegionFromKey(regionParam),
                      initialRangeDays: rangeParam == null
                          ? null
                          : int.tryParse(rangeParam),
                    ),
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _shellNavigatorProgress,
            routes: [
              GoRoute(
                path: '/progress',
                name: '/progress',
                pageBuilder: (context, state) =>
                    _appPage(state, const WorkoutProgressScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _shellNavigatorLibrary,
            routes: [
              GoRoute(
                path: '/exercise_library',
                name: '/exercise_library',
                pageBuilder: (context, state) =>
                    _appPage(state, const ExerciseLibraryScreen()),
              ),
            ],
          ),
        ],
      ),
      ..._overlayRoutes(oauthCallbackBuilder, challengeMode: challengeMode),
    ],
  );
}

/// Routes that push OVER the shell (active workout, summary, settings, account,
/// detail screens, deep-link landings, …). These are not part of any tab
/// branch's indexed stack.
List<RouteBase> _overlayRoutes(
  Widget Function(BuildContext, GoRouterState)? oauthCallbackBuilder, {
  required bool challengeMode,
}) {
  return [
    GoRoute(
      path: '/demo',
      name: '/demo',
      parentNavigatorKey: navigatorKey,
      redirect: (context, state) =>
          demoRouteRedirectTarget(challengeMode: challengeMode),
      pageBuilder: (context, state) =>
          _appPage(state, const DemoLandingScreen()),
    ),
    GoRoute(
      path: '/onboarding/intro',
      name: '/onboarding/intro',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) =>
          _appPage(state, const OnboardingIntroScreen()),
    ),
    GoRoute(
      path: '/onboarding/welcome',
      name: '/onboarding/welcome',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) =>
          _appPage(state, const OnboardingWelcomeScreen()),
    ),
    GoRoute(
      path: '/onboarding/import',
      name: '/onboarding/import',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) =>
          _appPage(state, const OnboardingImportScreen()),
    ),
    GoRoute(
      path: '/onboarding/import/preview',
      name: '/onboarding/import/preview',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) {
        final extra = state.extra;
        if (extra is Map &&
            extra['sessions'] is List &&
            extra['summary'] is ImportSummary) {
          return _appPage(
            state,
            OnboardingImportPreviewScreen(
              sessions: (extra['sessions'] as List).cast<WorkoutSession>(),
              summary: extra['summary'] as ImportSummary,
            ),
          );
        }
        // Stale / direct hit without a parsed file: restart the pick instead of
        // dead-ending.
        return _appPage(state, const OnboardingImportScreen());
      },
    ),
    GoRoute(
      path: '/onboarding/import/restored',
      name: '/onboarding/import/restored',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) {
        final extra = state.extra;
        if (extra is Map &&
            extra['outcome'] is ImportOutcome &&
            extra['summary'] is ImportSummary) {
          return _appPage(
            state,
            OnboardingImportRestoredScreen(
              outcome: extra['outcome'] as ImportOutcome,
              summary: extra['summary'] as ImportSummary,
            ),
          );
        }
        return _appPage(state, const OnboardingImportScreen());
      },
    ),
    GoRoute(
      path: '/onboarding/first-win/:id',
      name: '/onboarding/first-win/:id',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) => _appPage(
        state,
        OnboardingFirstWinSummaryScreen(
          sessionId: state.pathParameters['id'] ?? '',
        ),
      ),
    ),
    GoRoute(
      // The AI "magic moment": a first-party starter proposal the user can
      // approve through the existing pipeline. The screen provisions its own
      // ProposalsBloc from GetIt (like ProposalApprovalScreen).
      path: '/onboarding/proposal',
      name: '/onboarding/proposal',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) =>
          _appPage(state, const OnboardingProposalScreen()),
    ),
    GoRoute(
      path: '/summary/:id',
      name: '/summary/:id',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) {
        final id = state.pathParameters['id']!;
        final extra = state.extra;
        String? highlight;
        var justFinished = false;
        if (extra is Map) {
          final val = extra['highlightExerciseKey'];
          if (val is String) highlight = val;
          // Only the just-finished post-workout flow passes this flag; history
          // and deep links omit it, so they never show today's recovery note.
          justFinished = extra['justFinished'] == true;
        }
        return _appPage(
          state,
          WorkoutSummaryScreen(
            sessionId: id,
            highlightExerciseKey: highlight,
            justFinished: justFinished,
          ),
        );
      },
    ),
    GoRoute(
      path: '/exercise_detail',
      name: '/exercise_detail',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) {
        final extra = state.extra;
        if (extra is Exercise) {
          return _appPage(state, ExerciseDetailScreen(exercise: extra));
        }
        if (extra is Map) {
          final ex = extra['exercise'];
          final tab = extra['initialTabIndex'];
          if (ex is Exercise) {
            return _appPage(
              state,
              ExerciseDetailScreen(
                exercise: ex,
                initialTabIndex: tab is int ? tab : 0,
              ),
            );
          }
        }
        // No valid exercise to show (e.g. a stale/deep link without extra) —
        // surface the standard not-found screen instead of dead-ending on the
        // account screen.
        return _appPage(state, const _RouteNotFoundScreen());
      },
    ),
    GoRoute(
      path: '/templates',
      name: '/templates',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) => _appPage(state, const TemplatesScreen()),
    ),
    GoRoute(
      path: '/templates/:id',
      name: '/templates/:id',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) {
        final templateId = state.pathParameters['id'] ?? '';
        final extra = state.extra;
        final startInEditMode =
            extra is Map && extra['startInEditMode'] == true;
        return _appPage(
          state,
          TemplateDetailScreen(
            templateId: templateId,
            startInEditMode: startInEditMode,
          ),
        );
      },
    ),
    GoRoute(
      path: '/proposals',
      name: '/proposals',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) =>
          _appPage(state, const ProposalsInboxScreen()),
    ),
    GoRoute(
      path: '/proposals/:id',
      name: '/proposals/:id',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) => _appPage(
        state,
        ProposalApprovalScreen(proposalId: state.pathParameters['id'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/connections',
      name: '/connections',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) =>
          _appPage(state, const ConnectionsScreen()),
    ),
    GoRoute(
      path: '/connections/help',
      name: '/connections/help',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) =>
          _appPage(state, const ConnectAiHelpScreen()),
    ),
    GoRoute(
      // One platform's steps as its own route, so the AppBar back button and the
      // native iOS edge-swipe both return to the picker. Unknown slug (e.g. a
      // stale deep link) falls back to the picker.
      path: '/connections/help/:client',
      name: '/connections/help/:client',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) {
        final client = connectHelpClientById(state.pathParameters['client']);
        return _appPage(
          state,
          client == null
              ? const ConnectAiHelpScreen()
              : ConnectAiHelpArticleScreen(client: client),
        );
      },
    ),
    GoRoute(
      path: '/account',
      name: '/account',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) => _appPage(state, const AccountScreen()),
    ),
    GoRoute(
      path: '/settings/import-export',
      name: '/settings/import-export',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) =>
          _appPage(state, const DataImportExportScreen()),
    ),
    GoRoute(
      path: '/learn/:slug',
      name: '/learn/:slug',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) => _appPage(
        state,
        ArticleScreen(slug: state.pathParameters['slug'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/workouts',
      redirect: (context, state) => '/widget/workouts',
    ),
    GoRoute(
      path: '/skip',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) =>
          _appPage(state, const WidgetWorkoutLaunchScreen(stopRestTimer: true)),
    ),
    GoRoute(
      path: '/rest/skip',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) =>
          _appPage(state, const WidgetWorkoutLaunchScreen(stopRestTimer: true)),
    ),
    GoRoute(
      path: '/widget/workouts',
      name: '/widget/workouts',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) =>
          _appPage(state, const WidgetWorkoutLaunchScreen()),
    ),
    GoRoute(
      path: '/widget/nutrition',
      redirect: (context, state) => '/nutrition',
    ),
    GoRoute(
      path: '/auth/google/callback',
      name: '/auth/google/callback',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) {
        final builder =
            oauthCallbackBuilder ??
            (BuildContext context, GoRouterState state) =>
                OAuthCallbackScreen(callbackUri: state.uri);
        return _appPage(state, builder(context, state));
      },
    ),
    GoRoute(
      path: '/workout',
      name: '/workout',
      // Legacy deep links and stored post-login routes converge on the sole
      // active-workout owner so route-scoped capabilities cannot diverge from
      // the screen the user sees.
      redirect: (context, state) => '/workout_session',
    ),
    GoRoute(
      path: '/workout_edit/:id',
      name: '/workout_edit/:id',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) => _appPage(
        state,
        WorkoutEditScreen(sessionId: state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/exercise_library/:slug',
      name: '/exercise_library/:slug',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) {
        final slug = state.pathParameters['slug'] ?? '';
        final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '');
        final initialTabIndex = (tab != null && tab >= 0 && tab <= 2) ? tab : 0;
        return _appPage(
          state,
          ExerciseDetailBySlugScreen(
            slug: slug,
            initialTabIndex: initialTabIndex,
          ),
        );
      },
    ),
    GoRoute(
      path: '/exercise_select',
      name: '/exercise_select',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) =>
          _appPage(state, const ExerciseSelectionScreen()),
    ),
    GoRoute(
      // Global one-tap "log food" entry point: opens AddFoodSheet for today
      // from anywhere (shell / nutrition tab). No date argument by design.
      path: '/add-food',
      name: '/add-food',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) =>
          _nutritionGate(state, (_) => const GlobalAddFoodScreen()),
    ),
    GoRoute(
      path: '/nutrition/strategy',
      name: '/nutrition/strategy',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) =>
          _nutritionGate(state, (_) => const StrategyScreen()),
    ),
    GoRoute(
      path: '/nutrition/weight',
      name: '/nutrition/weight',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) =>
          _nutritionGate(state, (_) => const WeightTrendScreen()),
    ),
    GoRoute(
      path: '/nutrition/insights',
      name: '/nutrition/insights',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) =>
          _nutritionGate(state, (_) => const NutritionInsightsScreen()),
    ),
    GoRoute(
      path: '/nutrition/expenditure',
      name: '/nutrition/expenditure',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) =>
          _nutritionGate(state, (_) => const ExpenditureTrendScreen()),
    ),
    GoRoute(
      path: '/progress/body-score',
      name: '/progress/body-score',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) {
        final summary = state.extra;
        return _appPage(
          state,
          BodyScoreScreen(
            initialSummary: summary is BodyScoreSummary ? summary : null,
          ),
        );
      },
    ),
    GoRoute(
      path: '/settings',
      name: '/settings',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) => _appPage(state, const SettingsScreen()),
    ),
    GoRoute(
      path: '/health',
      name: '/health',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) =>
          _appPage(state, const HealthOverviewScreen()),
    ),
    GoRoute(
      path: '/health/night',
      name: '/health/night',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) {
        final extra = state.extra;
        return _appPage(
          state,
          NightDetailScreen(args: extra is NightDetailArgs ? extra : null),
        );
      },
    ),
    if (kDebugMode)
      GoRoute(
        path: '/health-preview',
        name: '/health-preview',
        parentNavigatorKey: navigatorKey,
        pageBuilder: (context, state) =>
            _appPage(state, const HealthOverviewScreen.preview()),
      ),
    GoRoute(
      path: '/workout_session',
      name: '/workout_session',
      parentNavigatorKey: navigatorKey,
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final returnLocation = workoutReturnLocationFromExtra(extra);
        return workoutMinimizePage(
          state,
          ActiveWorkoutScreen(
            sessionId: extra?['sessionId'] as String?,
            initialName: extra?['initialName'] as String? ?? 'Workout',
            initialExercises: (extra?['initialExercises'] as List?)
                ?.cast<Map<String, dynamic>>(),
            returnLocation: returnLocation,
          ),
          expandFromMiniPlayer:
              extra?[workoutExpandFromMiniPlayerExtraKey] == true,
          returnLocation: returnLocation,
        );
      },
    ),
  ];
}

@visibleForTesting
String? demoRouteRedirectTarget({required bool challengeMode}) {
  return challengeMode ? null : '/';
}

/// A real not-found landing for unmatched routes — a kind empty-state hero with
/// a single blue "Go home" action instead of silently dropping onto Account.
class _RouteNotFoundScreen extends StatelessWidget {
  const _RouteNotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ScreenEmptyState(
          icon: Icons.travel_explore_outlined,
          title: "We couldn't find that page",
          message: 'The link may be old or the page may have moved.',
          actionLabel: 'Go home',
          onAction: () => context.go('/'),
        ),
      ),
    );
  }
}
