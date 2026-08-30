import 'dart:io' show Platform;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hustl_app/core/config/api_config.dart';
import 'package:hustl_app/core/services/token_refresh.dart';

class TokenStorage {
  static const _accessTokenKey = 'auth_access_token';
  static const _refreshTokenKey = 'auth_refresh_token';
  static const _tokenExpiryKey = 'auth_token_expiry';
  // Shared keychain access group: intended to let the Apple Watch read the access
  // token (+ API base URL) so it can sync workouts directly to the backend when the
  // phone is unreachable (Phase 5 fallback). iOS only.
  //
  // DEFERRED (needs owner + entitlement/provisioning decision — not safe to change
  // here): as written these are NON-synchronizable keychain items in a shared access
  // group. A keychain access group only shares items between targets on the SAME
  // device; the Apple Watch is a separate device, so this write does NOT reliably
  // reach the watch's keychain. Two gaps must both be closed for the watch read
  // (WatchSyncUploader) to ever succeed:
  //   1. Entitlement: ios/HustlWatchExtension/HustlWatchExtension.entitlements has NO
  //      `keychain-access-groups` (only HustlWatch.entitlements / Runner do), so the
  //      extension's SecItemCopyMatching against this group can't match. Adding it is
  //      a provisioning-profile change.
  //   2. Cross-device delivery: pick ONE of —
  //      (a) write+read these with `synchronizable: true` on BOTH sides (relies on
  //          iCloud Keychain being enabled; note synchronizable and non-sync items are
  //          DISTINCT keychain entries, so flipping it changes item identity and must
  //          be validated on-device against the existing same-device readers), or
  //      (b) hand short-lived credentials to the watch over WCSession instead of the
  //          keychain (no iCloud dependency; needs a new bridge message + watch wiring).
  // Until one of these lands, the phone-never-returns fallback will usually find no
  // token/base URL and silently skip the direct upload (the phone-mediated
  // reconciliation path is unaffected). Behavior intentionally left unchanged here to
  // avoid breaking the working same-device readers with an unvalidated keychain flag.
  static const _sharedKeychainGroup = 'FZZ26XMXRC.com.hustl.shared';
  static const _sharedBaseUrlKey = 'hustl_api_base_url';
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  final FlutterSecureStorage _sharedSecure = const FlutterSecureStorage(
    iOptions: IOSOptions(groupId: _sharedKeychainGroup),
  );
  static String? _cachedAccessToken;
  static int? _cachedExpiry;

  Future<void> saveTokenPair({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
  }) async {
    final expiryTime = DateTime.now()
        .add(Duration(seconds: expiresIn))
        .millisecondsSinceEpoch;
    _cachedAccessToken = accessToken;
    _cachedExpiry = expiryTime;

    // macOS desktop builds aren't supported; use SharedPreferences on macOS so
    // widget tests (which run on the host) don't require secure storage mocks.
    if (Platform.isAndroid || Platform.isIOS) {
      await _secure.write(key: _accessTokenKey, value: accessToken);
      if (refreshToken != null) {
        await _secure.write(key: _refreshTokenKey, value: refreshToken);
      }
      await _secure.write(key: _tokenExpiryKey, value: expiryTime.toString());
      if (Platform.isIOS) {
        // Best-effort mirror to the shared keychain group for the watch.
        try {
          await _sharedSecure.write(key: _accessTokenKey, value: accessToken);
          await _sharedSecure.write(
            key: _tokenExpiryKey,
            value: expiryTime.toString(),
          );
          await _sharedSecure.write(
            key: _sharedBaseUrlKey,
            value: ApiConfig.baseUrl,
          );
        } catch (_) {}
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accessTokenKey, accessToken);
      if (refreshToken != null) {
        await prefs.setString(_refreshTokenKey, refreshToken);
      }
      await prefs.setInt(_tokenExpiryKey, expiryTime);
    }
  }

  Future<String?> getAccessToken() async {
    const buffer = 60 * 1000;
    // Serve from memory if comfortably valid.
    if (_cachedAccessToken != null && _cachedExpiry != null) {
      if (DateTime.now().millisecondsSinceEpoch < (_cachedExpiry! - buffer)) {
        return _cachedAccessToken;
      }
    }
    String? token;
    int? expiryTime;
    if (Platform.isAndroid || Platform.isIOS) {
      token = await _secure.read(key: _accessTokenKey);
      final expiryStr = await _secure.read(key: _tokenExpiryKey);
      if (expiryStr != null) expiryTime = int.tryParse(expiryStr);
    } else {
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString(_accessTokenKey);
      expiryTime = prefs.getInt(_tokenExpiryKey);
    }
    final valid =
        token != null &&
        expiryTime != null &&
        DateTime.now().millisecondsSinceEpoch < (expiryTime - buffer);
    if (valid) {
      _cachedAccessToken = token;
      _cachedExpiry = expiryTime;
      return token;
    }

    // Missing or within the expiry buffer: refresh in place (single-flight)
    // instead of dropping the bearer header, which would 401 the request.
    if (await TokenRefreshCoordinator.refresh()) {
      if (_cachedAccessToken != null &&
          _cachedExpiry != null &&
          DateTime.now().millisecondsSinceEpoch < (_cachedExpiry! - buffer)) {
        return _cachedAccessToken;
      }
    }
    await clearAccessToken();
    return null;
  }

  Future<String?> getRefreshToken() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return _secure.read(key: _refreshTokenKey);
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  Future<void> clearAccessToken() async {
    _cachedAccessToken = null;
    _cachedExpiry = null;
    if (Platform.isAndroid || Platform.isIOS) {
      await _secure.delete(key: _accessTokenKey);
      await _secure.delete(key: _tokenExpiryKey);
      if (Platform.isIOS) {
        try {
          await _sharedSecure.delete(key: _accessTokenKey);
          await _sharedSecure.delete(key: _tokenExpiryKey);
        } catch (_) {}
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_accessTokenKey);
      await prefs.remove(_tokenExpiryKey);
    }
  }

  Future<void> clearAll() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await _secure.delete(key: _accessTokenKey);
      await _secure.delete(key: _refreshTokenKey);
      await _secure.delete(key: _tokenExpiryKey);
      if (Platform.isIOS) {
        try {
          await _sharedSecure.delete(key: _accessTokenKey);
          await _sharedSecure.delete(key: _tokenExpiryKey);
          await _sharedSecure.delete(key: _sharedBaseUrlKey);
        } catch (_) {}
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_accessTokenKey);
      await prefs.remove(_refreshTokenKey);
      await prefs.remove(_tokenExpiryKey);
    }
  }
}
