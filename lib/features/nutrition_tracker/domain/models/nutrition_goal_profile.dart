import 'package:flutter/material.dart' show DateUtils;
import 'package:equatable/equatable.dart';

/// Subtract [years] whole years from [from], CLAMPING the day to the last valid
/// day of the target month so a Feb-29 source never overflows into the next
/// month. Example: `subtractYears(DateTime(2024, 2, 29), 13)` is
/// `DateTime(2011, 2, 28)` — NOT `DateTime(2011, 3, 1)`.
///
/// Plain `DateTime(from.year - years, from.month, from.day)` rolls Feb 29 over to
/// Mar 1 in a non-leap target year, which would push the under-13 DOB floor a day
/// later and let a just-under-13 date through the picker (the backend's [13, 120]
/// validation then rejects it). Clamping keeps every derived boundary leap-safe.
DateTime subtractYears(DateTime from, int years) {
  final targetYear = from.year - years;
  final lastDayOfMonth = DateUtils.getDaysInMonth(targetYear, from.month);
  final day = from.day <= lastDayOfMonth ? from.day : lastDayOfMonth;
  return DateTime(targetYear, from.month, day);
}

/// Whole years between [dob] and [now], using a stable CALENDAR-DATE comparison
/// (compare Y/M/D, never millisecond subtraction or /365.25). Mirrors the server
/// resolver in `hustl_backend/lib/nutrition/age.ts` so the app, API, and
/// connector all report the same derived age.
///
/// The birthday is "reached" when (now.month, now.day) >= (dob.month, dob.day),
/// so age increments ON the birthday and is one lower the day before. A Feb-29
/// DOB turns older on Mar 1 in a common (non-leap) year by the same tuple rule.
int ageFromBirthDate(DateTime dob, DateTime now) {
  var years = now.year - dob.year;
  if (now.month < dob.month ||
      (now.month == dob.month && now.day < dob.day)) {
    years -= 1;
  }
  return years;
}

/// The persisted "about you" inputs the goal sheet collects (date of birth, sex,
/// height, weight, activity level). These live on `user_profiles` on the backend
/// rather than on the weekly target plan, so they must be carried back to the
/// client explicitly for the goal sheet to prefill on reopen. Every field is
/// nullable — a brand-new user has none saved yet.
///
/// Date of birth is the stored source of truth; AGE is DERIVED from it ([ageYears])
/// so it never goes stale. For an older backend that still only returns a numeric
/// `ageYears`, [legacyAgeYears] preserves that number for read-only display, but
/// we NEVER fabricate a [birthDate] from it.
class NutritionGoalProfile extends Equatable {
  const NutritionGoalProfile({
    this.birthDate,
    this.legacyAgeYears,
    this.heightCm,
    this.weightKg,
    this.gender,
    this.activityLevel,
  });

  /// Date-only (local) date of birth — the authoritative source of truth.
  final DateTime? birthDate;

  /// Read-only fallback: a numeric age returned by an older backend that has no
  /// `birthDate`. Surfaced as seed text only; never used to synthesize a DOB.
  final int? legacyAgeYears;

  final int? heightCm;
  final double? weightKg;
  final String? gender;
  final String? activityLevel;

  /// The display age. Derived from [birthDate] when present (the math lives in
  /// exactly one place), else the legacy numeric age, else null.
  int? get ageYears {
    final dob = birthDate;
    if (dob != null) {
      final age = ageFromBirthDate(dob, DateTime.now());
      return age >= 0 ? age : null;
    }
    return legacyAgeYears;
  }

  bool get isEmpty =>
      birthDate == null &&
      legacyAgeYears == null &&
      heightCm == null &&
      weightKg == null &&
      (gender == null || gender!.isEmpty) &&
      (activityLevel == null || activityLevel!.isEmpty);

  /// Parses the `profile` object returned by the targets endpoints. Tolerates a
  /// null map (older backends / no profile yet) by returning an empty profile,
  /// and never throws on garbage.
  factory NutritionGoalProfile.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const NutritionGoalProfile();
    int? toInt(Object? v) {
      final n = (v as num?)?.toDouble();
      if (n == null || !n.isFinite || n <= 0) return null;
      return n.round();
    }

    double? toDouble(Object? v) {
      final n = (v as num?)?.toDouble();
      if (n == null || !n.isFinite || n <= 0) return null;
      return n;
    }

    String? toStr(Object? v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    // Parse the ISO 'YYYY-MM-DD' birthDate, then strip to a date-only local
    // DateTime so display + serialization stay in date-only space (no tz shift).
    DateTime? parseBirthDate(Object? v) {
      final s = toStr(v);
      if (s == null) return null;
      final parsed = DateTime.tryParse(s);
      if (parsed == null) return null;
      return DateTime(parsed.year, parsed.month, parsed.day);
    }

    final birthDate = parseBirthDate(map['birthDate']);
    return NutritionGoalProfile(
      birthDate: birthDate,
      // Keep the legacy numeric age only when no birthDate is present (display
      // fallback for an older backend); never synthesize a DOB from it.
      legacyAgeYears: birthDate == null ? toInt(map['ageYears']) : null,
      heightCm: toInt(map['heightCm']),
      weightKg: toDouble(map['weightKg']),
      gender: toStr(map['gender']),
      activityLevel: toStr(map['activityLevel']),
    );
  }

  @override
  List<Object?> get props => [
    birthDate,
    legacyAgeYears,
    heightCm,
    weightKg,
    gender,
    activityLevel,
  ];
}
