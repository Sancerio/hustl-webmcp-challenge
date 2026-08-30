import 'package:flutter/services.dart' show PlatformException;

/// Google Play Services status codes surfaced by the `google_sign_in` plugin on
/// Android. The plugin reports these as a `PlatformException(code:
/// 'sign_in_failed', message: 'ApiException: <n>: ...')` — the actionable status
/// lives in [PlatformException.message], NOT in [PlatformException.code].
class GoogleApiStatus {
  GoogleApiStatus._();

  /// No network — `CommonStatusCodes.NETWORK_ERROR`.
  static const int networkError = 7;

  /// Misconfiguration: the calling app's package + signing SHA-1 are not
  /// registered on the Android OAuth client (e.g. a debug-signed local build).
  /// Deterministic, not transient — `CommonStatusCodes.DEVELOPER_ERROR`.
  static const int developerError = 10;

  /// Generic sign-in failure — `GoogleSignInStatusCodes.SIGN_IN_FAILED`.
  static const int signInFailed = 12500;

  /// User dismissed the chooser — `GoogleSignInStatusCodes.SIGN_IN_CANCELLED`.
  static const int signInCancelled = 12501;
}

/// Extracts the numeric Google Play Services status code from a
/// [PlatformException] thrown by `google_sign_in` on Android, or `null` when the
/// message carries no recognizable code.
///
/// Handles both the fully-qualified form
/// (`com.google.android.gms.common.api.ApiException: 10: `) and a bare leading
/// `10: ...` form.
int? googleApiExceptionCode(PlatformException e) {
  final message = e.message ?? '';
  final match =
      RegExp(r'ApiException:\s*(\d+)').firstMatch(message) ??
      RegExp(r'^\s*(\d+):').firstMatch(message);
  final code = match?.group(1);
  return code == null ? null : int.tryParse(code);
}
