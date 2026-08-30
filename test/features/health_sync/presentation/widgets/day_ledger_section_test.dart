import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/domain/models/external_activity.dart';
import 'package:hustl_app/features/health_sync/domain/models/strain_ledger.dart';
import 'package:hustl_app/features/health_sync/domain/services/external_activity_filter.dart';
import 'package:hustl_app/features/health_sync/domain/services/strain_attribution_service.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/dashboard/day_ledger_section.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';

const _attribution = StrainAttributionService();
const _filter = ExternalActivityFilter();

// trainingLoad 275 AU -> strain 14 (mirrors the approved demo fixture).
// activeEnergyKilocalories/exerciseMinutes give the component-budgeted
// attribution model something to allocate; without them every session's
// share is correctly zero ("never invents load"), which would defeat these
// ledger-shape tests.
final _snapshot = DailyRecoverySnapshot(
  date: DateTime(2026, 7, 6),
  trainingLoad: 275,
  strainScore: 14,
  activeEnergyKilocalories: 800,
  exerciseMinutes: 95,
);

final _pushDay = WorkoutSession(
  id: 'hustl-push-day',
  name: 'Push day',
  startTime: DateTime(2026, 7, 6, 17, 10),
  endTime: DateTime(2026, 7, 6, 18, 14),
  exercises: const [],
  isCompleted: true,
  activeEnergyKilocalories: 410,
);

final _morningRun = ExternalActivity(
  platformUuid: 'ext-morning-run',
  sourceName: 'Apple Watch',
  kind: ExternalActivityKind.run,
  start: DateTime(2026, 7, 6, 7, 2),
  end: DateTime(2026, 7, 6, 7, 33),
  activeEnergyKcal: 342,
);

Future<StrainLedger?> _compute({
  DailyRecoverySnapshot? snapshot,
  List<WorkoutSession> sessions = const [],
  List<ExternalActivity> externals = const [],
  bool showExternals = true,
}) {
  return computeDayLedger(
    snapshot: snapshot ?? _snapshot,
    // The fake honors the requested window with the REAL repository semantics
    // (a strict START-time filter) so the section's padded query + overlap
    // filter is exercised, not bypassed.
    readSessions: (start, end) async => sessions
        .where((s) => s.startTime.isAfter(start) && s.startTime.isBefore(end))
        .toList(),
    readExternals: (_, __) async => externals,
    filter: _filter,
    attribution: _attribution,
    hustlWritebackUuids: const {},
    showExternals: showExternals,
  );
}

double _displayedSum(StrainLedger ledger) {
  final tenths =
      ledger.entries.fold<int>(
        0,
        (acc, e) => acc + (e.loadPoints * 10).round(),
      ) +
      (ledger.ambientLoadPoints * 10).round();
  return tenths / 10;
}

