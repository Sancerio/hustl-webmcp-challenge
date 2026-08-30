import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hustl_app/core/services/preferences_service.dart';

void main() {
  test('behavioral-momentum opt-in defaults off and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();

    // Opt-in: off by default so the coach is never noisy.
    expect(await prefs.getBehavioralMomentumEnabled(), isFalse);

    await prefs.setBehavioralMomentumEnabled(true);
    expect(await prefs.getBehavioralMomentumEnabled(), isTrue);

    await prefs.setBehavioralMomentumEnabled(false);
    expect(await prefs.getBehavioralMomentumEnabled(), isFalse);
  });
}
