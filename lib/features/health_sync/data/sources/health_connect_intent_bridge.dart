import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

/// Dart side of the `com.hustl.app/health_connect` MethodChannel implemented by
/// the Android [MainActivity].
///
/// It does two things:
///
/// 1. Surfaces the Play "show permissions rationale" launch. Android can start
///    the app straight into our privacy-rationale screen. The native side
///    queues that signal and pushes [showHealthPermissionRationale] when Dart is
///    listening; [init] also pulls any signal already queued before the handler
///    was attached (cold start), so the callback fires exactly once either way.
/// 2. Deep-links a permanently-denied user to the Health Connect manage-
///    permissions surface ([openManagePermissions]).
///
/// All methods are Android-only. On other platforms (and web) the channel has no
/// handler, so [init] no-ops and [openManagePermissions] returns false rather
/// than throwing a [MissingPluginException].
class HealthConnectIntentBridge {
  HealthConnectIntentBridge({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.hustl.app/health_connect');

  final MethodChannel _channel;

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Wires the incoming rationale notification and consumes any pending cold-
  /// start rationale. Safe to call on any platform; only does work on Android.
  Future<void> init({
    required Future<void> Function() onShowRationale,
  }) async {
    if (!_isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'showHealthPermissionRationale') {
        await onShowRationale();
      }
      return null;
    });
    try {
      final pending =
          await _channel.invokeMethod<bool>(
            'consumePendingHealthPermissionRationale',
          ) ??
          false;
      if (pending) await onShowRationale();
    } on MissingPluginException {
      // No native handler (e.g. unexpected platform); nothing to consume.
    }
  }

  /// Opens the Health Connect manage-permissions surface for this app. Returns
  /// true when a settings screen launched, false when none could be resolved
  /// (or off-Android). The caller should fall back to its existing flow on false.
  Future<bool> openManagePermissions() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'openHealthConnectPermissions',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }
}
