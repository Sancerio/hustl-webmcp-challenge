import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

import '../di/service_locator.dart';

/// Critical startup initialization: only the work that must complete before the
/// first frame (DI core: prefs + theme + feature locators) plus best-effort,
/// non-fatal device tuning that can run alongside it.
///
/// Everything else (widgets, notifications, health writeback, sync) is deferred
/// to post-first-frame by [HustlAppBootstrapper].
Future<void> runCriticalInit() async {
  final stopwatch = Stopwatch()..start();
  await Future.wait([setupDependencies(), _applyHighRefreshRate()]);
  stopwatch.stop();
  if (kDebugMode) {
    dev.log('[Startup] Critical init in ${stopwatch.elapsedMilliseconds}ms');
  }
}

/// Requests the device's highest refresh rate on Android. Guarded and
/// non-fatal: failures (unsupported platform, no high-refresh display) are
/// swallowed so they never block startup.
Future<void> _applyHighRefreshRate() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await FlutterDisplayMode.setHighRefreshRate();
  } catch (error, stackTrace) {
    dev.log(
      '[Startup] High refresh rate request failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
