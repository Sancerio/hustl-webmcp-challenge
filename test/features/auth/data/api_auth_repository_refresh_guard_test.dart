import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hustl_app/features/auth/data/datasources/auth_api.dart';
import 'package:hustl_app/features/auth/data/repositories/api_auth_repository.dart';
import 'package:hustl_app/core/services/token_storage.dart' as ts;
import 'package:hustl_app/core/services/preferences_service.dart';

// Fakes for TokenStorage and AuthApi to verify refresh guard behavior.

class _FakeTokenStorage implements ts.TokenStorage {
  String? access;
  String? refresh;
  int? expiry;

  @override
  Future<String?> getAccessToken() async => access;

  @override
  Future<String?> getRefreshToken() async => refresh;

  @override
  Future<void> saveTokenPair({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
  }) async {
    access = accessToken;
    refresh = refreshToken;
    expiry = DateTime.now()
        .add(Duration(seconds: expiresIn))
        .millisecondsSinceEpoch;
  }

  @override
  Future<void> clearAccessToken() async {
    access = null;
  }

  @override
  Future<void> clearAll() async {
    access = null;
    refresh = null;
    expiry = null;
  }
}

class _FakeAuthApi extends AuthApi {
  _FakeAuthApi();

  int refreshCalls = 0;
  String? lastRefreshToken;
  Exception? refreshError;

  @override
  Future<({String accessToken, String? refreshToken, int expiresIn})>
  refreshToken([String? refreshToken]) async {
    refreshCalls += 1;
    lastRefreshToken = refreshToken;
    if (refreshError != null) {
      throw refreshError!;
    }
    return (
      accessToken: 'new_access',
      refreshToken: refreshToken,
      expiresIn: 3600,
    );
  }

  @override
  Future<Map<String, dynamic>?> getMe(String token) async {
    // Return the inner data payload, since AuthApi.getMe returns data['data']
    return {
      'user': {
        'id': 'u1',
        'provider': 'google',
        'name': 'Test User',
        'email': 'test@example.com',
        'picture_url': null,
      },
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Ensure shared_preferences has a mock store available
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  group('ApiAuthRepository refresh guard (native path)', () {
    test('does not call refresh when no stored refresh token', () async {
      final prefs = PreferencesService();
      await prefs.init();
      final tokens = _FakeTokenStorage();
      final api = _FakeAuthApi();

      final repo = ApiAuthRepository(prefs, api: api, tokens: tokens);
      // Reset static backoff/state between tests
      await repo.signOut();
      final user = await repo.getCurrentUser();

      expect(user, isNull);
      expect(api.refreshCalls, 0);
    });

    test('calls refresh with stored refresh token when present', () async {
      final prefs = PreferencesService();
      await prefs.init();
      final tokens = _FakeTokenStorage();
      final api = _FakeAuthApi();

      final repo = ApiAuthRepository(prefs, api: api, tokens: tokens);
      await repo.signOut();
      tokens.refresh = 'r1';
      final user = await repo.getCurrentUser();

      expect(user, isNotNull);
      expect(api.refreshCalls, 1);
      expect(api.lastRefreshToken, 'r1');
    });

    test('keeps refresh token on transient refresh failure', () async {
      final prefs = PreferencesService();
      await prefs.init();
      final tokens = _FakeTokenStorage();

      // Fake API that throws a non-invalid_refresh error
      final api = _FakeAuthApi()
        ..refreshCalls = 0
        ..refreshError = AuthApiException(
          status: 503,
          code: 'network_error',
          message: 'temporary',
        );

      final repo = ApiAuthRepository(prefs, api: api, tokens: tokens);
      await repo.signOut();
      tokens.refresh = 'r1';
      final user = await repo.getCurrentUser();

      expect(user, isNull);
      expect(api.refreshCalls, 1);
      expect(tokens.refresh, 'r1', reason: 'refresh token should be preserved');
    });

    test('clears all tokens on invalid_refresh', () async {
      final prefs = PreferencesService();
      await prefs.init();
      // Simulate expired access token so that refresh path is executed
      final tokens = _FakeTokenStorage();

      // Fake API that throws invalid_refresh
      final api = _FakeAuthApi()
        ..refreshError = AuthApiException(
          status: 401,
          code: 'invalid_refresh',
          message: 'expired',
        );

      final repo = ApiAuthRepository(prefs, api: api, tokens: tokens);
      await repo.signOut();
      tokens.refresh = 'r1';
      final user = await repo.getCurrentUser();

      expect(user, isNull);
      expect(tokens.refresh, isNull, reason: 'refresh token should be cleared');
      expect(tokens.access, isNull, reason: 'access token should be cleared');
    });
  });
}
