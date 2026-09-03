import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/main_scaffold.dart';
import '../demo/demo_dependencies.dart';
import '../demo/demo_workout_seed.dart';
import '../../features/ai_proposals/presentation/screens/proposal_approval_screen.dart';
import '../../features/ai_proposals/presentation/screens/proposals_inbox_screen.dart';
import '../../features/health_sync/presentation/screens/health_overview_screen.dart';
import '../../features/nutrition_tracker/presentation/screens/diary_screen.dart';
import '../../features/workout_logging/presentation/screens/active_workout_screen.dart';
import '../../features/workout_logging/presentation/screens/workout_home_screen.dart';
import '../../features/workout_templates/presentation/screens/template_detail_screen.dart';
import '../../features/workout_templates/presentation/screens/templates_screen.dart';
import 'app_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _trainKey = GlobalKey<NavigatorState>();
final _nutritionKey = GlobalKey<NavigatorState>();

GoRouter createPublicRouter() => GoRouter(
  navigatorKey: _rootKey,
  errorBuilder: (_, __) => const _UnavailableScreen(),
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, __, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          navigatorKey: _trainKey,
          routes: [GoRoute(path: '/', builder: (_, __) => const WorkoutHomeScreen())],
        ),
        StatefulShellBranch(
          navigatorKey: _nutritionKey,
          routes: [GoRoute(path: '/nutrition', builder: (_, __) => const DiaryScreen())],
        ),
      ],
    ),
    GoRoute(path: '/proposals', builder: (_, __) => const ProposalsInboxScreen()),
    GoRoute(
      path: '/proposals/:id',
      builder: (_, state) =>
          ProposalApprovalScreen(proposalId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/account', redirect: (_, __) => '/proposals'),
    GoRoute(path: '/health', builder: (_, __) => const HealthOverviewScreen()),
    GoRoute(path: '/templates', builder: (_, __) => const TemplatesScreen()),
    GoRoute(
      path: '/templates/:id',
      builder: (_, state) => TemplateDetailScreen(
        templateId: state.pathParameters['id']!,
        startInEditMode: state.extra is Map &&
            (state.extra as Map)['startInEditMode'] == true,
      ),
    ),
    GoRoute(
      path: '/workout_session',
      builder: (_, state) {
        final supplied = state.extra is Map
            ? Map<String, dynamic>.from(state.extra as Map)
            : const <String, dynamic>{};
        final seed = DemoWorkoutSeed(anchor: demoAnchor()).buildSessions().first;
        final extra = supplied.isNotEmpty
            ? supplied
            : <String, dynamic>{
                'initialName': 'Repeat ${seed.name}',
                'initialExercises': seed.exercises
                    .map(
                      (exercise) => <String, dynamic>{
                        'name': exercise.exercise.name,
                        'sets': exercise.sets.length,
                        'rest': exercise.restTimerSeconds,
                        'previousSets': exercise.sets
                            .map((set) => set.toMap())
                            .toList(),
                      },
                    )
                    .toList(),
              };
        return ActiveWorkoutScreen(
          sessionId: extra['sessionId'] as String?,
          initialName: extra['initialName'] as String? ?? 'Workout',
          initialExercises:
              (extra['initialExercises'] as List?)?.cast<Map<String, dynamic>>(),
          returnLocation: extra['returnLocation'] as String?,
        );
      },
    ),
    GoRoute(path: '/workout', redirect: (_, __) => '/workout_session'),
  ],
);

class _UnavailableScreen extends StatelessWidget {
  const _UnavailableScreen();

  @override
  Widget build(BuildContext context) => const MainScaffold(
    child: Center(child: Text('This route is not part of the public evaluator.')),
  );
}
