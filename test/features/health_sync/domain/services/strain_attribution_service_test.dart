import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/domain/models/external_activity.dart';
import 'package:hustl_app/features/health_sync/domain/models/strain_ledger.dart';
import 'package:hustl_app/features/health_sync/domain/services/strain_attribution_service.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';

DailyRecoverySnapshot _day({
  required int? strainScore,
  double? trainingLoad,
  double energyKcal = 0,
  double exerciseMinutes = 0,
  int steps = 0,
  DateTime? date,
}) {
  final load =
      trainingLoad ??
      (energyKcal * 0.08 + exerciseMinutes * 1.4 + steps / 1000.0 * 1.2);
  return DailyRecoverySnapshot(
    date: date ?? DateTime.utc(2025, 6, 1),
    trainingLoad: load,
    strainScore: strainScore,
    activeEnergyKilocalories: energyKcal,
    exerciseMinutes: exerciseMinutes,
    steps: steps,
  );
}

ExternalActivity _ext({
  required String uuid,
  ExternalActivityKind kind = ExternalActivityKind.run,
  double? energy,
  DateTime? start,
  DateTime? end,
  String source = 'Strava',
  String? activityName,
}) {
  final s = start ?? DateTime.utc(2025, 6, 1, 8);
  final e = end ?? DateTime.utc(2025, 6, 1, 9);
  return ExternalActivity(
    platformUuid: uuid,
    sourceName: source,
    kind: kind,
    start: s,
    end: e,
    activeEnergyKcal: energy,
    activityName: activityName,
  );
}

WorkoutSession _hustl({
  required String id,
  double? energy,
  DateTime? start,
  DateTime? end,
}) {
  return WorkoutSession(
    id: id,
    name: 'Lift',
    startTime: start ?? DateTime.utc(2025, 6, 1, 18),
    endTime: end ?? DateTime.utc(2025, 6, 1, 19),
    exercises: const [],
    isCompleted: true,
    activeEnergyKilocalories: energy,
  );
}

/// The load-bearing invariant: entry load points + ambient sum EXACTLY to the
/// INPUT day's strain score (to 1 dp), and attribution never adds load. The
/// expected score is passed in from the fixture so a ledger that mangled its
/// own strainScore could not vacuously satisfy the check.
void _expectExactTotal(StrainLedger ledger, int inputStrainScore) {
  expect(
    ledger.strainScore,
    inputStrainScore,
    reason: 'ledger must preserve the input strain score',
  );
  final sum =
      ledger.entries.fold<double>(0, (a, e) => a + e.loadPoints) +
      ledger.ambientLoadPoints;
  expect(
    (sum * 10).round(),
    inputStrainScore * 10,
    reason:
        'entries + ambient must equal the input strainScore exactly '
        '(tenths)',
  );
  // Never adds load: no single entry exceeds the strain score.
  for (final e in ledger.entries) {
    expect(e.loadPoints, lessThanOrEqualTo(inputStrainScore.toDouble()));
    expect(e.loadPoints, greaterThanOrEqualTo(0));
  }
  expect(ledger.ambientLoadPoints, greaterThanOrEqualTo(0));
}

