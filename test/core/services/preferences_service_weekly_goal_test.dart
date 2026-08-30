import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  PreferencesService freshPrefs() {
    final prefs = PreferencesService();
    prefs.resetForTests();
    return prefs;
  }

  group('weekly workout goal notifier', () {
    test('defaults to 3 and seeds from stored value on init', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = freshPrefs();
      expect(prefs.weeklyWorkoutGoalListenable.value, 3);

      SharedPreferences.setMockInitialValues({'weekly_workout_goal': 5});
      final seeded = freshPrefs();
      await seeded.init();
      expect(seeded.weeklyWorkoutGoalListenable.value, 5);
    });

    test('setWeeklyWorkoutGoal updates the notifier and clamps', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = freshPrefs();

      await prefs.setWeeklyWorkoutGoal(6);
      expect(prefs.weeklyWorkoutGoalListenable.value, 6);
      expect(await prefs.getWeeklyWorkoutGoal(), 6);

      // Out-of-range writes are clamped to 1..14 in both the store and notifier.
      await prefs.setWeeklyWorkoutGoal(99);
      expect(prefs.weeklyWorkoutGoalListenable.value, 14);
      await prefs.setWeeklyWorkoutGoal(0);
      expect(prefs.weeklyWorkoutGoalListenable.value, 1);
    });

    test('listeners are notified when the goal changes elsewhere', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = freshPrefs();
      // Establish a known baseline (and run init) before attaching the listener
      // so only the change-under-test is counted.
      await prefs.setWeeklyWorkoutGoal(2);

      var fired = 0;
      int? lastSeen;
      void listener() {
        fired++;
        lastSeen = prefs.weeklyWorkoutGoalListenable.value;
      }

      prefs.weeklyWorkoutGoalListenable.addListener(listener);
      addTearDown(
        () => prefs.weeklyWorkoutGoalListenable.removeListener(listener),
      );

      await prefs.setWeeklyWorkoutGoal(7);
      expect(fired, 1);
      expect(lastSeen, 7);
    });
  });
}
