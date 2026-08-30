import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/theme_service.dart';

void main() {
  late PreferencesService prefs;
  late ThemeService themeService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = PreferencesService();
    await prefs.init();
    themeService = ThemeService(prefs);
    await themeService.init();
  });

  test('defaults to system when unset', () async {
    expect(themeService.themeMode.value, ThemeMode.system);
  });

  test('setThemeMode persists and notifies listeners', () async {
    int notifyCount = 0;
    themeService.themeMode.addListener(() => notifyCount++);

    await themeService.setThemeMode(ThemeMode.dark);
    expect(themeService.themeMode.value, ThemeMode.dark);

    // Recreate service to verify persistence
    final themeService2 = ThemeService(prefs);
    await themeService2.init();
    expect(themeService2.themeMode.value, ThemeMode.dark);

    expect(notifyCount, greaterThan(0));
  });
}
