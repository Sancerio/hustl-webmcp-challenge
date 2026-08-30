import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/network/http_client.dart';

class AuthApi {
  final http.Client _client;
  final String _base;

  /// Bound every auth network call so sign-in can never hang forever on a
  /// flaky connection. On timeout we surface a friendly, retryable error
  /// instead of leaving the UI stuck in a loading state.
  static const Duration _timeout = Duration(seconds: 20);

  AuthApi({http.Client? client, String? baseUrl})
    : _client = client ?? createHttpClient(),
      _base = baseUrl ?? ApiConfig.authBaseUrl;

  /// Run a network op with a hard timeout, mapping a stall to a structured,
  /// retryable error rather than a hung `Future`.
  Future<http.Response> _send(Future<http.Response> Function() op) async {
    try {
      return await op().timeout(_timeout);
    } on TimeoutException {
      throw AuthApiException(
        status: 0,
        code: 'timeout',
        message:
            'The request timed out. Please check your connection and try again.',
      );
    }
  }

  /// Translate a non-2xx response into a structured [AuthApiException],
  /// preferring the backend's `error.code`/`error.message` and capturing
  /// `Retry-After` for rate limits. Never returns.
  Never _throwForResponse(http.Response res) {
    var code = 'unknown_error';
    var message = 'Something went wrong. Please try again.';
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['error'] is Map) {
        final err = body['error'] as Map;
        code = (err['code'] as String?) ?? code;
        message = (err['message'] as String?) ?? message;
      }
    } catch (_) {
      // Non-JSON body: keep the generic message; the raw body is stashed below.
    }
    Duration? retryAfter;
    if (res.statusCode == 429) {
      if (code == 'unknown_error') code = 'rate_limited';
      final secs = int.tryParse(res.headers['retry-after'] ?? '');
      if (secs != null && secs > 0) retryAfter = Duration(seconds: secs);
    }
    throw AuthApiException(
      status: res.statusCode,
      code: code,
      message: message,
      rawBody: res.body,
      retryAfter: retryAfter,
    );
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? params,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: params);
    final res = await _send(
      () => _client.get(
        uri,
        headers: {'Content-Type': 'application/json', ...?headers},
      ),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    _throwForResponse(res);
  }

  Future<({String authUrl, String stateToken})> getLogin(
    String provider, {
    bool mobile = false,
  }) async {
    final data = await _get(
      '/api/auth/$provider/login',
      params: {if (mobile) 'mobile': 'true'},
    );
    final d = data['data'] as Map<String, dynamic>;
    return (
      authUrl: d['auth_url'] as String,
      stateToken: (d['state_token'] as String?) ?? '',
    );
  }

  Future<
    ({
      String accessToken,
      String? refreshToken,
      int expiresIn,
      Map<String, dynamic> user,
    })
  >
  exchangeCode({
    required String provider,
    required String code,
    required String state,
    String? stateToken,
    bool mobile = false,
  }) async {
    final data = await _get(
      '/api/auth/$provider/callback',
      params: {
        'code': code,
        'state': state,
        if (stateToken != null && stateToken.isNotEmpty)
          'state_token': stateToken,
        if (mobile) 'mobile': 'true',
      },
    );
    final d = data['data'] as Map<String, dynamic>;
    return (
      accessToken: d['accessToken'] as String,
      refreshToken: d['refreshToken'] as String?,
      expiresIn: d['expiresIn'] as int,
      user: d['user'] as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>?> getMe(String token) async {
    final data = await _get(
      '/api/me',
      headers: {'Authorization': 'Bearer $token'},
    );
    return data['data'] as Map<String, dynamic>?;
  }

  Future<({String accessToken, String? refreshToken, int expiresIn})>
  refreshToken([String? refreshToken]) async {
    final uri = Uri.parse('$_base/api/auth/refresh');
    final res = await _send(
      () => refreshToken == null
          // Web: rely on HttpOnly cookie
          ? _client.post(uri, headers: {'Content-Type': 'application/json'})
          : _client.post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'refreshToken': refreshToken}),
            ),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final d = data['data'] as Map<String, dynamic>;
      return (
        accessToken: d['accessToken'] as String,
        refreshToken: d['refreshToken'] as String?,
        expiresIn: d['expiresIn'] as int,
      );
    }
    _throwForResponse(res);
  }

  Future<
    ({
      String accessToken,
      String? refreshToken,
      int expiresIn,
      Map<String, dynamic> user,
    })
  >
  nativeGoogleSignIn({required String idToken}) async {
    final uri = Uri.parse('$_base/api/auth/google/native');
    final res = await _send(
      () => _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id_token': idToken}),
      ),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final d = data['data'] as Map<String, dynamic>;
      return (
        accessToken: d['accessToken'] as String,
        refreshToken: d['refreshToken'] as String?,
        expiresIn: d['expiresIn'] as int,
        user: d['user'] as Map<String, dynamic>,
      );
    }
    _throwForResponse(res);
  }

  /// Exchanges an Apple identity token for app tokens via the backend's native
  /// Apple sign-in endpoint. Returns the same token+user shape as Google native.
  Future<
    ({
      String accessToken,
      String? refreshToken,
      int expiresIn,
      Map<String, dynamic> user,
    })
  >
  nativeAppleSignIn({
    required String identityToken,
    required String rawNonce,
    String? fullName,
  }) async {
    final uri = Uri.parse('$_base/api/auth/apple/native');
    final res = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'identityToken': identityToken,
        'rawNonce': rawNonce,
        if (fullName != null && fullName.isNotEmpty) 'fullName': fullName,
      }),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final d = data['data'] as Map<String, dynamic>;
      return (
        accessToken: d['accessToken'] as String,
        refreshToken: d['refreshToken'] as String?,
        expiresIn: d['expiresIn'] as int,
        user: d['user'] as Map<String, dynamic>,
      );
    }
    throw Exception(
      'Native Apple sign-in failed: ${res.statusCode} ${res.body}',
    );
  }

  /// Revokes the current session server-side so the refresh token can no longer
  /// mint new access tokens. Best-effort: any 2xx is success, and any error
  /// (network, non-2xx) is swallowed so a failed call never blocks local
  /// sign-out. Sends the stored [refreshToken] in the body when available, and
  /// omits Authorization when only a refresh-token/cookie-backed session remains.
  Future<void> logout(String? accessToken, [String? refreshToken]) async {
    try {
      final uri = Uri.parse('$_base/api/auth/logout');
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (accessToken != null && accessToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $accessToken';
      }
      await _client.post(
        uri,
        headers: headers,
        body: (refreshToken != null && refreshToken.isNotEmpty)
            ? jsonEncode({'refreshToken': refreshToken})
            : null,
      );
    } catch (_) {
      // Best-effort: swallow errors so local sign-out always proceeds.
    }
  }

  /// Permanently deletes the authenticated account. Idempotent on the server:
  /// any 2xx response is treated as success. Non-2xx maps to [AuthApiException].
  Future<void> deleteAccount(String accessToken) async {
    final uri = Uri.parse('$_base/api/account/delete');
    final res = await _client.delete(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return;
    }
    // Surface a structured backend error when one is present.
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == false) {
        final err = body['error'] as Map<String, dynamic>?;
        throw AuthApiException(
          status: res.statusCode,
          code: (err?['code'] as String?) ?? 'unknown_error',
          message: (err?['message'] as String?) ?? 'Account deletion failed',
          rawBody: res.body,
        );
      }
    } on AuthApiException {
      rethrow;
    } catch (_) {
      // Fall through to generic error when body is not structured JSON.
    }
    throw AuthApiException(
      status: res.statusCode,
      code: 'unknown_error',
      message: 'Account deletion failed',
      rawBody: res.body,
    );
  }
}

/// Structured API error for AuthApi methods that need to surface a backend code.
class AuthApiException implements Exception {
  final int status;
  final String code;
  final String message;
  final String? rawBody;

  /// Populated for HTTP 429 responses that carry a `Retry-After` header.
  final Duration? retryAfter;

  AuthApiException({
    required this.status,
    required this.code,
    required this.message,
    this.rawBody,
    this.retryAfter,
  });
  @override
  String toString() =>
      'AuthApiException(status=$status, code=$code, message=$message)';
}
