import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';

import '../../app/di/service_locator.dart';
import '../../app/theme/app_theme.dart';
import '../../core/services/deep_link_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/nutrition_widget_service.dart';
import '../../core/services/workout_widget_service.dart';
import '../../core/widgets/hustl_error_screen.dart';
import '../../features/ai_proposals/services/proposal_count_service.dart';
import '../../features/health_sync/data/services/health_backend_sync_service.dart';
import '../../features/health_sync/data/sources/health_connect_intent_bridge.dart';
import '../../features/health_sync/data/writeback/workout_writeback_coordinator.dart';
import '../navigation/app_router.dart' show navigatorKey;
import '../demo/demo_mode.dart';
import 'startup_init.dart';

@visibleForTesting
bool shouldStartPostAppTasks({bool challengeMode = kChallengeMode}) =>
    !challengeMode;

/// Owns the startup lifecycle: keeps the native splash up while critical init
/// runs (no throwaway Flutter loading screen), mounts the real app once, removes
/// the native splash after the first real frame, then kicks non-critical work
/// off the critical path. Failures surface a retryable [HustlErrorScreen].
class HustlAppBootstrapper extends StatefulWidget {
  const HustlAppBootstrapper({
    super.key,
    required this.app,
    required this.onExternalDeepLink,
    required this.homeWidgetAppGroupId,
  });

  final Widget app;
  final void Function(Uri uri) onExternalDeepLink;
  final String homeWidgetAppGroupId;

  @override
  State<HustlAppBootstrapper> createState() => _HustlAppBootstrapperState();
}

class _HustlAppBootstrapperState extends State<HustlAppBootstrapper> {
  late Future<void> _bootstrapFuture;
  bool _postAppTasksScheduled = false;
  bool _deepLinksInitialized = false;
  bool _splashRemoved = false;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = runCriticalInit();
    _scheduleDeepLinkInit();
  }

  void _retryBootstrap() {
    setState(() {
      _postAppTasksScheduled = false;
      _bootstrapFuture = runCriticalInit();
    });
  }

  void _removeNativeSplash() {
    if (_splashRemoved) return;
    _splashRemoved = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // The SplashReveal overlay re-renders the same icon the native splash
      // shows; decode it first so the handoff frame never drops the logo.
      try {
        await precacheImage(
          const AssetImage('assets/icon/hustl-glyph-white.png'),
          context,
        );
      } catch (_) {
        // Decoding is best-effort; the reveal still works without it.
      }
      // Web is intentionally excluded: the native splash is configured with
      // `web: false`, so there is no web splash to remove. Calling
      // `FlutterNativeSplash.remove()` on web fires a MethodChannel call into a
      // JS function that does not exist (`removeSplashFromWeb()`), whose async
      // reply throws out of `StandardMethodCodec.decodeEnvelope` as an UNCAUGHT
      // zone error (the plugin's try/catch only guards synchronous throws). Web
      // never calls `preserve()` (see main.dart), so the first frame was never
      // deferred and there is nothing to undo here.
      if (!kIsWeb) {
        FlutterNativeSplash.remove();
      }
    });
  }

  void _scheduleDeepLinkInit() {
    if (kIsWeb || _deepLinksInitialized) return;
    _deepLinksInitialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        DeepLinkService().initialize(onNonAuthLink: widget.onExternalDeepLink),
      );
    });
  }

  void _schedulePostAppTasks() {
    if (_postAppTasksScheduled) return;
    _postAppTasksScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _startPostAppTasks());
  }

  void _startPostAppTasks() {
    if (!mounted) return;
    // The public evaluator is a deliberately sealed, in-memory product lane.
    // Skip every post-frame integration hook so no widget, notification,
    // writeback, proposal-polling, or health-sync service can contact an
    // external runtime. WebMCP access itself settles in AuthSyncListeners.
    if (!shouldStartPostAppTasks()) return;

    // Android-only: surface the Play "show rationale" launch into our health
    // privacy screen, and consume any signal queued before Dart was listening.
    unawaited(
      _guard(
        '[HealthConnect] rationale bridge',
        () => HealthConnectIntentBridge().init(
          onShowRationale: _showHealthPermissionRationale,
        ),
      ),
    );

    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      unawaited(HomeWidget.setAppGroupId(widget.homeWidgetAppGroupId));
    }

    if (getIt.isRegistered<WorkoutWidgetService>()) {
      unawaited(
        _guard(
          'home widget',
          () => getIt<WorkoutWidgetService>().updateWorkoutsPerWeekWidget(),
        ),
      );
    }
    if (getIt.isRegistered<NutritionWidgetService>()) {
      unawaited(
        _guard(
          'nutrition widget',
          () => getIt<NutritionWidgetService>().updateNutritionSummaryWidget(),
        ),
      );
    }
    if (getIt.isRegistered<NotificationService>()) {
      unawaited(getIt<NotificationService>().init());
    }
    // Poll-on-resume badge for AI proposals (no-ops when write-consent is OFF).
    if (getIt.isRegistered<ProposalCountService>()) {
      getIt<ProposalCountService>().start();
    }
    if (getIt.isRegistered<WorkoutWritebackCoordinator>()) {
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 500),
          () => _guard(
            '[WorkoutWriteback] init',
            () => getIt<WorkoutWritebackCoordinator>().init(),
          ),
        ),
      );
    }
    if (getIt.isRegistered<HealthBackendSyncService>()) {
      final healthSync = getIt<HealthBackendSyncService>();
      healthSync.startLifecycleSync();
      healthSync.scheduleLaunchSync();
    }
  }

  @override
  void dispose() {
    if (getIt.isRegistered<HealthBackendSyncService>()) {
      getIt<HealthBackendSyncService>().stopLifecycleSync();
    }
    super.dispose();
  }

  /// Routes to the health connect/permissions explanation screen in response to
  /// the Android Play "show rationale" intent. Uses the global navigator + the
  /// app's GoRouter (never `Navigator.*`); best-effort if the router isn't ready.
  Future<void> _showHealthPermissionRationale() async {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    try {
      final router = GoRouter.of(context);
      final path = router.routeInformationProvider.value.uri.path;
      if (path == '/health') return;
      router.push('/health');
    } catch (_) {
      // Router not ready (e.g. backgrounded); the user can still open Health
      // from settings. Best-effort, do not crash startup.
    }
  }

  Future<void> _guard(String label, Future<void> Function() task) async {
    try {
      await task();
    } catch (error, stackTrace) {
      dev.log('$label failed', error: error, stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // Native splash stays up; render nothing of our own.
          return const SizedBox.shrink();
        }

        if (snapshot.hasError) {
          _removeNativeSplash();
          return _ErrorApp(error: snapshot.error!, onRetry: _retryBootstrap);
        }

        _schedulePostAppTasks();
        _removeNativeSplash();
        return widget.app;
      },
    );
  }
}

class _ErrorApp extends StatelessWidget {
  const _ErrorApp({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hustl',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: HustlErrorScreen(
        title: 'Failed to start',
        details: error.toString(),
        onRetry: onRetry,
      ),
    );
  }
}
