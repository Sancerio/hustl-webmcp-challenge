import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/token_refresh.dart';
import 'package:hustl_app/core/services/token_storage_io.dart' as io;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureStore = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        switch (call.method) {
          case 'write':
            secureStore[call.arguments['key'] as String] =
                call.arguments['value'] as String? ?? '';
            return true;
          case 'read':
            return secureStore[call.arguments['key'] as String];
          case 'delete':
            secureStore.remove(call.arguments['key'] as String);
            return true;
          case 'readAll':
            return secureStore;
          case 'deleteAll':
            secureStore.clear();
            return true;
          case 'containsKey':
            return secureStore.containsKey(call.arguments['key'] as String);
        }
        return null;
      });

  test(
    'TokenStorage IO returns cached token without re-reading storage',
    () async {
      final storage = io.TokenStorage();
      await storage.saveTokenPair(
        accessToken: 'tok',
        refreshToken: 'r',
        expiresIn: 3600,
      );

      // First read populates cache
      final t1 = await storage.getAccessToken();
      expect(t1, 'tok');

      // Simulate storage loss (secure storage cleared) — cache should still serve
      secureStore.clear();

      final t2 = await storage.getAccessToken();
      expect(t2, 'tok');
    },
  );

  test(
    'TokenStorage IO refreshes on expiry instead of returning null',
    () async {
      TokenRefreshCoordinator.resetForTest();
      await io.TokenStorage().clearAccessToken();
      final prefs = await SharedPreferences.getInstance();
      final past = DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      await prefs.setString('auth_access_token', 'stale');
      await prefs.setInt('auth_token_expiry', past);
      TokenRefreshCoordinator.refresher = () async {
        await io.TokenStorage().saveTokenPair(
          accessToken: 'fresh',
          refreshToken: 'r',
          expiresIn: 3600,
        );
        return true;
      };
      expect(await io.TokenStorage().getAccessToken(), 'fresh');
      TokenRefreshCoordinator.resetForTest();
    },
  );
}
