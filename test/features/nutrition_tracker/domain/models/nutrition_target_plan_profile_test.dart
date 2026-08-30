import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/nutrition_goal_profile.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/nutrition_target_plan.dart';

void main() {
  group('ageFromBirthDate (shared derivation)', () {
    test('age increments ON the birthday and is one lower the day before', () {
      final now = DateTime(2026, 6, 21);
      expect(ageFromBirthDate(DateTime(2000, 6, 21), now), 26); // birthday today
      expect(ageFromBirthDate(DateTime(2000, 6, 22), now), 25); // day before
    });

    test('year-boundary: Dec 31 DOB', () {
      expect(ageFromBirthDate(DateTime(2000, 12, 31), DateTime(2025, 12, 30)), 24);
      expect(ageFromBirthDate(DateTime(2000, 12, 31), DateTime(2025, 12, 31)), 25);
    });

    test('leap-day DOB turns older on Mar 1 in a common year', () {
      expect(ageFromBirthDate(DateTime(2000, 2, 29), DateTime(2025, 2, 28)), 24);
      expect(ageFromBirthDate(DateTime(2000, 2, 29), DateTime(2025, 3, 1)), 25);
    });
  });

  group('subtractYears (leap-safe DOB-picker bounds)', () {
    test('plain (non-leap source) subtraction keeps the same month/day', () {
      expect(subtractYears(DateTime(2026, 6, 21), 13), DateTime(2013, 6, 21));
      expect(subtractYears(DateTime(2026, 6, 21), 120), DateTime(1906, 6, 21));
    });

    test(
      'Feb 29 clamps to Feb 28 in a non-leap target year (never rolls to Mar 1)',
      () {
        // 13y back from a leap-day "today": 2011 is NOT a leap year. The youngest
        // selectable DOB (lastDate) must stay Feb 28 — rolling to Mar 1 would
        // admit a just-under-13 DOB the backend's [13, 120] rule rejects.
        final last = subtractYears(DateTime(2024, 2, 29), 13);
        expect(last, DateTime(2011, 2, 28));
        expect(last, isNot(DateTime(2011, 3, 1)));

        // 120y back: 1904 IS a leap year, so the day is preserved there.
        expect(subtractYears(DateTime(2024, 2, 29), 120), DateTime(1904, 2, 29));
      },
    );

    test('Feb 29 → Feb 29 when the target year is also a leap year', () {
      // 4y back from 2024 lands on 2020 (leap): the day survives unclamped.
      expect(subtractYears(DateTime(2024, 2, 29), 4), DateTime(2020, 2, 29));
    });

    test(
      'the clamped 13y floor does not admit an under-13 DOB on a leap day',
      () {
        // On a leap-day "today", a child turning 13 the next day must NOT be
        // selectable. The clamped lastDate is Feb 28 of the non-leap target year,
        // so the under-13 boundary (Feb 29 of the prior, would-be Mar 1) is below
        // the floor and the picker correctly excludes it.
        final today = DateTime(2024, 2, 29);
        final lastDate = subtractYears(today, 13); // youngest selectable DOB
        // A DOB one day LATER than the floor (younger than 13) is after lastDate.
        final justUnder13 = lastDate.add(const Duration(days: 1));
        expect(justUnder13.isAfter(lastDate), isTrue);
        // And the floor itself derives an age of exactly 13 against today.
        expect(ageFromBirthDate(lastDate, today), 13);
        // One day younger derives 12 — correctly rejected by the [13, 120] rule.
        expect(ageFromBirthDate(justUnder13, today), 12);
      },
    );
  });

  group('NutritionGoalProfile.fromMap', () {
    test('parses the targets-endpoint profile object with birthDate', () {
      final profile = NutritionGoalProfile.fromMap(const {
        'birthDate': '1995-03-10',
        'ageYears': 31,
        'heightCm': 175,
        'weightKg': 72.4,
        'gender': 'female',
        'activityLevel': 'light',
      });
      // birthDate is the source of truth; ageYears is derived from it.
      expect(profile.birthDate, DateTime(1995, 3, 10));
      final expectedAge = ageFromBirthDate(DateTime(1995, 3, 10), DateTime.now());
      expect(profile.ageYears, expectedAge);
      // The numeric ageYears in the map is ignored when a birthDate is present.
      expect(profile.legacyAgeYears, isNull);
      expect(profile.heightCm, 175);
      expect(profile.weightKg, 72.4);
      expect(profile.gender, 'female');
      expect(profile.activityLevel, 'light');
      expect(profile.isEmpty, isFalse);
    });

    test('legacy backend (no birthDate) surfaces numeric ageYears for display', () {
      final profile = NutritionGoalProfile.fromMap(const {
        'ageYears': 31,
        'heightCm': 175,
      });
      // No DOB is fabricated; the legacy number is preserved as the display age.
      expect(profile.birthDate, isNull);
      expect(profile.legacyAgeYears, 31);
      expect(profile.ageYears, 31);
      expect(profile.isEmpty, isFalse);
    });

    test('null map yields an empty profile (no saved data yet)', () {
      final profile = NutritionGoalProfile.fromMap(null);
      expect(profile.isEmpty, isTrue);
      expect(profile.ageYears, isNull);
    });

    test('drops non-positive / blank values to null and tolerates garbage DOB', () {
      final profile = NutritionGoalProfile.fromMap(const {
        'birthDate': 'not-a-date',
        'ageYears': 0,
        'heightCm': null,
        'weightKg': -5,
        'gender': '',
        'activityLevel': '   ',
      });
      expect(profile.birthDate, isNull);
      expect(profile.legacyAgeYears, isNull);
      expect(profile.ageYears, isNull);
      expect(profile.heightCm, isNull);
      expect(profile.weightKg, isNull);
      expect(profile.gender, isNull);
      expect(profile.activityLevel, isNull);
      expect(profile.isEmpty, isTrue);
    });
  });

  group('NutritionTargetPlan.fromMap profile carry', () {
    // Regression for the original bug: the backend persisted the profile but the
    // client never carried it back, so the goal sheet reset to defaults on
    // reopen. The plan map must now surface the sibling `profile` object the
    // repository injects from the targets response.
    test('carries the injected profile sibling into the plan', () {
      final plan = NutritionTargetPlan.fromMap(const {
        'week_start': '2026-06-15',
        'mode': 'auto',
        'goal': 'lose',
        'rate_per_week': 0.4,
        'calories_target': 2100,
        'protein_grams_target': 160,
        'carbs_grams_target': 200,
        'fat_grams_target': 60,
        'needsSetup': false,
        'profile': {
          'birthDate': '1986-04-02',
          'heightCm': 180,
          'weightKg': 84.0,
          'gender': 'male',
          'activityLevel': 'very_active',
        },
      });

      expect(plan.goal, 'lose');
      expect(plan.ratePerWeek, 0.4);
      expect(plan.profile, isNotNull);
      expect(plan.profile!.birthDate, DateTime(1986, 4, 2));
      expect(plan.profile!.heightCm, 180);
      expect(plan.profile!.weightKg, 84.0);
      expect(plan.profile!.gender, 'male');
      expect(plan.profile!.activityLevel, 'very_active');
    });

    test('no profile key leaves profile null (older response shape)', () {
      final plan = NutritionTargetPlan.fromMap(const {
        'week_start': '2026-06-15',
        'mode': 'auto',
        'goal': 'maintain',
        'calories_target': 2000,
        'protein_grams_target': 150,
        'carbs_grams_target': 200,
        'fat_grams_target': 60,
        'needsSetup': false,
      });
      expect(plan.profile, isNull);
    });
  });
}
