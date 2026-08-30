import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/app/di/service_locator.dart';
import 'package:hustl_app/app/demo/demo_coaching_trends_api.dart';
import 'package:hustl_app/app/demo/demo_mode.dart';
import 'package:hustl_app/app/demo/demo_workout_history_web_mcp_service.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/theme_service.dart';
import 'package:hustl_app/core/webmcp/coaching_trends_api.dart';
import 'package:hustl_app/core/webmcp/web_mcp_config.dart';
import 'package:hustl_app/core/webmcp/workout_history_web_mcp_service.dart';

void main() {
  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
  });

  test('setupDependencies registers and initializes core services', () async {
    await setupDependencies();

    expect(getIt.isRegistered<PreferencesService>(), isTrue);
    expect(getIt.isRegistered<ThemeService>(), isTrue);

    final prefs = getIt<PreferencesService>();
    final theme = getIt<ThemeService>();

    // Preferences should be usable immediately
    final rawMode = await prefs.getRawThemeMode();
    expect(rawMode, anyOf(['system', 'light', 'dark']));

    // Theme service should already reflect stored mode
    expect(
      theme.themeMode.value,
      anyOf(ThemeMode.system, ThemeMode.light, ThemeMode.dark),
    );
  });

  test('demo WebMCP variant wires only offline history readers', () async {
    if (!kDemoMode || !kWebMcpEnabled) return;

    await setupDependencies();

    expect(
      getIt<WorkoutHistoryWebMcpReader>(),
      isA<DemoWorkoutHistoryWebMcpService>(),
    );
    expect(getIt<CoachingTrendsApi>(), isA<DemoCoachingTrendsApi>());
  });
}
