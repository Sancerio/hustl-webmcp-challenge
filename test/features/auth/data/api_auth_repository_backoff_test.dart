import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/features/auth/data/repositories/api_auth_repository.dart';
import 'package:hustl_app/features/auth/data/datasources/auth_api.dart';
import 'package:hustl_app/core/services/token_storage.dart' as ts;
import 'package:hustl_app/core/services/preferences_service.dart';

class _FakeTokenStorage implements ts.TokenStorage {
  String? access;
  String? refresh = 'r1';
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
    expiry = null;
  }

  @override
  Future<void> clearAll() async {
    access = null;
    refresh = null;
    expiry = null;
  }
}

class _BackoffAuthApi extends AuthApi {
  int refreshCalls = 0;
  bool failFirst = true;

  @override
  Future<({String accessToken, String? refreshToken, int expiresIn})>
  refreshToken([String? refreshToken]) async {
    refreshCalls += 1;
    if (failFirst) {
      failFirst = false;
      throw Exception('simulate refresh failure');
    }
    return (accessToken: 'a1', refreshToken: refreshToken, expiresIn: 3600);
  }

  @override
  Future<Map<String, dynamic>?> getMe(String token) async {
    return {
      'user': {
        'id': 'u1',
        'provider': 'google',
        'name': 'User',
        'email': 'u@x.com',
        'picture_url': null,
      },
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('backoff prevents repeated refresh attempts after failure', () async {
    final prefs = PreferencesService();
    await prefs.init();
    final tokens = _FakeTokenStorage();
    final api = _BackoffAuthApi();
    final repo = ApiAuthRepository(prefs, api: api, tokens: tokens);

    // First call: attempts refresh and fails
    final r1 = await repo.getCurrentUser();
    expect(r1, isNull);
    expect(api.refreshCalls, 1);

    // Immediate second call: should not attempt refresh due to backoff
    final r2 = await repo.getCurrentUser();
    expect(r2, isNull);
    expect(api.refreshCalls, 1);
  });
}
