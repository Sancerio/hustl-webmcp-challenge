import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:go_router/go_router.dart';
import 'package:url_strategy/url_strategy.dart';

import 'app/bootstrap/hustl_app_bootstrapper.dart';
import 'app/navigation/app_router.dart';
import 'app/navigation/deep_links.dart';
import 'app/widgets/hustl_app.dart';

export 'app/navigation/app_router.dart' show createRouter, navigatorKey;

const String homeWidgetAppGroupId = 'group.com.hustl.app';

/// App-wide router. Initialized after `setPathUrlStrategy()` so the first load
/// of a deep link such as `/auth/google/callback?...` is not missed on web.
late final GoRouter appRouter;

Future<void> main() async {
  // Stamp the boot instant first so the branded SplashReveal can shorten itself
  // by however long the native splash was already up during a slow cold start.
  final launchedAt = DateTime.now();
  final binding = WidgetsFlutterBinding.ensureInitialized();

  // Root-zone error observer. The best-effort fire-and-forget background work
  // (health writeback + backend sync dispatches) now guards its OWN async
  // errors at the dispatch site, so this handler must NOT blanket-swallow: a
  // `return true` here would mark EVERY uncaught error handled and silently mask
  // real release crashes. We only log for visibility and return false so the
  // error keeps propagating to the framework / crash reporting.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught platform error (propagated): $error');
    return false;
  };
  // Keep the native splash up until the real app's first frame is scheduled.
  //
  // Web is intentionally excluded: `flutter_native_splash` is configured with
  // `web: false`, so no web splash JS is generated. On web, `preserve()` only
  // calls `deferFirstFrame()`, which must later be undone by `remove()`; but
  // `remove()` on web fires a `flutter_native_splash` MethodChannel call into a
  // JS function (`removeSplashFromWeb()`) that does not exist when `web: false`,
  // whose async reply throws a PlatformException / FormatException('Invalid
  // envelope') out of StandardMethodCodec.decodeEnvelope. The plugin's own
  // try/catch around `invokeMethod` only catches SYNCHRONOUS throws, so the
  // async error escapes as an uncaught zone error on every web load right after
  // the first post-login frame. Skipping preserve()/remove() on web avoids the
  // deferred-frame dance entirely (no hang) and the failing channel call.
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: binding);
  }

  // Path URL strategy on web so /auth/... routes resolve on first load.
  setPathUrlStrategy();
  appRouter = createRouter();

  runApp(
    HustlAppBootstrapper(
      app: HustlApp(router: appRouter, launchedAt: launchedAt),
      onExternalDeepLink: (uri) => handleExternalDeepLink(appRouter, uri),
      homeWidgetAppGroupId: homeWidgetAppGroupId,
    ),
  );
}
