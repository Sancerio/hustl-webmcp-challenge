import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/services/nutrition_checkin_reminder.dart';

void main() {
  group('shouldArmWeeklyCheckIn', () {
    final now = DateTime(2026, 6, 15, 8, 0);

    test('never arms when the reminder is opted out', () {
      expect(
        shouldArmWeeklyCheckIn(enabled: false, mode: 'auto', now: now),
        isFalse,
      );
    });

    test('does not arm in manual mode (coaching is off)', () {
      expect(
        shouldArmWeeklyCheckIn(enabled: true, mode: 'manual', now: now),
        isFalse,
      );
    });

    test('arms for an opted-in, auto, unlocked plan', () {
      expect(
        shouldArmWeeklyCheckIn(enabled: true, mode: 'auto', now: now),
        isTrue,
      );
    });

    test('suppresses while the plan is locked into the future', () {
      expect(
        shouldArmWeeklyCheckIn(
          enabled: true,
          mode: 'auto',
          lockedUntil: now.add(const Duration(days: 10)),
          now: now,
        ),
        isFalse,
      );
    });

    test('arms again once a past lock has elapsed', () {
      expect(
        shouldArmWeeklyCheckIn(
          enabled: true,
          mode: 'auto',
          lockedUntil: now.subtract(const Duration(days: 1)),
          now: now,
        ),
        isTrue,
      );
    });
  });
}
