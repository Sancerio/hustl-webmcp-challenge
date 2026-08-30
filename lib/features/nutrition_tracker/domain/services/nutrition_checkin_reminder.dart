import '../../../../core/services/notification_service.dart';
import '../../../../core/services/preferences_service.dart';
import '../models/nutrition_target_plan.dart';

/// Should the repeating weekly check-in reminder be armed for this plan state?
///
/// Anti-nag by construction: only an opted-in, auto-coaching, unlocked plan
/// earns the weekly nudge.
///   - Not opted in        → no reminder (the feature is off).
///   - Manual mode         → coaching is off, there is no check-in to review.
///   - Locked into a future → the plan is intentionally frozen; a nudge would be
///     noise until the lock passes.
/// A single repeating notification can't suppress just one week, so per-week
/// states (already applied / on-track / insufficient data) deliberately do NOT
/// disarm it — the tap still lands on Strategy, which shows the right state, and
/// the cadence (one ping per week) is preserved. Pure for unit testing.
bool shouldArmWeeklyCheckIn({
  required bool enabled,
  required String mode,
  DateTime? lockedUntil,
  required DateTime now,
}) {
  if (!enabled) return false;
  if (mode != 'auto') return false;
  if (lockedUntil != null && lockedUntil.isAfter(now)) return false;
  return true;
}

/// Wires the pure [shouldArmWeeklyCheckIn] decision to the saved preferences and
/// the OS schedule. Safe to call on every Strategy load and after any plan
/// mutation — scheduling is idempotent (stable id) and arming/cancelling is
/// cheap, so re-syncing keeps the schedule honest against the latest state
/// (mode flip, lock set/clear, opt-out) with at most a one-cycle lag.
class NutritionCheckInReminder {
  NutritionCheckInReminder({
    PreferencesService? prefs,
    NotificationService? notifications,
  }) : _prefs = prefs ?? PreferencesService(),
       _notifications = notifications ?? NotificationService();

  final PreferencesService _prefs;
  final NotificationService _notifications;

  Future<void> sync(NutritionTargetPlan plan, {DateTime? now}) async {
    final enabled = await _prefs.getNutritionCheckInReminderEnabled();
    final arm = shouldArmWeeklyCheckIn(
      enabled: enabled,
      mode: plan.mode,
      lockedUntil: plan.lockedUntil,
      now: now ?? DateTime.now(),
    );
    if (arm) {
      await _notifications.scheduleWeeklyCheckIn(
        weekday: await _prefs.getNutritionCheckInReminderWeekday(),
        hour: await _prefs.getNutritionCheckInReminderHour(),
        minute: await _prefs.getNutritionCheckInReminderMinute(),
      );
    } else {
      await _notifications.cancelWeeklyCheckIn();
    }
  }
}
