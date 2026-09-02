import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'model/evaluator_state.dart';
import 'ui/coach_screens.dart';
import 'ui/design.dart';
import 'ui/evaluator_scope.dart';
import 'ui/evaluator_shell.dart';
import 'ui/nutrition_screen.dart';
import 'ui/recovery_screen.dart';
import 'ui/template_screens.dart';
import 'ui/training_screen.dart';
import 'webmcp/tool.dart';
import 'webmcp/tool_host.dart';
import 'webmcp/web_mcp_controller.dart';

class EvaluatorApp extends StatefulWidget {
  const EvaluatorApp({super.key, required this.state, this.toolHost});

  final EvaluatorState state;
  final ToolHost? toolHost;

  @override
  State<EvaluatorApp> createState() => _EvaluatorAppState();
}

class _EvaluatorAppState extends State<EvaluatorApp> {
  bool _delegateRefreshStarted = false;

  late final GoRouter _router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/demo', redirect: (_, _) => '/'),
      ShellRoute(
        builder: (_, _, child) => EvaluatorShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const TrainingScreen()),
          GoRoute(path: '/health', builder: (_, _) => const RecoveryScreen()),
          GoRoute(
            path: '/nutrition',
            builder: (_, _) => const NutritionScreen(),
          ),
          GoRoute(path: '/proposals', builder: (_, _) => const CoachScreen()),
          GoRoute(
            path: '/proposals/:id',
            builder: (_, state) =>
                ProposalDetailScreen(proposalId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/templates',
            builder: (_, _) => const TemplatesScreen(),
          ),
          GoRoute(
            path: '/templates/:id',
            builder: (_, state) =>
                TemplateDetailScreen(templateId: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );

  late final WebMcpController _webMcp = WebMcpController(
    state: widget.state,
    host: widget.toolHost ?? createToolHost(),
    // Tool ownership follows the matched route, never a pre-redirect URI.
    currentRoute: () => _router.routerDelegate.currentConfiguration.uri.path,
    navigate: _router.go,
  );

  @override
  void initState() {
    super.initState();
    _router.routerDelegate.addListener(_routeChanged);
    // Let initial deep-link redirects settle before the first registration.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_delegateRefreshStarted) unawaited(_webMcp.refresh());
    });
  }

  void _routeChanged() {
    _delegateRefreshStarted = true;
    unawaited(_webMcp.refresh());
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_routeChanged);
    _webMcp.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EvaluatorScope(
    state: widget.state,
    child: MaterialApp.router(
      title: 'Hustl',
      debugShowCheckedModeBanner: false,
      theme: evaluatorTheme(),
      routerConfig: _router,
    ),
  );
}
