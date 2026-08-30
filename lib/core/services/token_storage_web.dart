import 'package:shared_preferences/shared_preferences.dart';

import 'token_refresh.dart';

/// Web implementation of [TokenStorage] that persists tokens in
/// `localStorage` via `SharedPreferences` so authentication survives
/// full page refreshes.
class TokenStorage {
  static const _accessTokenKey = 'auth_access_token';
  static const _refreshTokenKey = 'auth_refresh_token';
  static const _tokenExpiryKey = 'auth_token_expiry';

  // Lightweight in-memory cache to reduce storage reads
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

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setInt(_tokenExpiryKey, expiryTime);
    // Do not store refresh token on web (HttpOnly cookie is used)
  }

  Future<String?> getAccessToken() async {
    const buffer = 60 * 1000;
    // Serve from memory if comfortably valid.
    if (_cachedAccessToken != null && _cachedExpiry != null) {
      if (DateTime.now().millisecondsSinceEpoch < (_cachedExpiry! - buffer)) {
        return _cachedAccessToken;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_accessTokenKey);
    final expiryTime = prefs.getInt(_tokenExpiryKey);
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
      // The refresher persists the new pair via saveTokenPair, updating the
      // static cache; return it when it is now valid.
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
    // Use HttpOnly cookie on web; never expose refresh token to JS.
    return null;
  }

  Future<void> clearAccessToken() async {
    _cachedAccessToken = null;
    _cachedExpiry = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_tokenExpiryKey);
  }

  Future<void> clearAll() async {
    await clearAccessToken();
    // Nothing to clear for refresh token on web; ensure prefs leftover is removed if any
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_refreshTokenKey);
  }
}
