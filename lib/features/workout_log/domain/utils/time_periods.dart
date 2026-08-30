import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:hustl_app/core/services/preferences_service.dart';

enum BodyScorePeriod {
  // Phase 1 (training-balance revamp): the in-progress current calendar week is
  // the DEFAULT and headline window so this-week work is visible immediately.
  // It resolves week start -> now (see [currentWeekToNow]); every other option
  // is a CLOSED window that ends before the current week.
  currentWeek('current_week', 'This week'),
  lastFullWeek('last_full_week', 'Last full week'),
  lastFullMonth('last_full_month', 'Last full month'),
  last4FullWeeks('last_4_full_weeks', 'Last 4 full weeks');

  const BodyScorePeriod(this.id, this.label);

  final String id;
  final String label;

  /// The Phase 1 default - the in-progress current week. Used to seed the
  /// persisted-pref default and to force a one-time migration off any stale
  /// closed-period selection so existing users are never stuck on a window that
  /// excludes the current week.
  static const BodyScorePeriod defaultPeriod = BodyScorePeriod.currentWeek;

  /// Whether this is the in-progress (open) current-week window. The headline
  /// numbers and cue are driven from RAW summed sets vs the weekly goal for this
  /// window; the other (closed) windows keep the paced behaviour.
  bool get isCurrentWeek => this == BodyScorePeriod.currentWeek;

  static BodyScorePeriod? fromId(String? value) {
    if (value == null) return null;
    for (final period in BodyScorePeriod.values) {
      if (period.id == value) return period;
    }
    return null;
  }

  static BodyScorePeriod fromLegacyDays(int days) {
    if (days <= 7) return BodyScorePeriod.lastFullWeek;
    if (days <= 21) return BodyScorePeriod.last4FullWeeks;
    return BodyScorePeriod.lastFullMonth;
  }

  BodyScorePeriodWindow resolve(
    DateTime today, {
    int firstWeekday = DateTime.monday,
  }) {
    final range = switch (this) {
      BodyScorePeriod.currentWeek => currentWeekToNow(
        today,
        firstWeekday: firstWeekday,
      ),
      BodyScorePeriod.lastFullWeek => lastFullWeekRange(
        today,
        firstWeekday: firstWeekday,
      ),
      BodyScorePeriod.lastFullMonth => lastFullMonthRange(today),
      BodyScorePeriod.last4FullWeeks => lastNFullWeeksRange(
        today,
        4,
        firstWeekday: firstWeekday,
      ),
    };
    final dateLabel = switch (this) {
      BodyScorePeriod.lastFullMonth => _formatMonthLabel(range.start),
      // "This week so far - day N of 7" - the in-progress week reads as live,
      // not as a closed date range. N = days elapsed since the week start (1-7).
      BodyScorePeriod.currentWeek => _formatCurrentWeekLabel(range),
      _ => formatShortDateRange(range),
    };
    return BodyScorePeriodWindow(
      period: this,
      range: range,
      dateLabel: dateLabel,
    );
  }
}

/// Days elapsed since the current week's start, inclusive of today (1-7).
int currentWeekDayOf(DateTimeRange currentWeekRange) {
  final start = startOfDay(currentWeekRange.start);
  final today = startOfDay(currentWeekRange.end);
  return (today.difference(start).inDays + 1)
      .clamp(1, DateTime.daysPerWeek)
      .toInt();
}

String _formatCurrentWeekLabel(DateTimeRange range) {
  return 'This week so far · day ${currentWeekDayOf(range)} of '
      '${DateTime.daysPerWeek}';
}

class BodyScorePeriodWindow {
  const BodyScorePeriodWindow({
    required this.period,
    required this.range,
    required this.dateLabel,
  });

  final BodyScorePeriod period;
  final DateTimeRange range;
  final String dateLabel;

  int get dayCount => inclusiveDays(range);

  String get labelWithDate => '${period.label} · $dateLabel';
}

const String bodyScorePeriodPrefKey = 'body_score_period';

/// One-time migration marker (Phase 1, training-balance revamp). Existing users
/// may have a stale CLOSED-period selection persisted under
/// [bodyScorePeriodPrefKey] that EXCLUDES the in-progress current week. On the
/// first read after this upgrade we FORCE the new current-week default once -
/// even over a stored pref - then record this marker so a later DELIBERATE
/// period change is honoured normally. Shared by every surface so the migration
/// runs regardless of which one (Home focus card or the Training-balance detail)
/// loads first. See [readPersistedBodyScorePeriod].
const String bodyScoreCurrentWeekMigrationKey =
    'body_score_current_week_default_v1';

