import 'dart:async';
import 'dart:developer' as dev;
import 'package:app_links/app_links.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  final Map<String, Completer<Map<String, String>>> _pendingOAuthRequests = {};
  void Function(Uri uri)? _onNonAuthLink;

  Future<void> initialize({void Function(Uri uri)? onNonAuthLink}) async {
    _onNonAuthLink = onNonAuthLink;
    // Handle app launched from a deep link (cold start)
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      _handleIncomingLink(initialUri, fromColdStart: true);
    }

    // Handle app opened from a deep link (warm start)
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) => _handleIncomingLink(uri, fromColdStart: false),
      onError: (err) {
        dev.log('Deep link error: $err');
      },
    );
  }

  void dispose() {
    _linkSubscription?.cancel();
    _onNonAuthLink = null;
    // Complete any pending requests with errors
    for (final completer in _pendingOAuthRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError('Deep link service disposed');
      }
    }
    _pendingOAuthRequests.clear();
  }

  Future<Map<String, String>> waitForOAuthCallback({
    required String provider,
    required String state,
  }) async {
    // Create a completer for this OAuth request
    final completer = Completer<Map<String, String>>();
    _pendingOAuthRequests[state] = completer;

    // Set up a timeout to prevent hanging forever
    Timer(const Duration(minutes: 5), () {
      if (!completer.isCompleted) {
        _pendingOAuthRequests.remove(state);
        completer.completeError('OAuth callback timeout');
      }
    });

    return completer.future;
  }

  void _handleIncomingLink(Uri uri, {required bool fromColdStart}) {
    dev.log('Received deep link: $uri');

    // Support both custom-scheme (e.g., hustl://auth/google/callback) and
    // path-based (e.g., https://example.com/auth/google/callback) variants.
    final segments = uri.pathSegments;

    // Case 1: custom scheme where host is 'auth' and path is '/<provider>/callback'
    final isCustomSchemeAuthHost =
        (uri.host == 'auth' &&
        segments.length >= 2 &&
        segments.last == 'callback');

    // Case 2: path-based '/auth/<provider>/callback' regardless of host
    final isPathBasedAuth =
        (segments.length >= 3 &&
        segments.first == 'auth' &&
        segments.last == 'callback');

    if (isCustomSchemeAuthHost || isPathBasedAuth) {
      _handleOAuthCallback(uri);
      return;
    }

    // Forward non-auth links to the app regardless of launch state; callers can
    // decide when navigation is safe (e.g., by posting frame callbacks).
    if (_onNonAuthLink != null) {
      _onNonAuthLink!(uri);
    }
  }

  void _handleOAuthCallback(Uri uri) {
    final queryParams = uri.queryParameters;
    final state = queryParams['state'];
    final code = queryParams['code'];
    final error = queryParams['error'];

    if (state == null) {
      dev.log('OAuth callback missing state parameter');
      return;
    }

    final completer = _pendingOAuthRequests.remove(state);
    if (completer == null) {
      dev.log('No pending OAuth request for state: $state');
      return;
    }

    if (error != null) {
      completer.completeError('OAuth error: $error');
      return;
    }

    if (code == null) {
      completer.completeError('OAuth callback missing code parameter');
      return;
    }

    // Complete the OAuth request with the callback parameters
    completer.complete({'code': code, 'state': state, ...queryParams});
  }
}
