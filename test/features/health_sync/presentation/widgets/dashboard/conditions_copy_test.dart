import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/dashboard/conditions_copy.dart';

const _alarmingWords = [
  'danger',
  'bad',
  'worse',
  'fail',
  'sick',
  'illness',
  'alarm',
  'warning',
];

void _expectNeverAlarmist(String? text) {
  if (text == null) return;
  final lower = text.toLowerCase();
  for (final word in _alarmingWords) {
    expect(
      lower,
      isNot(contains(word)),
      reason: 'lede should never say "$word": $text',
    );
  }
}

DailyRecoverySnapshot _snap({
  DateTime? date,
  double? sleepMinutes,
  double? hrv,
  double? rhr,
}) => DailyRecoverySnapshot(
  date: date ?? DateTime(2026, 1, 5),
  sleepDurationMinutes: sleepMinutes,
  hrvValue: hrv,
  restingHeartRateBpm: rhr,
);

void main() {
  group('trailingSignalBaseline', () {
    test('returns null below the minimum count', () {
      expect(trailingSignalBaseline([1.0, 2.0, 3.0, 4.0]), isNull);
    });

    test('averages once the minimum count is reached', () {
      expect(trailingSignalBaseline([10.0, 20.0, 30.0, 40.0, 50.0]), 30);
    });

    test('windows to the trailing N days, ignoring older values', () {
      final values = [1000.0, 1000.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0];
      // 9 values, min 5, window 7 -> last 7 are all 10s.
      expect(trailingSignalBaseline(values, windowDays: 7), 10);
    });
  });

  group('ConditionsBaselines.fromSnapshots', () {
    test('excludes "today" from the baseline and averages the rest', () {
      final today = _snap(
        date: DateTime(2026, 1, 6),
        sleepMinutes: 400,
        hrv: 40,
        rhr: 55,
      );
      final snapshots = [
        for (var i = 0; i < 5; i++)
          DailyRecoverySnapshot(
            date: DateTime(2026, 1, i + 1),
            sleepDurationMinutes: 450,
            hrvValue: 50,
            restingHeartRateBpm: 50,
          ),
        today,
      ];
      final baselines = ConditionsBaselines.fromSnapshots(snapshots, today);
      expect(baselines.sleepMinutes, 450);
      expect(baselines.hrvValue, 50);
      expect(baselines.restingHeartRateBpm, 50);
    });
  });

  group('latestRecoverySnapshot', () {
    test('empty list -> null snapshot, not stale', () {
      final result = latestRecoverySnapshot(const []);
      expect(result.snapshot, isNull);
      expect(result.isStale, isFalse);
    });

    test('today has data -> that is returned, not stale', () {
      final today = _snap(sleepMinutes: 400);
      final result = latestRecoverySnapshot([today]);
      expect(result.snapshot, today);
      expect(result.isStale, isFalse);
    });

    test('today is blank -> falls back to the last day with data, stale', () {
      // hasRecoveryData requires one of sleepPerformanceScore/hrv/rhr/
      // respiratoryRate — a bare sleep duration alone does not count, so use
      // HRV here to make "yesterday" genuinely carry recovery data.
      final yesterday = _snap(date: DateTime(2026, 1, 5), hrv: 45);
      final today = DailyRecoverySnapshot(date: DateTime(2026, 1, 6));
      final result = latestRecoverySnapshot([yesterday, today]);
      expect(result.snapshot, yesterday);
      expect(result.isStale, isTrue);
    });
  });

  group('delta helpers', () {
    test('sleepDelta: under baseline', () {
      final delta = sleepDelta(400, 430);
      expect(delta!.label, '30m under');
      expect(delta.up, isFalse);
    });

    test('sleepDelta: over baseline', () {
      final delta = sleepDelta(460, 430);
      expect(delta!.label, '30m over');
      expect(delta.up, isTrue);
    });

    test('sleepDelta: missing inputs -> null', () {
      expect(sleepDelta(null, 430), isNull);
      expect(sleepDelta(400, null), isNull);
    });

    test('hrvDelta: a drop reads as "easier", never "worse"', () {
      final delta = hrvDelta(50, 58);
      expect(delta!.label, '8 ms easier');
      expect(delta.up, isFalse);
    });

    test('hrvDelta: a rise reads as "higher"', () {
      final delta = hrvDelta(66, 58);
      expect(delta!.label, '8 ms higher');
      expect(delta.up, isTrue);
    });

    test('rhrDelta: over baseline', () {
      final delta = rhrDelta(56, 52);
      expect(delta!.label, '4 over');
      expect(delta.up, isTrue);
    });

    test('rhrDelta: under baseline', () {
      final delta = rhrDelta(48, 52);
      expect(delta!.label, '4 under');
      expect(delta.up, isFalse);
    });
  });

  group('conditionsLede', () {
    test('all signals with meaningful deviations weaves sleep + heart', () {
      final today = _snap(sleepMinutes: 432, hrv: 50, rhr: 60);
      final lede = conditionsLede(
        today,
        sleepBaselineMinutes: 450,
        hrvBaseline: 58,
        rhrBaseline: 52,
      );
      expect(
        lede,
        'You slept 7h 12m — 18 minutes under your baseline — '
        'and your heart ran slightly warm overnight.',
      );
    });

    test('partial: sleep only, no baselines -> single clause, no delta', () {
      final today = _snap(sleepMinutes: 432);
      final lede = conditionsLede(
        today,
        sleepBaselineMinutes: null,
        hrvBaseline: null,
        rhrBaseline: null,
      );
      expect(lede, 'You slept 7h 12m.');
    });

    test('partial: HRV only (no RHR) drives the heart clause', () {
      final today = _snap(hrv: 45);
      final lede = conditionsLede(
        today,
        sleepBaselineMinutes: null,
        hrvBaseline: 58,
        rhrBaseline: null,
      );
      expect(lede, 'Your HRV eased a little overnight.');
    });

    test(
      'none: no signals at all -> null (hero falls back to coachHeadline)',
      () {
        final today = _snap();
        final lede = conditionsLede(
          today,
          sleepBaselineMinutes: 450,
          hrvBaseline: 58,
          rhrBaseline: 52,
        );
        expect(lede, isNull);
      },
    );

    test(
      'a single flat heart-only signal still returns a quiet true sentence',
      () {
        final today = _snap(rhr: 52);
        final lede = conditionsLede(
          today,
          sleepBaselineMinutes: null,
          hrvBaseline: null,
          rhrBaseline: 52,
        );
        expect(lede, 'Your resting heart rate held steady overnight.');
      },
    );

    test('never reads as alarmist across a spread of bad-looking inputs', () {
      final cases = [
        conditionsLede(
          _snap(sleepMinutes: 300, hrv: 30, rhr: 70),
          sleepBaselineMinutes: 480,
          hrvBaseline: 70,
          rhrBaseline: 50,
        ),
        conditionsLede(
          _snap(sleepMinutes: 300),
          sleepBaselineMinutes: 480,
          hrvBaseline: null,
          rhrBaseline: null,
        ),
        conditionsLede(
          _snap(rhr: 80),
          sleepBaselineMinutes: null,
          hrvBaseline: null,
          rhrBaseline: 50,
        ),
      ];
      for (final lede in cases) {
        _expectNeverAlarmist(lede);
      }
    });
  });
}
