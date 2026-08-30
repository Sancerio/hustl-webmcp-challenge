/// Pure date math for repeating, day-of-week scheduled notifications.
///
/// [NotificationService] needs a concrete *next* fire time to hand
/// `zonedSchedule` before the OS takes over the weekly repeat. Keeping the
/// arithmetic here — free of `flutter_local_notifications` and `timezone` — lets
/// us unit-test the gnarly seed cases (later today vs. already passed vs. a
/// different weekday) without a plugin or a real clock.
library;

/// The next occurrence of [weekday] at [hour]:[minute] strictly after [from].
///
/// [weekday] follows `DateTime` (Mon = 1 … Sun = 7). When [from] already sits on
/// the target weekday, the same day is returned only if its [hour]:[minute] is
/// still ahead; otherwise it rolls to next week, so a reminder never resolves to
/// a past instant (which would silently no-show on the first cycle).
DateTime nextWeeklyInstance({
  required DateTime from,
  required int weekday,
  required int hour,
  required int minute,
}) {
  var candidate = DateTime(
    from.year,
    from.month,
    from.day,
    hour,
    minute,
  );
  // At most 8 steps: advance until the weekday matches AND the instant is in
  // the future relative to [from].
  while (candidate.weekday != weekday || !candidate.isAfter(from)) {
    candidate = candidate.add(const Duration(days: 1));
  }
  return candidate;
}
