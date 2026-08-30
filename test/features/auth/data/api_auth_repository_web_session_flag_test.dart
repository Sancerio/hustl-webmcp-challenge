import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/features/auth/data/repositories/api_auth_repository.dart';
import 'package:hustl_app/features/auth/data/datasources/auth_api.dart';
import 'package:hustl_app/core/services/token_storage.dart' as ts;
import 'package:hustl_app/core/services/preferences_service.dart';

class _FakeTokenStorage implements ts.TokenStorage {
  @override
  Future<String?> getAccessToken() async => null;
  @override
  Future<String?> getRefreshToken() async => null;
  @override
  Future<void> saveTokenPair({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
  }) async {}
  @override
  Future<void> clearAccessToken() async {}
  @override
  Future<void> clearAll() async {}
}

class _FakeAuthApi extends AuthApi {
  @override
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
    return (
      accessToken: 'a1',
      refreshToken: null,
      expiresIn: 3600,
      user: {
        'id': 'u1',
        'provider': 'google',
        'name': 'User',
        'email': 'u@x.com',
        'picture_url': null,
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('completeOAuthOnWeb marks web session flag', () async {
    final prefs = PreferencesService();
    await prefs.init();
    final repo = ApiAuthRepository(
      prefs,
      api: _FakeAuthApi(),
      tokens: _FakeTokenStorage(),
    );

    expect(await prefs.getHasWebSession(), false);
    await repo.completeOAuthOnWeb(provider: 'google', code: 'c', state: 's');
    expect(await prefs.getHasWebSession(), true);
  });

  test('signOut resets web session flag', () async {
    final prefs = PreferencesService();
    await prefs.init();
    final repo = ApiAuthRepository(
      prefs,
      api: _FakeAuthApi(),
      tokens: _FakeTokenStorage(),
    );

    await prefs.setHasWebSession(true);
    await repo.signOut();
    expect(await prefs.getHasWebSession(), false);
  });
}