/// Reads the persisted [BodyScorePeriod], APPLYING the one-time current-week
/// migration ([bodyScoreCurrentWeekMigrationKey]) so the new default takes
/// effect for upgraded users on whichever surface loads first.
///
/// - First read after upgrade (no migration marker): returns
///   [BodyScorePeriod.defaultPeriod] (the in-progress current week), persisting
///   it over any stale stored closed-period pref and setting the marker, so the
///   Home focus card and the detail BOTH default to the current week even when
///   a stale closed window was stored.
/// - Subsequent reads: returns the stored selection (a later deliberate change
///   is honoured), falling back to [BodyScorePeriod.defaultPeriod] when nothing
///   valid is stored.
///
/// CENTRALISED so the migration is never duplicated divergently across surfaces;
/// both [BodyScorePeriod] consumers call this single helper.
Future<BodyScorePeriod> readPersistedBodyScorePeriod(
  PreferencesService prefs,
) async {
  final migrated = await prefs.getRawString(bodyScoreCurrentWeekMigrationKey);
  if (migrated == null) {
    // First read after upgrade: force the current-week default once, regardless
    // of any stored closed-period pref, persist it, and set the marker.
    await prefs.setRawString(
      bodyScorePeriodPrefKey,
      BodyScorePeriod.defaultPeriod.id,
    );
    await prefs.setRawString(bodyScoreCurrentWeekMigrationKey, 'done');
    return BodyScorePeriod.defaultPeriod;
  }
  final storedPeriodId = await prefs.getRawString(bodyScorePeriodPrefKey);
  return BodyScorePeriod.fromId(storedPeriodId) ?? BodyScorePeriod.defaultPeriod;
}

DateTime startOfDay(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

DateTime endOfDay(DateTime date) {
  return startOfDay(
    date,
  ).add(const Duration(days: 1)).subtract(const Duration(microseconds: 1));
}

int inclusiveDays(DateTimeRange range) {
  return range.end.difference(range.start).inDays + 1;
}

DateTime startOfWeek(DateTime date, {int firstWeekday = DateTime.monday}) {
  final normalized = startOfDay(date);
  final int delta = (normalized.weekday - firstWeekday) % DateTime.daysPerWeek;
  return normalized.subtract(Duration(days: delta));
}

DateTimeRange lastFullWeekRange(
  DateTime today, {
  int firstWeekday = DateTime.monday,
}) {
  final thisWeekStart = startOfWeek(today, firstWeekday: firstWeekday);
  final start = thisWeekStart.subtract(const Duration(days: 7));
  final end = thisWeekStart.subtract(const Duration(microseconds: 1));
  return DateTimeRange(start: start, end: end);
}

DateTimeRange lastNFullWeeksRange(
  DateTime today,
  int count, {
  int firstWeekday = DateTime.monday,
}) {
  assert(count > 0, 'count must be positive');
  final thisWeekStart = startOfWeek(today, firstWeekday: firstWeekday);
  final start = thisWeekStart.subtract(Duration(days: 7 * count));
  final end = thisWeekStart.subtract(const Duration(microseconds: 1));
  return DateTimeRange(start: start, end: end);
}

DateTimeRange lastFullMonthRange(DateTime today) {
  final thisMonthStart = DateTime(today.year, today.month, 1);
  final prevMonthStart = DateTime(
    thisMonthStart.year,
    thisMonthStart.month - 1,
  );
  final prevMonthEnd = thisMonthStart.subtract(const Duration(microseconds: 1));
  return DateTimeRange(start: prevMonthStart, end: prevMonthEnd);
}

DateTimeRange currentWeekToNow(
  DateTime now, {
  int firstWeekday = DateTime.monday,
}) {
  final start = startOfWeek(now, firstWeekday: firstWeekday);
  return DateTimeRange(start: start, end: now);
}

DateTimeRange currentMonthToNow(DateTime now) {
  final start = DateTime(now.year, now.month, 1);
  return DateTimeRange(start: start, end: now);
}

DateTimeRange rollingRangeToToday({required int days, DateTime? anchor}) {
  final normalizedDays = days.clamp(1, 365);
  final DateTime end = endOfDay(anchor ?? DateTime.now());
  final DateTime start = startOfDay(
    end,
  ).subtract(Duration(days: normalizedDays - 1));
  return DateTimeRange(start: start, end: end);
}

String formatShortDateRange(DateTimeRange range) {
  final start = startOfDay(range.start);
  final end = endOfDay(range.end);
  final bool sameYear = start.year == end.year;
  final bool sameMonth = sameYear && start.month == end.month;
  final startFormat = DateFormat(sameYear ? 'MMM d' : 'MMM d, y');
  final endFormat = DateFormat(
    sameMonth
        ? 'd, y'
        : sameYear
        ? 'MMM d'
        : 'MMM d, y',
  );
  final startLabel = startFormat.format(start);
  final endLabel = endFormat.format(end);
  return '$startLabel–$endLabel';
}

String _formatMonthLabel(DateTime start) {
  return DateFormat.yMMMM().format(DateTime(start.year, start.month, 1));
}
