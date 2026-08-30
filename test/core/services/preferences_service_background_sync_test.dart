import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hustl_app/core/services/preferences_service.dart';

void main() {
  test('background sync preference persists', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    expect(await prefs.getBackgroundSyncEnabled(), isTrue);
    await prefs.setBackgroundSyncEnabled(false);
    expect(await prefs.getBackgroundSyncEnabled(), isFalse);
  });

  test('inactivity reminder minutes persist and clamp', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    expect(prefs.inactivityReminderMinutes, 5);
    await prefs.setInactivityReminderMinutes(12);
    expect(prefs.inactivityReminderMinutes, 12);
    await prefs.setInactivityReminderMinutes(0);
    expect(prefs.inactivityReminderMinutes, 1);
    await prefs.setInactivityReminderMinutes(120);
    expect(prefs.inactivityReminderMinutes, 60);
  });
}
