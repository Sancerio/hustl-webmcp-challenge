import 'dart:async';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, kDebugMode;
import 'package:flutter/services.dart' show PlatformException;
import 'package:url_launcher/url_launcher.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../../core/web/platform_redirect.dart';
import '../../../../core/services/deep_link_service.dart';
import '../../../../core/config/api_config.dart';

import '../../../../core/services/preferences_service.dart';
import '../../../../core/services/token_storage.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import 'package:hustl_app/features/auth/data/datasources/auth_api.dart';
import '../../errors/auth_exception.dart';
import '../../errors/google_sign_in_error.dart';

class ApiAuthRepository implements AuthRepository {
  final AuthApi _api;
  final TokenStorage _tokens;
  final PreferencesService _prefs;
  final DeepLinkService _deepLinkService;

  // In-memory refresh backoff to avoid spamming the backend on failures
  static Duration _refreshBackoff = Duration.zero; // grows up to _maxBackoff
  static DateTime? _nextRefreshAllowedAt;
  static const Duration _initialBackoff = Duration(seconds: 30);
  static const Duration _maxBackoff = Duration(minutes: 5);

  /// Single source of truth for the support contact surfaced in auth errors,
  /// so the (previously three) hand-copied call sites can't drift.
  static const String supportEmail = 'support@hustl.app';
  static const String _emailNotVerifiedMessage =
      'Your email isn\'t verified with this provider. '
      'Please contact support at $supportEmail to link your account.';

  ApiAuthRepository(
    this._prefs, {
    AuthApi? api,
    TokenStorage? tokens,
    DeepLinkService? deepLinkService,
  }) : _api = api ?? AuthApi(),
       _tokens = tokens ?? TokenStorage(),
       _deepLinkService = deepLinkService ?? DeepLinkService();

  @override
  Future<AuthUser?> getCurrentUser() async {
    // Try access token first
    final access = await _tokens.getAccessToken();
    if (access != null) {
      try {
        final data = await _api.getMe(access);
        final u = data?['user'] as Map<String, dynamic>?;
        if (u == null) return null;
        return AuthUser(
          id: u['id'] as String,
          provider: _providerFromString(u['provider'] as String?),
          displayName: u['name'] as String?,
          email: u['email'] as String?,
          photoUrl: u['picture_url'] as String?,
        );
      } catch (_) {
        /* fallthrough to refresh */
      }
    }

    // Attempt refresh: on web only when we know a session likely exists (hint flag),
    // and on native only if we have a stored refresh token
    final storedRefresh = await _tokens.getRefreshToken();
    try {
      // On web, rely on HttpOnly cookie but avoid calling if we never had a session
      if (kIsWeb) {
        final hasWebSession = await _prefs.getHasWebSession();
        if (!hasWebSession) {
          await _tokens.clearAll();
          return null;
        }
      }
      // Respect backoff window if set
      if (_nextRefreshAllowedAt != null &&
          DateTime.now().isBefore(_nextRefreshAllowedAt!)) {
        return null;
      }
      // On native, require a stored refresh token
      if (!kIsWeb && (storedRefresh == null || storedRefresh.isEmpty)) {
        await _tokens.clearAll();
        return null;
      }
      final refreshed = await _api.refreshToken(kIsWeb ? null : storedRefresh);
      await _tokens.saveTokenPair(
        accessToken: refreshed.accessToken,
        refreshToken: refreshed.refreshToken, // null on web
        expiresIn: refreshed.expiresIn,
      );
      // On web, mark that we have a valid refresh-backed session
      if (kIsWeb) {
        await _prefs.setHasWebSession(true);
      }
      // Reset backoff on success
      _refreshBackoff = Duration.zero;
      _nextRefreshAllowedAt = null;
      final data = await _api.getMe(refreshed.accessToken);
      final u = data?['user'] as Map<String, dynamic>?;
      if (u == null) return null;
      return AuthUser(
        id: u['id'] as String,
        provider: _providerFromString(u['provider'] as String?),
        displayName: u['name'] as String?,
        email: u['email'] as String?,
        photoUrl: u['picture_url'] as String?,
      );
    } catch (e) {
      _scheduleRefreshBackoff();
      // Only clear the refresh token when it's truly invalid/expired.
      // For transient failures (network, 5xx), keep the refresh token so we can recover later.
      final isInvalidRefresh =
          (e is AuthApiException && e.code == 'invalid_refresh')
          // Be defensive about library identity or wrapped errors
          ||
          e.toString().contains('invalid_refresh');
      if (isInvalidRefresh) {
        await _tokens.clearAll();
      } else {
        await _tokens.clearAccessToken();
      }
      return null;
    }
  }

