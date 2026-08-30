import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hustl_app/core/services/preferences_service.dart';

void main() {
  test('weekly training recap opt-in defaults off and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();

    // Opt-in: off by default — the recap only exists once the user turns it on.
    expect(prefs.weeklyTrainingRecapEnabled, isFalse);

    await prefs.setWeeklyTrainingRecapEnabled(true);
    expect(prefs.weeklyTrainingRecapEnabled, isTrue);

    await prefs.setWeeklyTrainingRecapEnabled(false);
    expect(prefs.weeklyTrainingRecapEnabled, isFalse);
  });

  test('weekly training recap pref is independent of next-set targets',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();

    await prefs.setSuggestNextSetTargets(false);
    // Toggling next-set targets must NOT flip the recap on.
    expect(prefs.weeklyTrainingRecapEnabled, isFalse);

    await prefs.setWeeklyTrainingRecapEnabled(true);
    await prefs.setSuggestNextSetTargets(true);
    // And re-enabling next-set targets must NOT clear the recap.
    expect(prefs.weeklyTrainingRecapEnabled, isTrue);
  });
}
