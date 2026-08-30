import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hustl_app/core/services/preferences_service.dart';

void main() {
  test(
    'seenHealthConnectPrimer defaults false and persists once set',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService();
      prefs.resetForTests();
      await prefs.init();

      expect(prefs.seenHealthConnectPrimer, isFalse);
      await prefs.setSeenHealthConnectPrimer(true);
      expect(prefs.seenHealthConnectPrimer, isTrue);
    },
  );

  test('seenHealthConnectPrimer reads a pre-seeded value', () async {
    SharedPreferences.setMockInitialValues({
      'seen_health_connect_primer': true,
    });
    final prefs = PreferencesService();
    prefs.resetForTests();
    await prefs.init();

    expect(prefs.seenHealthConnectPrimer, isTrue);
  });
}