  /// Refresh the access token in place (no user fetch) and persist the new pair.
  /// Wired into [TokenRefreshCoordinator] so a feature data source's
  /// `getAccessToken()` self-heals on expiry instead of dropping the bearer
  /// header. Shares the same web-cookie/native-token gating, backoff, and
  /// invalid-refresh handling as [getCurrentUser]. Returns true on success.
  Future<bool> ensureFreshToken() async {
    final storedRefresh = await _tokens.getRefreshToken();
    try {
      if (kIsWeb) {
        final hasWebSession = await _prefs.getHasWebSession();
        if (!hasWebSession) {
          await _tokens.clearAll();
          return false;
        }
      }
      if (_nextRefreshAllowedAt != null &&
          DateTime.now().isBefore(_nextRefreshAllowedAt!)) {
        return false;
      }
      if (!kIsWeb && (storedRefresh == null || storedRefresh.isEmpty)) {
        await _tokens.clearAll();
        return false;
      }
      final refreshed = await _api.refreshToken(kIsWeb ? null : storedRefresh);
      await _tokens.saveTokenPair(
        accessToken: refreshed.accessToken,
        refreshToken: refreshed.refreshToken, // null on web
        expiresIn: refreshed.expiresIn,
      );
      if (kIsWeb) {
        await _prefs.setHasWebSession(true);
      }
      _refreshBackoff = Duration.zero;
      _nextRefreshAllowedAt = null;
      return true;
    } catch (e) {
      _scheduleRefreshBackoff();
      final isInvalidRefresh =
          (e is AuthApiException && e.code == 'invalid_refresh') ||
          e.toString().contains('invalid_refresh');
      if (isInvalidRefresh) {
        await _tokens.clearAll();
      } else {
        await _tokens.clearAccessToken();
      }
      return false;
    }
  }

  @override
  Future<AuthUser> signInWithGoogle() => _launchOAuth('google');

