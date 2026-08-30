import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/features/auth/data/datasources/auth_api.dart';
import 'package:hustl_app/features/auth/data/repositories/api_auth_repository.dart';
import 'package:hustl_app/core/services/token_storage.dart' as ts;
import 'package:hustl_app/core/services/preferences_service.dart';

/// Records calls and lets us assert ordering relative to the API logout call.
class _FakeTokenStorage implements ts.TokenStorage {
  String? access;
  String? refresh;
  final List<String> events;

  _FakeTokenStorage(this.events, {this.access, this.refresh});

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
  }

  @override
  Future<void> clearAccessToken() async {
    access = null;
  }

  @override
  Future<void> clearAll() async {
    events.add('clearAll');
    access = null;
    refresh = null;
  }
}

class _FakeAuthApi extends AuthApi {
  final List<String> events;
  String? lastAccessToken;
  String? lastRefreshToken;
  bool throwOnLogout;

  _FakeAuthApi(this.events, {this.throwOnLogout = false});

  @override
  Future<void> logout(String? accessToken, [String? refreshToken]) async {
    events.add('logout');
    lastAccessToken = accessToken;
    lastRefreshToken = refreshToken;
    if (throwOnLogout) {
      throw Exception('network down');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});

  group('ApiAuthRepository.signOut server-side logout', () {
    test('calls logout with stored tokens, then clears local state', () async {
      final prefs = PreferencesService();
      await prefs.init();
      final events = <String>[];
      final tokens = _FakeTokenStorage(events, access: 'a1', refresh: 'r1');
      final api = _FakeAuthApi(events);
      final repo = ApiAuthRepository(prefs, api: api, tokens: tokens);

      await repo.signOut();

      // logout is invoked before local tokens are cleared.
      expect(events, ['logout', 'clearAll']);
      expect(api.lastAccessToken, 'a1');
      expect(api.lastRefreshToken, 'r1');
      // Local session is cleared.
      expect(tokens.access, isNull);
      expect(tokens.refresh, isNull);
      expect(await prefs.getHasWebSession(), false);
    });

    test('clears local state even when logout throws', () async {
      final prefs = PreferencesService();
      await prefs.init();
      final events = <String>[];
      final tokens = _FakeTokenStorage(events, access: 'a1', refresh: 'r1');
      final api = _FakeAuthApi(events, throwOnLogout: true);
      final repo = ApiAuthRepository(prefs, api: api, tokens: tokens);

      await repo.signOut();

      expect(events, ['logout', 'clearAll']);
      expect(tokens.access, isNull);
      expect(tokens.refresh, isNull);
    });

    test('calls logout when only a refresh token remains', () async {
      final prefs = PreferencesService();
      await prefs.init();
      final events = <String>[];
      final tokens = _FakeTokenStorage(events, refresh: 'r1');
      final api = _FakeAuthApi(events);
      final repo = ApiAuthRepository(prefs, api: api, tokens: tokens);

      await repo.signOut();

      expect(events, ['logout', 'clearAll']);
      expect(api.lastAccessToken, isNull);
      expect(api.lastRefreshToken, 'r1');
      expect(tokens.refresh, isNull);
    });

    test('calls logout when only a web cookie session is known', () async {
      final prefs = PreferencesService();
      await prefs.init();
      await prefs.setHasWebSession(true);
      final events = <String>[];
      final tokens = _FakeTokenStorage(events);
      final api = _FakeAuthApi(events);
      final repo = ApiAuthRepository(prefs, api: api, tokens: tokens);

      await repo.signOut();

      expect(events, ['logout', 'clearAll']);
      expect(api.lastAccessToken, isNull);
      expect(api.lastRefreshToken, isNull);
      expect(await prefs.getHasWebSession(), false);
    });

    test('skips logout when there is no local or web session hint', () async {
      final prefs = PreferencesService();
      await prefs.init();
      final events = <String>[];
      final tokens = _FakeTokenStorage(events);
      final api = _FakeAuthApi(events);
      final repo = ApiAuthRepository(prefs, api: api, tokens: tokens);

      await repo.signOut();

      expect(events, ['clearAll']);
      expect(api.lastAccessToken, isNull);
    });
  });
}
