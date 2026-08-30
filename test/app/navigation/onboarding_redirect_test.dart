import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/app/navigation/app_router.dart';

void main() {
  group('onboardingRedirectTarget', () {
    test('returns null when the v3 flag is off (default production)', () {
      for (final seen in const [true, false]) {
        for (final loc in const ['/', '/onboarding/intro', '/nutrition']) {
          expect(
            onboardingRedirectTarget(enabled: false, seen: seen, location: loc),
            isNull,
          );
        }
      }
    });

    group('flag on · new user (not seen)', () {
      test('a plain cold start is sent to the intro', () {
        expect(
          onboardingRedirectTarget(enabled: true, seen: false, location: '/'),
          '/onboarding/intro',
        );
      });

      test(
        'deep links and tab roots pass straight through (never swallowed)',
        () {
          for (final loc in const [
            '/nutrition',
            '/history',
            '/skip',
            '/workout_session',
            '/proposals/abc',
            '/add-food',
            '/nutrition/weight',
            '/auth/google/callback',
            '/widget/workouts',
          ]) {
            expect(
              onboardingRedirectTarget(
                enabled: true,
                seen: false,
                location: loc,
              ),
              isNull,
              reason: loc,
            );
          }
        },
      );

      test('in-onboarding routes are left alone', () {
        for (final loc in const ['/onboarding/intro', '/onboarding/welcome']) {
          expect(
            onboardingRedirectTarget(enabled: true, seen: false, location: loc),
            isNull,
            reason: loc,
          );
        }
      });
    });

    group('flag on · returning user (seen — incl. existing v2 users)', () {
      test('is bounced out of /onboarding back to home', () {
        for (final loc in const ['/onboarding/intro', '/onboarding/welcome']) {
          expect(
            onboardingRedirectTarget(enabled: true, seen: true, location: loc),
            '/',
            reason: loc,
          );
        }
      });

      test('is never redirected from a normal route', () {
        for (final loc in const ['/', '/nutrition', '/workout_session']) {
          expect(
            onboardingRedirectTarget(enabled: true, seen: true, location: loc),
            isNull,
            reason: loc,
          );
        }
      });

      test('reaches the post-onboarding first-win summary (allowlisted)', () {
        // A new lifter is "seen" the moment they pass the welcome screen, so the
        // first-win summary must NOT be bounced home like the intro/welcome are.
        expect(
          onboardingRedirectTarget(
            enabled: true,
            seen: true,
            location: '/onboarding/first-win/abc123',
          ),
          isNull,
        );
      });

      test('reaches the Strong import flow (allowlisted)', () {
        // Seen is marked BEFORE pushing into import (so an app-kill mid-import
        // resumes past the carousel), so the import routes must not be bounced
        // home like the intro/welcome are.
        for (final loc in const [
          '/onboarding/import',
          '/onboarding/import/preview',
          '/onboarding/import/restored',
        ]) {
          expect(
            onboardingRedirectTarget(enabled: true, seen: true, location: loc),
            isNull,
            reason: loc,
          );
        }
      });
    });
  });
}
