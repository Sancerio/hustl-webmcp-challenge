import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hustl_app/core/services/preferences_service.dart';

void main() {
  test('coach-explains opt-in defaults off and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();

    // Opt-in: off by default — even when on it is a no-op unless the backend
    // flag is enabled, so the coach is never noisy.
    expect(await prefs.getCoachExplainsEnabled(), isFalse);

    await prefs.setCoachExplainsEnabled(true);
    expect(await prefs.getCoachExplainsEnabled(), isTrue);

    await prefs.setCoachExplainsEnabled(false);
    expect(await prefs.getCoachExplainsEnabled(), isFalse);
  });

  test('coach-explains pref is independent of behavioral momentum', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();

    await prefs.setBehavioralMomentumEnabled(true);
    // Toggling momentum on must NOT flip coach-explains on.
    expect(await prefs.getCoachExplainsEnabled(), isFalse);

    await prefs.setCoachExplainsEnabled(true);
    await prefs.setBehavioralMomentumEnabled(false);
    // And clearing momentum must NOT clear coach-explains.
    expect(await prefs.getCoachExplainsEnabled(), isTrue);
  });
}