void main() {
  const service = StrainAttributionService();

  group('empty and ambient-only cases', () {
    test(
      'no sessions or externals but measured strain -> ambient-only ledger',
      () {
        final ledger = service.attribute(
          day: _day(strainScore: 12, trainingLoad: 300),
          hustlSessions: const [],
          externals: const [],
        );
        expect(ledger.entries, isEmpty);
        expect(ledger.strainScore, 12);
        expect(ledger.ambientLoadPoints, 12.0);
        // Ambient-only is NOT empty: a measured day must never be suppressed
        // by a caller's `if (ledger.isEmpty) hide()`.
        expect(ledger.isEmpty, isFalse);
        expect(ledger.hasSessionEntries, isFalse);
        _expectExactTotal(ledger, 12);
      },
    );

    test('ambient-only ledger preserves the whole measured strain', () {
      final ledger = service.attribute(
        day: _day(strainScore: 7, trainingLoad: 120),
        hustlSessions: const [],
        externals: const [],
      );
      expect(ledger.entries, isEmpty);
      expect(ledger.strainScore, 7);
      expect(ledger.ambientLoadPoints, 7.0);
      expect(ledger.isEmpty, isFalse);
      expect(ledger.hasSessionEntries, isFalse);
      _expectExactTotal(ledger, 7);
    });

    test('StrainLedger.empty() is empty and has no session entries', () {
      const ledger = StrainLedger.empty();
      expect(ledger.isEmpty, isTrue);
      expect(ledger.hasSessionEntries, isFalse);
    });

    test('zero strain -> empty ledger even with sessions', () {
      final ledger = service.attribute(
        day: _day(strainScore: 0, trainingLoad: 10),
        hustlSessions: [_hustl(id: 's1', energy: 200)],
        externals: const [],
      );
      expect(ledger.isEmpty, isTrue);
    });

    test('null strain -> empty ledger', () {
      final ledger = service.attribute(
        day: _day(strainScore: null, trainingLoad: 300),
        hustlSessions: const [],
        externals: [_ext(uuid: 'a', energy: 300)],
      );
      expect(ledger.isEmpty, isTrue);
    });

    test(
      'in-progress Hustl session (no endTime) is ignored -> ambient-only',
      () {
        final ledger = service.attribute(
          day: _day(strainScore: 10, trainingLoad: 300),
          hustlSessions: [
            WorkoutSession(
              id: 'live',
              name: 'Live',
              startTime: DateTime.utc(2025, 6, 1, 8),
              exercises: const [],
            ),
          ],
          externals: const [],
        );
        expect(ledger.entries, isEmpty);
        expect(ledger.strainScore, 10);
        expect(ledger.ambientLoadPoints, 10.0);
        _expectExactTotal(ledger, 10);
      },
    );
  });

  group('attribution math (component-budgeted anchors)', () {
    test('anchor 1: single soccer, exercise budget covers duration', () {
      final day = _day(
        strainScore: 11,
        energyKcal: 900,
        exerciseMinutes: 70,
        steps: 8000,
      );
      final ledger = service.attribute(
        day: day,
        hustlSessions: const [],
        externals: [
          _ext(
            uuid: 'soccer',
            kind: ExternalActivityKind.other,
            energy: 737,
            start: DateTime.utc(2025, 6, 1, 17),
            end: DateTime.utc(2025, 6, 1, 18, 4),
          ),
        ],
      );
      expect(ledger.entries.length, 1);
      expect(ledger.entries.single.share, closeTo(0.8272, 1e-3));
      expect(ledger.entries.single.loadPoints, 9.1);
      expect(ledger.ambientLoadPoints, 1.9);
      _expectExactTotal(ledger, 11);
    });

    test('anchor 2: exercise budget smaller than duration (paused / '
        'low-intensity) caps exercise credit', () {
      final day = _day(
        strainScore: 5,
        energyKcal: 300,
        exerciseMinutes: 25,
        steps: 5000,
      );
      final ledger = service.attribute(
        day: day,
        hustlSessions: const [],
        externals: [
          _ext(
            uuid: 'paused',
            kind: ExternalActivityKind.other,
            energy: 200,
            start: DateTime.utc(2025, 6, 1, 17),
            end: DateTime.utc(2025, 6, 1, 18, 4),
          ),
        ],
      );
      expect(ledger.entries.single.share, closeTo(0.7846, 1e-3));
      expect(ledger.entries.single.loadPoints, 3.9);
      expect(ledger.ambientLoadPoints, 1.1);
      _expectExactTotal(ledger, 5);
    });

    test('anchor 3: overlapping different-kind sessions are NOT '
        'double-counted', () {
      final day = _day(
        strainScore: 10,
        energyKcal: 0,
        exerciseMinutes: 120,
        steps: 0,
      );
      final ledger = service.attribute(
        day: day,
        hustlSessions: const [],
        externals: [
          _ext(
            uuid: 'A',
            kind: ExternalActivityKind.run,
            start: DateTime.utc(2025, 6, 1, 17),
            end: DateTime.utc(2025, 6, 1, 18),
          ),
          _ext(
            uuid: 'B',
            kind: ExternalActivityKind.ride,
            start: DateTime.utc(2025, 6, 1, 17, 30),
            end: DateTime.utc(2025, 6, 1, 18, 30),
          ),
          _ext(
            uuid: 'C',
            kind: ExternalActivityKind.run,
            start: DateTime.utc(2025, 6, 1, 20),
            end: DateTime.utc(2025, 6, 1, 20, 30),
          ),
        ],
      );
      expect(ledger.entries.map((e) => e.id), ['A', 'B', 'C']);
      expect(ledger.entries[0].share, closeTo(0.375, 1e-3));
      expect(ledger.entries[1].share, closeTo(0.375, 1e-3));
      // If overlaps were double-counted, C's share would be 30/150 = 0.2 —
      // this assertion is the meaningful guard against that bug.
      expect(ledger.entries[2].share, closeTo(0.25, 1e-3));
      expect(ledger.ambientLoadPoints, 0);
      _expectExactTotal(ledger, 10);
    });

    test('anchor 4: day measured no energy AND no exercise -> session '
        'invents nothing', () {
      final day = _day(
        strainScore: 3,
        energyKcal: 0,
        exerciseMinutes: 0,
        steps: 10000,
      );
      final ledger = service.attribute(
        day: day,
        hustlSessions: const [],
        externals: [
          _ext(
            uuid: 'run',
            kind: ExternalActivityKind.run,
            start: DateTime.utc(2025, 6, 1, 17),
            end: DateTime.utc(2025, 6, 1, 18),
          ),
        ],
      );
      expect(ledger.entries.single.loadPoints, 0.0);
      expect(ledger.ambientLoadPoints, 3.0);
      _expectExactTotal(ledger, 3);
    });

    test('anchor 5: energy-absent session claims the residual energy '
        'budget (bounded)', () {
      final day = _day(
        strainScore: 4,
        energyKcal: 500,
        exerciseMinutes: 0,
        steps: 0,
      );
      final ledger = service.attribute(
        day: day,
        hustlSessions: const [],
        externals: [
          _ext(
            uuid: 'run',
            kind: ExternalActivityKind.run,
            start: DateTime.utc(2025, 6, 1, 17),
            end: DateTime.utc(2025, 6, 1, 18),
          ),
        ],
      );
      expect(ledger.entries.single.share, closeTo(1.0, 1e-3));
      expect(ledger.entries.single.loadPoints, 4.0);
      expect(ledger.ambientLoadPoints, 0.0);
      _expectExactTotal(ledger, 4);
    });

    test('anchor 6: energy cap when recorded kcal exceeds the day budget', () {
      final day = _day(
        strainScore: 18,
        energyKcal: 100,
        exerciseMinutes: 0,
        steps: 0,
      );
      final ledger = service.attribute(
        day: day,
        hustlSessions: const [],
        externals: [
          _ext(
            uuid: 'A',
            energy: 1000,
            start: DateTime.utc(2025, 6, 1, 7),
            end: DateTime.utc(2025, 6, 1, 8),
          ),
          _ext(
            uuid: 'B',
            energy: 1000,
            start: DateTime.utc(2025, 6, 1, 9),
            end: DateTime.utc(2025, 6, 1, 10),
          ),
        ],
      );
      expect(ledger.entries[0].share, closeTo(0.5, 1e-3));
      expect(ledger.entries[1].share, closeTo(0.5, 1e-3));
      expect(ledger.ambientLoadPoints, 0);
      _expectExactTotal(ledger, 18);
    });

    test('anchor 7: mixed Hustl + external still both weighted, exercise '
        'included', () {
      final day = _day(
        strainScore: 12,
        energyKcal: 400,
        exerciseMinutes: 60,
        steps: 0,
      );
      final ledger = service.attribute(
        day: day,
        hustlSessions: [
          _hustl(
            id: 'H',
            energy: 200,
            start: DateTime.utc(2025, 6, 1, 6),
            end: DateTime.utc(2025, 6, 1, 6, 30),
          ),
        ],
        externals: [
          _ext(
            uuid: 'E',
            kind: ExternalActivityKind.run,
            energy: 200,
            start: DateTime.utc(2025, 6, 1, 12),
            end: DateTime.utc(2025, 6, 1, 12, 30),
          ),
        ],
      );
      expect(ledger.entries.map((e) => e.id), ['H', 'E']);
      expect(ledger.entries[0].source, StrainSource.hustl);
      expect(ledger.entries[1].source, StrainSource.external);
      expect(ledger.entries[0].share, closeTo(0.5, 1e-3));
      expect(ledger.entries[1].share, closeTo(0.5, 1e-3));
      expect(ledger.ambientLoadPoints, 0);
      expect(ledger.isEmpty, isFalse);
      expect(ledger.hasSessionEntries, isTrue);
      _expectExactTotal(ledger, 12);
    });

    test('external activityName flows through to the ledger entry', () {
      final ledger = service.attribute(
        day: _day(strainScore: 8, energyKcal: 500, exerciseMinutes: 0),
        hustlSessions: const [],
        externals: [
          _ext(
            uuid: 'A',
            kind: ExternalActivityKind.other,
            energy: 500,
            activityName: 'Soccer',
          ),
        ],
      );
      expect(ledger.entries.single.activityName, 'Soccer');
      _expectExactTotal(ledger, 8);
    });
  });

  group('robustness fixes (clipping, sanitization, denominator floor)', () {
    test('cross-midnight recorded kcal are prorated on adjacent days', () {
      final activity = _ext(
        uuid: 'overnight',
        energy: 400,
        start: DateTime.utc(2025, 6, 1, 23),
        end: DateTime.utc(2025, 6, 2, 3),
      );

      final firstDay = service.attribute(
        day: _day(
          strainScore: 8,
          energyKcal: 400,
          exerciseMinutes: 0,
          date: DateTime.utc(2025, 6, 1),
        ),
        hustlSessions: const [],
        externals: [activity],
      );
      final secondDay = service.attribute(
        day: _day(
          strainScore: 8,
          energyKcal: 400,
          exerciseMinutes: 0,
          date: DateTime.utc(2025, 6, 2),
        ),
        hustlSessions: const [],
        externals: [activity],
      );

      // One of four hours falls on June 1; three fall on June 2.
      expect(firstDay.entries.single.share, closeTo(0.25, 1e-9));
      expect(secondDay.entries.single.share, closeTo(0.75, 1e-9));
      expect(firstDay.entries.single.loadPoints, 2.0);
      expect(secondDay.entries.single.loadPoints, 6.0);
      _expectExactTotal(firstDay, 8);
      _expectExactTotal(secondDay, 8);
    });

    test('fully in-day recorded kcal retain a duration ratio of one', () {
      final ledger = service.attribute(
        day: _day(strainScore: 8, energyKcal: 400, exerciseMinutes: 0),
        hustlSessions: const [],
        externals: [
          _ext(
            uuid: 'in-day',
            energy: 200,
            start: DateTime.utc(2025, 6, 1, 8),
            end: DateTime.utc(2025, 6, 1, 9),
          ),
        ],
      );

      expect(ledger.entries.single.share, closeTo(0.5, 1e-9));
      expect(ledger.entries.single.loadPoints, 4.0);
      _expectExactTotal(ledger, 8);
    });

    test('recorded kcal on a non-positive interval claim no energy', () {
      final instant = DateTime.utc(2025, 6, 1, 8);
      final ledger = service.attribute(
        day: _day(strainScore: 8, energyKcal: 400, exerciseMinutes: 0),
        hustlSessions: const [],
        externals: [
          _ext(uuid: 'invalid', energy: 400, start: instant, end: instant),
        ],
      );

      expect(ledger.entries.single.share, 0.0);
      expect(ledger.entries.single.loadPoints, 0.0);
      expect(ledger.ambientLoadPoints, 8.0);
      _expectExactTotal(ledger, 8);
    });

    test('cross-midnight session is clipped to the day window for effective '
        'minutes, but its displayed start stays the original time', () {
      final day = _day(
        strainScore: 6,
        energyKcal: 0,
        exerciseMinutes: 30,
        date: DateTime.utc(2025, 6, 1),
      );
      final originalStartA = DateTime.utc(2025, 5, 31, 12);
      final ledger = service.attribute(
        day: day,
        hustlSessions: const [],
        externals: [
          // Only the last 1 minute (2025-06-01 00:00 -> 00:01) is in-day.
          _ext(
            uuid: 'A',
            kind: ExternalActivityKind.walk,
            start: originalStartA,
            end: DateTime.utc(2025, 6, 1, 0, 1),
          ),
          _ext(
            uuid: 'B',
            kind: ExternalActivityKind.run,
            start: DateTime.utc(2025, 6, 1, 8),
            end: DateTime.utc(2025, 6, 1, 8, 29),
          ),
        ],
      );
      final a = ledger.entries.singleWhere((e) => e.id == 'A');
      final b = ledger.entries.singleWhere((e) => e.id == 'B');
      expect(a.share, closeTo(1 / 30, 1e-3));
      expect(b.share, closeTo(29 / 30, 1e-3));
      expect(a.loadPoints, lessThan(b.loadPoints));
      // Clipping only affects the effective-minutes math, never display.
      expect(a.start, originalStartA);
      _expectExactTotal(ledger, 6);
    });

    test(
      'non-finite kcal does not crash and yields a finite, valid ledger',
      () {
        final day = _day(
          strainScore: 10,
          energyKcal: 100,
          exerciseMinutes: 0,
          trainingLoad: 8,
        );
        final ledger = service.attribute(
          day: day,
          hustlSessions: [
            _hustl(
              id: 'H',
              energy: double.infinity,
              start: DateTime.utc(2025, 6, 1, 18),
              end: DateTime.utc(2025, 6, 1, 19),
            ),
          ],
          externals: const [],
        );
        for (final e in ledger.entries) {
          expect(e.loadPoints.isFinite, isTrue);
        }
        expect(ledger.ambientLoadPoints.isFinite, isTrue);
        _expectExactTotal(ledger, 10);
      },
    );

    test('huge finite kcal is capped, not overflowed to zero shares', () {
      final day = _day(strainScore: 12, energyKcal: 500, exerciseMinutes: 0);
      final ledger = service.attribute(
        day: day,
        hustlSessions: const [],
        externals: [
          _ext(
            uuid: 'A',
            energy: 1e308,
            start: DateTime.utc(2025, 6, 1, 8),
            end: DateTime.utc(2025, 6, 1, 8, 30),
          ),
          _ext(
            uuid: 'B',
            energy: 1e308,
            start: DateTime.utc(2025, 6, 1, 9),
            end: DateTime.utc(2025, 6, 1, 9, 30),
          ),
        ],
      );
      expect(ledger.entries[0].share, closeTo(0.5, 1e-3));
      expect(ledger.entries[1].share, closeTo(0.5, 1e-3));
      expect(ledger.entries[0].share, greaterThan(0));
      expect(ledger.entries[1].share, greaterThan(0));
      expect(ledger.ambientLoadPoints, closeTo(0, 1e-9));
      _expectExactTotal(ledger, 12);
    });

    test('inconsistent trainingLoad smaller than its own components: the '
        'denominator floor (not the post-hoc cap) bounds the share', () {
      // Components imply E*0.08 + M*1.4 = 1000*0.08 + 60*1.4 = 164 AU, far
      // above the deliberately-inconsistent trainingLoad of 10. The session
      // claims only HALF of them (30 of the 60 exercise minutes + 500 of the
      // 1000 kcal): sessionLoad = 30*1.4 + 500*0.08 = 42 + 40 = 82 AU.
      //
      // With the denominator FLOORED at the component budget (164), share =
      // 82/164 = 0.5 and ambient is a real 0.5*9 = 4.5. The OLD post-hoc
      // `shareSum` cap (denominator = trainingLoad = 10) would instead force
      // share -> 1.0 and ambient -> 0, so the 0.5 / nonzero-ambient assertions
      // below fail under that regression. This is what distinguishes the two.
      final day = _day(
        strainScore: 9,
        energyKcal: 1000,
        exerciseMinutes: 60,
        trainingLoad: 10,
      );
      final ledger = service.attribute(
        day: day,
        hustlSessions: const [],
        externals: [
          _ext(
            uuid: 'A',
            energy: 500,
            start: DateTime.utc(2025, 6, 1, 8),
            end: DateTime.utc(2025, 6, 1, 8, 30),
          ),
        ],
      );
      expect(ledger.entries.single.share, closeTo(0.5, 1e-3));
      expect(ledger.entries.single.loadPoints, closeTo(4.5, 1e-9));
      expect(ledger.ambientLoadPoints, closeTo(4.5, 1e-9));
      _expectExactTotal(ledger, 9);
    });

    test('a non-midnight day.date is normalized to its calendar day for '
        'clipping', () {
      // The snapshot date carries a non-midnight time-of-day. The window must
      // still be the whole calendar day [Jun 1 00:00, Jun 2 00:00), so a normal
      // in-day session is credited in full. (Using `date` raw as the window
      // start would clip this 08:00-09:00 session — which is before 15:30 — to
      // nothing, giving share 0.)
      final ledger = service.attribute(
        day: _day(
          strainScore: 6,
          energyKcal: 0,
          exerciseMinutes: 60,
          date: DateTime.utc(2025, 6, 1, 15, 30),
        ),
        hustlSessions: const [],
        externals: [
          _ext(
            uuid: 'A',
            kind: ExternalActivityKind.run,
            start: DateTime.utc(2025, 6, 1, 8),
            end: DateTime.utc(2025, 6, 1, 9),
          ),
        ],
      );
      expect(ledger.entries.single.share, closeTo(1.0, 1e-3));
      _expectExactTotal(ledger, 6);
    });

    test('asymmetric Hustl + external shares are hand-derivable (guards '
        'against a symmetric-only allocator)', () {
      // sessionLoad(H) = exerciseAu + energyAu = 30*1.4 + 250*0.08
      //                = 42 + 20 = 62
      // sessionLoad(E) = 60*1.4 + 100*0.08 = 84 + 8 = 92
      // effectiveDayLoad = dayLoad = 400*0.08 + 90*1.4 = 32 + 126 = 158
      // share(H) = 62/158 = 31/79 ≈ 0.39241
      // share(E) = 92/158 = 46/79 ≈ 0.58228
      // ambient  = 1 - 77/79 = 2/79 ≈ 0.02532
      final day = _day(strainScore: 12, energyKcal: 400, exerciseMinutes: 90);
      final ledger = service.attribute(
        day: day,
        hustlSessions: [
          _hustl(
            id: 'H',
            energy: 250,
            start: DateTime.utc(2025, 6, 1, 6),
            end: DateTime.utc(2025, 6, 1, 6, 30),
          ),
        ],
        externals: [
          _ext(
            uuid: 'E',
            kind: ExternalActivityKind.run,
            energy: 100,
            start: DateTime.utc(2025, 6, 1, 12),
            end: DateTime.utc(2025, 6, 1, 13),
          ),
        ],
      );
      expect(ledger.entries.map((e) => e.id), ['H', 'E']);
      expect(ledger.entries[0].share, closeTo(31 / 79, 1e-4));
      expect(ledger.entries[1].share, closeTo(46 / 79, 1e-4));
      expect(ledger.ambientLoadPoints, closeTo(2 / 79 * 12, 0.05));
      // Shares are asymmetric, not equal — guards a symmetric-only bug.
      expect(
        ledger.entries[0].share,
        isNot(closeTo(ledger.entries[1].share, 1e-3)),
      );
      _expectExactTotal(ledger, 12);
    });
  });

  group('largest-remainder exactness across many fixtures', () {
    test('entries + ambient always equal strainScore to 1 dp', () {
      var checked = 0;
      for (var strain = 1; strain <= 21; strain++) {
        for (final n in [1, 2, 3, 5]) {
          final externals = <ExternalActivity>[];
          for (var i = 0; i < n; i++) {
            externals.add(
              _ext(
                uuid: 'e$strain-$i',
                // vary energy so shares are irregular fractions
                energy: 37.0 * (i + 1) + strain * 3.0,
                start: DateTime.utc(2025, 6, 1, 6 + i),
                end: DateTime.utc(2025, 6, 1, 6 + i, 40 + i),
              ),
            );
          }
          final ledger = service.attribute(
            day: _day(
              strainScore: strain,
              energyKcal: 120 + strain * 5,
              exerciseMinutes: 20 + n * 10,
            ),
            hustlSessions: const [],
            externals: externals,
          );
          _expectExactTotal(ledger, strain);
          checked++;
        }
      }
      expect(checked, greaterThanOrEqualTo(20));
    });
  });
}
