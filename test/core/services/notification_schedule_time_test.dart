import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/services/notification_schedule_time.dart';

void main() {
  group('nextWeeklyInstance', () {
    // A fixed Monday 08:00 seed so the cases below are unambiguous.
    final monday0800 = DateTime(2026, 6, 15, 8, 0);

    setUp(() {
      // Guard: the seed really is a Monday, so the weekday-based cases hold.
      expect(monday0800.weekday, DateTime.monday);
    });

    test('returns later the same day when the time is still ahead', () {
      final result = nextWeeklyInstance(
        from: monday0800,
        weekday: DateTime.monday,
        hour: 9,
        minute: 0,
      );
      expect(result, DateTime(2026, 6, 15, 9, 0));
      expect(result.isAfter(monday0800), isTrue);
    });

    test('rolls to next week when the time has already passed today', () {
      final result = nextWeeklyInstance(
        from: monday0800,
        weekday: DateTime.monday,
        hour: 7,
        minute: 0,
      );
      expect(result, DateTime(2026, 6, 22, 7, 0));
      expect(result.weekday, DateTime.monday);
    });

    test('rolls a full week forward when the instant is exactly equal', () {
      final result = nextWeeklyInstance(
        from: monday0800,
        weekday: DateTime.monday,
        hour: 8,
        minute: 0,
      );
      // Strictly future: an equal seed must not resolve to the past/now.
      expect(result, DateTime(2026, 6, 22, 8, 0));
      expect(result.isAfter(monday0800), isTrue);
    });

    test('advances to the next matching weekday later in the week', () {
      final result = nextWeeklyInstance(
        from: monday0800,
        weekday: DateTime.thursday,
        hour: 9,
        minute: 30,
      );
      expect(result.weekday, DateTime.thursday);
      expect(result, DateTime(2026, 6, 18, 9, 30));
      final daysAhead = result.difference(monday0800).inDays;
      expect(daysAhead, lessThan(7));
    });

    test('wraps to the following week for an earlier weekday', () {
      // Sunday is "behind" Monday, so it must land six days out, not in the past.
      final result = nextWeeklyInstance(
        from: monday0800,
        weekday: DateTime.sunday,
        hour: 9,
        minute: 0,
      );
      expect(result.weekday, DateTime.sunday);
      expect(result.isAfter(monday0800), isTrue);
      expect(result, DateTime(2026, 6, 21, 9, 0));
    });
  });
}
