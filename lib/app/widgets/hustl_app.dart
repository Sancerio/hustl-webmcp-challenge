import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/theme_service.dart';
import '../../core/webmcp/web_mcp_access_gate.dart';
import '../../core/webmcp/web_mcp_config.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../bootstrap/splash_reveal.dart';
import '../demo/demo_experience_frame.dart';
import '../demo/demo_mode.dart';
import '../di/service_locator.dart';
import '../navigation/shell_web_mcp_tools.dart';
import '../theme/app_theme.dart';
import 'auth_sync_listeners.dart';
import '../../core/services/notification_service.dart';

/// Root application widget. Hosts the auth bloc, theme listener, sync side
/// effects and the router; overlays the one-shot [SplashReveal] above content
/// (auth hydration runs behind it — no blocking overlay).
class HustlApp extends StatefulWidget {
  const HustlApp({super.key, required this.router, this.launchedAt});

  final GoRouter router;

  /// When the app process began booting; forwarded to [SplashReveal] so the
  /// branded reveal can shorten itself after a slow cold start.
  final DateTime? launchedAt;

  @override
  State<HustlApp> createState() => _HustlAppState();
}

class _HustlAppState extends State<HustlApp> {
  bool _revealDone = false;

  @override
  void initState() {
    super.initState();
    // Cold-start notification tap: if the app was launched by tapping a
    // notification, dispatch its payload once the router/navigator is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().handleAppLaunchNotification();
    });
  }

  void _onRevealCompleted() {
    if (!mounted || _revealDone) return;
    setState(() => _revealDone = true);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<AuthBloc>()..add(AuthCheckRequested()),
      child: AuthSyncListeners(
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: getIt<ThemeService>().themeMode,
          builder: (context, mode, _) => MaterialApp.router(
            title: 'Hustl',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: mode,
            debugShowCheckedModeBanner: false,
            routerConfig: widget.router,
            builder: (context, child) {
              final app = child ?? const SizedBox.shrink();
              final Widget routedApp;
              if (kWebMcpEnabled && getIt.isRegistered<WebMcpAccessGate>()) {
                routedApp = ValueListenableBuilder<bool>(
                  valueListenable: getIt<WebMcpAccessGate>().ready,
                  child: app,
                  builder: (context, ready, child) => ShellWebMcpTools(
                    enabled: ready,
                    navigate: widget.router.go,
                    currentRoute: () => widget
                        .router
                        .routerDelegate
                        .currentConfiguration
                        .last
                        .matchedLocation,
                    navigationChanges: widget.router.routerDelegate,
                    child: child!,
                  ),
                );
              } else {
                routedApp = app;
              }
              final presentedApp = kChallengeMode
                  ? DemoExperienceFrame(child: routedApp)
                  : routedApp;
              return Stack(
                children: [
                  presentedApp,
                  if (!_revealDone)
                    SplashReveal(
                      onCompleted: _onRevealCompleted,
                      launchedAt: widget.launchedAt,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
