import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hustl_app/core/services/token_refresh.dart';
import 'package:hustl_app/core/services/token_storage_web.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('saveTokenPair persists token to SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = TokenStorage();
    await storage.saveTokenPair(
      accessToken: 't123',
      refreshToken: null,
      expiresIn: 3600,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_access_token'), 't123');
  });

  group('getAccessToken refresh-on-expiry', () {
    Future<void> writeExpiredToken() async {
      final prefs = await SharedPreferences.getInstance();
      final past = DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      await prefs.setString('auth_access_token', 'stale');
      await prefs.setInt('auth_token_expiry', past);
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      TokenRefreshCoordinator.resetForTest();
      // Reset the static in-memory cache between tests.
      await TokenStorage().clearAccessToken();
    });
    tearDown(TokenRefreshCoordinator.resetForTest);

    test('refreshes in place and returns the new token instead of null', () async {
      await writeExpiredToken();
      TokenRefreshCoordinator.refresher = () async {
        await TokenStorage().saveTokenPair(
          accessToken: 'fresh',
          refreshToken: null,
          expiresIn: 3600,
        );
        return true;
      };
      expect(await TokenStorage().getAccessToken(), 'fresh');
    });

    test('returns null and clears when refresh fails', () async {
      await writeExpiredToken();
      TokenRefreshCoordinator.refresher = () async => false;
      expect(await TokenStorage().getAccessToken(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_access_token'), isNull);
    });

    test('concurrent callers share a single refresh (single-flight)', () async {
      await writeExpiredToken();
      var calls = 0;
      TokenRefreshCoordinator.refresher = () async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await TokenStorage().saveTokenPair(
          accessToken: 'fresh',
          refreshToken: null,
          expiresIn: 3600,
        );
        return true;
      };
      final results = await Future.wait([
        TokenStorage().getAccessToken(),
        TokenStorage().getAccessToken(),
        TokenStorage().getAccessToken(),
      ]);
      expect(calls, 1);
      expect(results, everyElement('fresh'));
    });

    test('without a wired refresher, keeps the original clear-and-null behavior', () async {
      await writeExpiredToken();
      // refresher stays null (resetForTest)
      expect(await TokenStorage().getAccessToken(), isNull);
    });
  });
}
