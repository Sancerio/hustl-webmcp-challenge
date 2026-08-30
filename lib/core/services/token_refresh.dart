/// Single-flight access-token refresh shared by both [TokenStorage]
/// implementations (web/io).
///
/// Feature data sources read their bearer token via `TokenStorage.getAccessToken()`.
/// Without this, an access token that hit its expiry buffer was simply dropped —
/// `getAccessToken()` returned null, the request went out with no Authorization
/// header, and the backend answered 401 until the app was restarted. The
/// coordinator lets `getAccessToken()` refresh the token in place instead.
///
/// [refresher] is wired once at startup (DI) to the auth repository's refresh.
/// It is left null in tests, where `getAccessToken()` keeps its original
/// clear-and-return-null behavior on expiry (so existing tests are unaffected).
typedef TokenRefresher = Future<bool> Function();

class TokenRefreshCoordinator {
  TokenRefreshCoordinator._();

  /// Wired once during app bootstrap. Returns true when a fresh token was stored.
  static TokenRefresher? refresher;

  static Future<bool>? _inflight;

  /// Run [refresher] at most once concurrently — a burst of requests that all
  /// find the token expired share a single network refresh rather than each
  /// firing their own. Returns false (never throws) when unset or on failure.
  static Future<bool> refresh() {
    final r = refresher;
    if (r == null) return Future.value(false);
    return _inflight ??= _run(r);
  }

  static Future<bool> _run(TokenRefresher r) async {
    try {
      return await r();
    } catch (_) {
      return false;
    } finally {
      _inflight = null;
    }
  }

  /// Test hook: clear the wired refresher + any in-flight attempt between tests.
  static void resetForTest() {
    refresher = null;
    _inflight = null;
  }
}