void main() {
  group('computeDayLedger', () {
    test(
      'itemizes the day’s sessions and totals to the strain score',
      () async {
        final ledger = await _compute(
          sessions: [_pushDay],
          externals: [_morningRun],
        );

        expect(ledger, isNotNull);
        expect(ledger!.entries.length, 2);
        expect(
          ledger.entries.map((e) => e.label),
          containsAll(<String>['Push day', 'Apple Watch']),
        );
        // The receipt's honesty invariant: displayed rows + ambient sum EXACTLY
        // to the strain score the hero shows.
        expect(_displayedSum(ledger), ledger.strainScore.toDouble());
      },
    );

    test('returns null when there is no strain score', () async {
      final ledger = await _compute(
        snapshot: DailyRecoverySnapshot(date: DateTime(2026, 7, 6)),
        sessions: [_pushDay],
        externals: [_morningRun],
      );
      expect(ledger, isNull);
    });

    test(
      'WORKOUT read denied → Hustl-only receipt (externals simply absent)',
      () async {
        // The silent reader yields nothing when the WORKOUT scope is absent;
        // the receipt still itemizes Hustl rows + ambient and never prompts.
        final ledger = await _compute(
          sessions: [_pushDay],
          externals: const [],
        );

        expect(ledger, isNotNull);
        expect(ledger!.entries.length, 1);
        expect(ledger.entries.single.source, StrainSource.hustl);
        expect(_displayedSum(ledger), ledger.strainScore.toDouble());
      },
    );

    test('returns null on an ambient-only day (no session entries)', () async {
      // Measured strain but nothing to itemize -> the receipt never renders,
      // even though the ledger itself is not empty.
      final ledger = await _compute(sessions: const [], externals: const []);
      expect(ledger, isNull);
    });

    test('drops incomplete sessions before attributing', () async {
      final incomplete = _pushDay.copyWith(isCompleted: false);
      final ledger = await _compute(
        sessions: [incomplete],
        externals: const [],
      );
      // Only an incomplete session and no externals -> nothing to itemize.
      expect(ledger, isNull);
    });

    test(
      'derives the day window from the SNAPSHOT date, never the wall clock',
      () async {
        // A fallback day: the dashboard shows July 5 ("as of" an earlier day)
        // while a workout was logged "today" (July 6). The July-6 session must
        // NOT be attributed to the July-5 snapshot...
        final fallbackSnapshot = DailyRecoverySnapshot(
          date: DateTime(2026, 7, 5),
          trainingLoad: 275,
          strainScore: 14,
        );
        final todaySession = _pushDay; // July 6, 17:10–18:14.
        final excluded = await _compute(
          snapshot: fallbackSnapshot,
          sessions: [todaySession],
        );
        expect(excluded, isNull);

        // ...while a session on the snapshot's own day IS included.
        final snapshotDaySession = _pushDay.copyWith(
          startTime: DateTime(2026, 7, 5, 17, 10),
          endTime: DateTime(2026, 7, 5, 18, 14),
        );
        final included = await _compute(
          snapshot: fallbackSnapshot,
          sessions: [snapshotDaySession],
        );
        expect(included, isNotNull);
        expect(included!.entries.single.label, 'Push day');
      },
    );

    test(
      'a session crossing midnight INTO the day appears on that day’s ledger',
      () async {
        // 23:30 July 5 -> 00:30 July 6: the repository's start-time filter
        // would drop it from an exact July-6 window; the padded query + overlap
        // filter must keep it on July 6.
        final midnight = _pushDay.copyWith(
          id: 'hustl-midnight',
          name: 'Night session',
          startTime: DateTime(2026, 7, 5, 23, 30),
          endTime: DateTime(2026, 7, 6, 0, 30),
        );
        final ledger = await _compute(sessions: [midnight]);
        expect(ledger, isNotNull);
        expect(ledger!.entries.single.label, 'Night session');
      },
    );

    test(
      'toggle OFF hides external rows only; ambient absorbs their share',
      () async {
        final on = await _compute(
          sessions: [_pushDay],
          externals: [_morningRun],
          showExternals: true,
        );
        final off = await _compute(
          sessions: [_pushDay],
          externals: [_morningRun],
          showExternals: false,
        );

        expect(on, isNotNull);
        expect(off, isNotNull);

        // Hustl row survives both; the external row is present only when ON.
        expect(
          on!.entries.any((e) => e.source == StrainSource.external),
          isTrue,
        );
        expect(
          off!.entries.any((e) => e.source == StrainSource.external),
          isFalse,
        );
        expect(off.entries.map((e) => e.label), contains('Push day'));

        // The external's share is re-absorbed into ambient, not renormalized:
        // ambient is strictly larger with externals hidden, and the total still
        // equals the strain score.
        expect(off.ambientLoadPoints, greaterThan(on.ambientLoadPoints));
        expect(_displayedSum(off), off.strainScore.toDouble());
      },
    );
  });

  group('DayLedgerSection', () {
    Future<void> pump(WidgetTester tester, DayLedgerLoad loader) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DayLedgerSection(snapshot: _snapshot, loader: loader),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders the header and receipt when a ledger resolves', (
      tester,
    ) async {
      final ledger = await _compute(
        sessions: [_pushDay],
        externals: [_morningRun],
      );
      await pump(tester, (_) async => ledger);

      expect(find.text("The day's ledger"), findsOneWidget);
      expect(find.byKey(const Key('dayLedgerReceipt')), findsOneWidget);
    });

    testWidgets('renders zero height (no header) when the ledger is null', (
      tester,
    ) async {
      await pump(tester, (_) async => null);

      expect(find.text("The day's ledger"), findsNothing);
      expect(find.byKey(const Key('dayLedgerReceipt')), findsNothing);
    });

    Future<void> pumpWithSnapshot(
      WidgetTester tester,
      DailyRecoverySnapshot snapshot,
      StrainLedger? ledger,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DayLedgerSection(
                snapshot: snapshot,
                loader: (_) async => ledger,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets("threads the snapshot's typicalStrainScore into the receipt's "
        '"typical {n}" sub-line', (tester) async {
      final ledger = await _compute(
        sessions: [_pushDay],
        externals: [_morningRun],
      );
      final snapshot = DailyRecoverySnapshot(
        date: DateTime(2026, 7, 6),
        trainingLoad: 275,
        strainScore: 14,
        typicalStrainScore: 9,
      );
      await pumpWithSnapshot(tester, snapshot, ledger);

      expect(find.byKey(const Key('dayLedgerReceipt')), findsOneWidget);
      expect(find.text('typical 9'), findsOneWidget);
    });

    testWidgets(
      'omits the "typical" sub-line when the snapshot has no typical strain',
      (tester) async {
        final ledger = await _compute(
          sessions: [_pushDay],
          externals: [_morningRun],
        );
        // _snapshot leaves typicalStrainScore null (still calibrating).
        await pumpWithSnapshot(tester, _snapshot, ledger);

        expect(find.byKey(const Key('dayLedgerReceipt')), findsOneWidget);
        expect(find.textContaining('typical'), findsNothing);
      },
    );

    testWidgets(
      'a Settings toggle flip updates the still-mounted section by ITSELF '
      '(listener schedules the rebuild — no external re-pump of the tree)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = PreferencesService();
        await prefs.init();
        GetIt.instance.registerSingleton<PreferencesService>(prefs);
        addTearDown(() => GetIt.instance.reset(dispose: true));

        // The loader honors the toggle value the section hands it, exactly as
        // the production GetIt loader does.
        Future<StrainLedger?> loader(bool showExternals) => _compute(
          sessions: [_pushDay],
          externals: [_morningRun],
          showExternals: showExternals,
        );

        // Pump the tree ONCE.
        await pump(tester, loader);
        expect(find.text('Run · Apple Watch'), findsOneWidget);
        expect(find.text('Strength · Hustl'), findsOneWidget);

        // Flip the pref through the SERVICE SETTER only — as Settings does on
        // another route. No new pumpWidget: the section's own subscription must
        // schedule the rebuild.
        await prefs.setShowExternalWorkoutsInDay(false);
        await tester.pumpAndSettle();

        expect(find.text('Run · Apple Watch'), findsNothing);
        expect(find.text('Strength · Hustl'), findsOneWidget);
        expect(find.text("The day's ledger"), findsOneWidget);
      },
    );

    testWidgets(
      'never renders stale rows while a replaced load is pending — the whole '
      'section (header included) is absent for the waiting frames',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = PreferencesService();
        await prefs.init();
        GetIt.instance.registerSingleton<PreferencesService>(prefs);
        addTearDown(() => GetIt.instance.reset(dispose: true));

        final onLedger = await _compute(
          sessions: [_pushDay],
          externals: [_morningRun],
          showExternals: true,
        );
        final offLedger = await _compute(
          sessions: [_pushDay],
          externals: [_morningRun],
          showExternals: false,
        );

        // Completer-driven loader: the TEST controls when each load finishes.
        final completers = <bool, Completer<StrainLedger?>>{};
        Future<StrainLedger?> loader(bool showExternals) {
          final completer = Completer<StrainLedger?>();
          completers[showExternals] = completer;
          return completer.future;
        }

        await pump(tester, loader);
        completers[true]!.complete(onLedger);
        await tester.pumpAndSettle();
        expect(find.text('Run · Apple Watch'), findsOneWidget);

        // Flip via the service setter; the section swaps in a NEW, still-
        // PENDING future. One frame later nothing stale may render: no
        // external row, and — consistent with self-gating — no header either.
        await prefs.setShowExternalWorkoutsInDay(false);
        await tester.pump();

        expect(find.text('Run · Apple Watch'), findsNothing);
        expect(find.text('Strength · Hustl'), findsNothing);
        expect(find.text("The day's ledger"), findsNothing);
        expect(find.byKey(const Key('dayLedgerReceipt')), findsNothing);

        // Completing the replacement load brings back the Hustl-only receipt.
        completers[false]!.complete(offLedger);
        await tester.pumpAndSettle();

        expect(find.text('Run · Apple Watch'), findsNothing);
        expect(find.text('Strength · Hustl'), findsOneWidget);
        expect(find.text("The day's ledger"), findsOneWidget);
      },
    );

    testWidgets('a toggle flip after the section is disposed does not throw', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService();
      await prefs.init();
      GetIt.instance.registerSingleton<PreferencesService>(prefs);
      addTearDown(() => GetIt.instance.reset(dispose: true));

      await pump(
        tester,
        (show) =>
            _compute(sessions: [_pushDay], externals: [], showExternals: show),
      );
      expect(find.byKey(const Key('dayLedgerReceipt')), findsOneWidget);

      // Dispose the section by replacing the tree, then flip the pref: the
      // listener must have been removed (no setState-after-dispose throw).
      await tester.pumpWidget(const SizedBox.shrink());
      await prefs.setShowExternalWorkoutsInDay(false);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
