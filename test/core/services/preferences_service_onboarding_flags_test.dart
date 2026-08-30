import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  PreferencesService freshPrefs() {
    final prefs = PreferencesService();
    prefs.resetForTests();
    return prefs;
  }

  group('onboarding v2 one-shot flags', () {
    test('first-win flag defaults false and persists once set', () async {
      final prefs = freshPrefs();
      SharedPreferences.setMockInitialValues({});
      expect(await prefs.getOnboardingV2SeenFirstWin(), isFalse);
      await prefs.setOnboardingV2SeenFirstWin(true);
      expect(await prefs.getOnboardingV2SeenFirstWin(), isTrue);
    });

    test('sign-in nudge flag defaults false and persists once set', () async {
      final prefs = freshPrefs();
      SharedPreferences.setMockInitialValues({});
      expect(await prefs.getOnboardingV2SeenSigninNudge(), isFalse);
      await prefs.setOnboardingV2SeenSigninNudge(true);
      expect(await prefs.getOnboardingV2SeenSigninNudge(), isTrue);
    });

    test(
      'notification primer flag defaults false and persists once set',
      () async {
        final prefs = freshPrefs();
        SharedPreferences.setMockInitialValues({});
        expect(await prefs.getOnboardingV2SeenNotificationPrimer(), isFalse);
        await prefs.setOnboardingV2SeenNotificationPrimer(true);
        expect(await prefs.getOnboardingV2SeenNotificationPrimer(), isTrue);
      },
    );

    test(
      'start-workout coachmark migrated to a v2-named key, defaults false',
      () async {
        final prefs = freshPrefs();
        SharedPreferences.setMockInitialValues({});
        expect(await prefs.getOnboardingV2SeenCoachmarkStartWorkout(), isFalse);
        await prefs.setOnboardingV2SeenCoachmarkStartWorkout(true);
        expect(await prefs.getOnboardingV2SeenCoachmarkStartWorkout(), isTrue);
      },
    );
  });

  group('onboarding v3 intro first-run flag', () {
    test('sync getter defaults false and persists once set', () async {
      final prefs = freshPrefs();
      SharedPreferences.setMockInitialValues({});
      await prefs.init(); // populate _prefs so the sync getter can read
      expect(prefs.onboardingIntroSeen, isFalse);
      await prefs.setOnboardingIntroSeen(true);
      expect(prefs.onboardingIntroSeen, isTrue);
    });
  });
}
