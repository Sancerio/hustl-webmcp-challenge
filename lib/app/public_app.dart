import 'package:flutter/material.dart';

import '../core/webmcp/web_mcp_access_gate.dart';
import 'navigation/public_router.dart';
import 'navigation/shell_web_mcp_tools.dart';
import 'theme/app_theme.dart';
import 'public_dependencies.dart';

class PublicHustlApp extends StatefulWidget {
  const PublicHustlApp({super.key});

  @override
  State<PublicHustlApp> createState() => _PublicHustlAppState();
}

class _PublicHustlAppState extends State<PublicHustlApp> {
  late final router = createPublicRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Hustl WebMCP evaluator',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      builder: (context, child) => ShellWebMcpTools(
        enabled: getIt<WebMcpAccessGate>().ready.value,
        navigate: router.go,
        currentRoute: () => webMcpRouteForRouter(router),
        navigationChanges: router.routerDelegate,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