  @override
  Future<AuthUser> signInWithApple({
    required String identityToken,
    required String rawNonce,
    String? fullName,
  }) async {
    try {
      final result = await _api.nativeAppleSignIn(
        identityToken: identityToken,
        rawNonce: rawNonce,
        fullName: fullName,
      );
      await _tokens.saveTokenPair(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        expiresIn: result.expiresIn,
      );
      final u = result.user;
      return AuthUser(
        id: u['id'] as String,
        provider: _providerFromString(u['provider'] as String?),
        displayName: u['name'] as String?,
        email: u['email'] as String?,
        photoUrl: u['picture_url'] as String?,
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(
        'Apple sign-in failed. Please try again.',
        details: kDebugMode ? e.toString() : null,
      );
    }
  }

  Future<AuthUser> _launchOAuth(String provider) async {
    // Use native Google Sign-In on mobile to avoid redirect issues
    if (!kIsWeb && provider == 'google') {
      try {
        // Use the google_sign_in plugin
        // Use explicit iOS client ID when provided
        final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
        if (isIOS && ApiConfig.googleIosClientId.isEmpty) {
          // Provide a clear message and, in debug, a developer hint
          final hint = _iosConfigHint();
          throw AuthException(
            'Google sign-in is not configured on this device. Please try again later.',
            details: kDebugMode ? hint : null,
          );
        }

        if (ApiConfig.googleWebClientId.isEmpty) {
          // Provide a clear message and, in debug, a developer hint
          final hint = _webConfigHint();
          throw AuthException(
            'Google sign-in is not configured on this device. Please try again later.',
            details: kDebugMode ? hint : null,
          );
        }
        final googleSignIn = GoogleSignIn(
          clientId: isIOS ? ApiConfig.googleIosClientId : null,
          serverClientId: ApiConfig.googleWebClientId.isNotEmpty
              ? ApiConfig.googleWebClientId
              : null,
          scopes: ['email', 'profile'],
        );
        final account = await googleSignIn.signIn();
        if (account == null) {
          throw AuthCancelledException();
        }
        final auth = await account.authentication;
        final idToken = auth.idToken;
        if (idToken == null) {
          // Surface a human message; keep the technical reason for debug only.
          throw AuthException(
            'We couldn\'t finish Google sign-in. Please try again.',
            details: 'Missing ID token from Google.',
          );
        }
        final result = await _api.nativeGoogleSignIn(idToken: idToken);
        await _tokens.saveTokenPair(
          accessToken: result.accessToken,
          refreshToken: result.refreshToken,
          expiresIn: result.expiresIn,
        );
        final u = result.user;
        return AuthUser(
          id: u['id'] as String,
          provider: _providerFromString(u['provider'] as String?),
          displayName: u['name'] as String?,
          email: u['email'] as String?,
          photoUrl: u['picture_url'] as String?,
        );
      } catch (e) {
        // Already a clean cancel signal — don't re-wrap it as a generic failure.
        if (e is AuthCancelledException) rethrow;
        // The plugin can also report a cancel as a PlatformException instead of
        // a null account (seen on some Android/iOS versions).
        if (e is PlatformException &&
            (e.code == 'sign_in_canceled' || e.code == 'canceled')) {
          throw AuthCancelledException();
        }
        // Provide a friendlier error for common native issues and add developer hints in debug
        final message = _friendlyGoogleNativeError(e);
        throw AuthException(message, details: kDebugMode ? e.toString() : null);
      }
    }

    late final ({String authUrl, String stateToken}) login;
    try {
      login = await _api.getLogin(provider, mobile: !kIsWeb);
    } catch (e) {
      throw AuthException(
        'Could not start $provider sign-in. Please try again.',
        details: e.toString(),
      );
    }

    // Web: redirect to provider URL, flow will resume on /auth/.../callback
    if (kIsWeb) {
      // Redirect the browser directly (avoids url_launcher issues on web)
      webRedirectTo(login.authUrl);
      // Return a never-completing Future to keep Bloc in loading until navigation happens
      return Completer<AuthUser>().future;
    }

    // For mobile, set up deep link listener and launch OAuth URL
    try {
      // Parse state from auth URL for deep link matching
      final uri = Uri.parse(login.authUrl);
      final state = uri.queryParameters['state'];
      if (state == null) {
        throw AuthException('Could not start sign-in. Please try again.');
      }

      // Start listening for the OAuth callback deep link
      final callbackFuture = _deepLinkService.waitForOAuthCallback(
        provider: provider,
        state: state,
      );

      // Launch the OAuth URL in external browser
      final ok = await launchUrl(
        Uri.parse(login.authUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        throw AuthException('Could not open $provider sign-in');
      }

      // Wait for the deep link callback
      final callbackParams = await callbackFuture;

      // Exchange the code for tokens
      final result = await _api.exchangeCode(
        provider: provider,
        code: callbackParams['code']!,
        state: callbackParams['state']!,
        stateToken: login.stateToken.isNotEmpty ? login.stateToken : null,
        mobile: true,
      );

      // Store tokens
      await _tokens.saveTokenPair(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        expiresIn: result.expiresIn,
      );

      // Return the authenticated user
      final u = result.user;
      return AuthUser(
        id: u['id'] as String,
        provider: _providerFromString(u['provider'] as String?),
        displayName: u['name'] as String?,
        email: u['email'] as String?,
        photoUrl: u['picture_url'] as String?,
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      if (e is AuthApiException) {
        throw AuthException(_friendlyAuthApiError(e), details: e.toString());
      }
      throw AuthException(
        'Sign-in failed. Please try again.',
        details: e.toString(),
      );
    }
  }

  // Called by the Flutter web callback screen after redirect
  Future<AuthUser> completeOAuthOnWeb({
    required String provider,
    required String code,
    required String state,
    String? stateToken,
  }) async {
    late final ({
      String accessToken,
      String? refreshToken,
      int expiresIn,
      Map<String, dynamic> user,
    })
    result;
    try {
      result = await _api.exchangeCode(
        provider: provider,
        code: code,
        state: state,
        stateToken: stateToken,
      );
    } catch (e) {
      if (e is AuthApiException) {
        throw AuthException(_friendlyAuthApiError(e), details: e.toString());
      }
      throw AuthException(
        'Could not complete sign-in. Please try again.',
        details: e.toString(),
      );
    }
    await _tokens.saveTokenPair(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken, // null on web (cookie-based)
      expiresIn: result.expiresIn,
    );
    // Mark that we have a valid cookie-backed session on web
    await _prefs.setHasWebSession(true);
    final u = result.user;
    final authUser = AuthUser(
      id: u['id'] as String,
      provider: _providerFromString(u['provider'] as String?),
      displayName: u['name'] as String?,
      email: u['email'] as String?,
      photoUrl: u['picture_url'] as String?,
    );
    await _prefs.setAuthUserJson(''); // Clear legacy path, optional
    return authUser;
  }

  @override
  Future<void> signOut() async {
    // Best-effort server-side revocation of the refresh token before we drop
    // local state. A failed/absent network call must never block sign-out.
    final access = await _tokens.getAccessToken();
    final refresh = await _tokens.getRefreshToken();
    final hasWebSession = await _prefs.getHasWebSession();
    if ((access != null && access.isNotEmpty) ||
        (refresh != null && refresh.isNotEmpty) ||
        hasWebSession) {
      try {
        await _api.logout(access, refresh);
      } catch (_) {
        // Proceed with local sign-out regardless of server outcome.
      }
    }
    await _tokens.clearAll();
    await _prefs.clearAuthUser();
    await _prefs.setHasWebSession(false);
    _refreshBackoff = Duration.zero;
    _nextRefreshAllowedAt = null;
  }

  @override
  Future<void> deleteAccount() async {
    final access = await _tokens.getAccessToken();
    if (access == null || access.isEmpty) {
      throw AuthException('You are not signed in.');
    }
    try {
      await _api.deleteAccount(access);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(
        'Could not delete your account. Please try again.',
        details: kDebugMode ? e.toString() : null,
      );
    }
    // Server-side deletion succeeded (or was already deleted) — clear the local
    // session exactly like signOut() so the app returns to unauthenticated.
    await signOut();
  }

  AuthProvider _providerFromString(String? s) {
    switch (s) {
      case 'google':
        return AuthProvider.google;
      case 'apple':
        return AuthProvider.apple;
      default:
        return AuthProvider.guest;
    }
  }

  /// Maps a structured backend [AuthApiException] to recoverable user copy,
  /// reused by the native, deep-link, and web sign-in paths.
  String _friendlyAuthApiError(AuthApiException e) {
    switch (e.code) {
      case 'email_not_verified':
        return _emailNotVerifiedMessage;
      case 'rate_limited':
        final secs = e.retryAfter?.inSeconds;
        return secs != null
            ? 'Too many attempts. Please wait ${secs}s and try again.'
            : 'Too many attempts. Please wait a moment and try again.';
      case 'timeout':
        return 'The request timed out. Please check your connection and try again.';
      default:
        return e.message.isNotEmpty
            ? e.message
            : 'Sign-in failed. Please try again.';
    }
  }

  String _friendlyGoogleNativeError(Object e) {
    if (e is AuthException) return e.message;
    if (e is AuthApiException) return _friendlyAuthApiError(e);
    if (e is PlatformException) {
      // On Android the actionable GMS status hides in the message, not e.code.
      // DEVELOPER_ERROR (10) is deterministic config — the build's signing SHA-1
      // + package aren't registered on the com.hustl.app Android OAuth client
      // (e.g. a debug-signed local build). Surface it instead of a vague retry.
      if (googleApiExceptionCode(e) == GoogleApiStatus.developerError) {
        return kDebugMode
            ? 'Google sign-in is not authorized for this build (ApiException 10 / '
                  'DEVELOPER_ERROR). Register this build’s SHA-1 on the com.hustl.app '
                  'Android OAuth client, or sign with the registered release keystore.'
            : 'Google sign-in isn’t available on this build. Please try again later.';
      }
      switch (e.code) {
        case 'network_error':
          return 'Network error during Google sign-in. Please check your connection and try again.';
        // 'sign_in_canceled' / 'canceled' are handled as AuthCancelledException
        // before this helper is reached — see the catch block above.
        case 'sign_in_failed':
          return 'Google sign-in failed. Please try again.';
        default:
          return 'Google sign-in failed. Please try again.';
      }
    }
    // Generic fallback; in debug, developer hint is included via details
    return 'Google sign-in failed. Please try again.';
  }

  String _iosConfigHint() {
    return 'Missing GOOGLE_IOS_CLIENT_ID dart-define or URL scheme. '
        'Pass --dart-define=GOOGLE_IOS_CLIENT_ID=<client id> and ensure Info.plist CFBundleURLSchemes '
        'includes com.googleusercontent.apps.<client-id-suffix>.';
  }

  String _webConfigHint() {
    return 'Missing GOOGLE_WEB_CLIENT_ID dart-define. '
        'Pass --dart-define=GOOGLE_WEB_CLIENT_ID=<web-client-id> with your web OAuth client ID from Google Console.';
  }
}

void _scheduleRefreshBackoff() {
  if (ApiAuthRepository._refreshBackoff == Duration.zero) {
    ApiAuthRepository._refreshBackoff = ApiAuthRepository._initialBackoff;
  } else {
    final doubled = ApiAuthRepository._refreshBackoff * 2;
    ApiAuthRepository._refreshBackoff = doubled > ApiAuthRepository._maxBackoff
        ? ApiAuthRepository._maxBackoff
        : doubled;
  }
  ApiAuthRepository._nextRefreshAllowedAt = DateTime.now().add(
    ApiAuthRepository._refreshBackoff,
  );
}
