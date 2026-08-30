import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('getWatchCompanionEnabledOrNull returns null when unset', () async {
    final prefs = PreferencesService();
    prefs.resetForTests();
    SharedPreferences.setMockInitialValues({});
    expect(await prefs.getWatchCompanionEnabledOrNull(), isNull);
    expect(await prefs.getWatchCompanionEnabled(), isFalse);
  });

  test('getWatchCompanionEnabledOrNull returns value when set', () async {
    final prefs = PreferencesService();
    prefs.resetForTests();
    SharedPreferences.setMockInitialValues({'watch_companion_enabled': true});
    expect(await prefs.getWatchCompanionEnabledOrNull(), isTrue);
    expect(await prefs.getWatchCompanionEnabled(), isTrue);
  });

  test('watch companion debug override can be set and cleared', () async {
    final prefs = PreferencesService();
    prefs.resetForTests();
    SharedPreferences.setMockInitialValues({});
    expect(await prefs.getWatchCompanionDebugOverride(), isNull);
    await prefs.setWatchCompanionDebugOverride(false);
    expect(await prefs.getWatchCompanionDebugOverride(), isFalse);
    await prefs.setWatchCompanionDebugOverride(null);
    expect(await prefs.getWatchCompanionDebugOverride(), isNull);
  });

  test(
    'watch heart-rate recording default is on and can be disabled',
    () async {
      final prefs = PreferencesService();
      prefs.resetForTests();
      SharedPreferences.setMockInitialValues({});
      expect(await prefs.getWatchHeartRateRecordingEnabled(), isTrue);
      await prefs.setWatchHeartRateRecordingEnabled(false);
      expect(await prefs.getWatchHeartRateRecordingEnabled(), isFalse);
    },
  );
}
