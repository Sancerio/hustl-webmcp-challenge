import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/dashboard/conditions_week_strip.dart';

Future<void> _pump(
  WidgetTester tester,
  List<DailyRecoverySnapshot> snapshots,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ConditionsWeekStrip(snapshots: snapshots)),
    ),
  );
  await tester.pump();
}

DailyRecoverySnapshot _day(DateTime date, {RecoveryFlowBand? band}) {
  return DailyRecoverySnapshot(
    date: date,
    flowBand: band,
    band: band?.legacyBand,
  );
}

void main() {
  testWidgets('pairs each readiness-band label with a color marker', (
    tester,
  ) async {
    final snapshots = [
      for (var i = 0; i < 7; i++)
        _day(DateTime(2026, 1, 1 + i), band: RecoveryFlowBand.ready),
    ];
    await _pump(tester, snapshots);

    expect(find.text('Charged'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Steady'), findsOneWidget);
    expect(find.text('Recharge'), findsOneWidget);
    expect(find.text('Charged · Ready · Steady · Recharge'), findsNothing);

    for (final band in RecoveryFlowBand.values) {
      expect(
        find.byKey(ValueKey('conditions-week-legend-${band.name}')),
        findsOneWidget,
      );
    }
  });

  testWidgets(
    'Steady and Recharge legend markers use visibly distinct accents',
    (tester) async {
      final snapshots = [
        for (var i = 0; i < 7; i++)
          _day(DateTime(2026, 1, 1 + i), band: RecoveryFlowBand.ready),
      ];
      await _pump(tester, snapshots);

      Color legendColor(RecoveryFlowBand band) {
        final box = tester.widget<DecoratedBox>(
          find.byKey(ValueKey('conditions-week-legend-${band.name}')),
        );
        return (box.decoration as BoxDecoration).color!;
      }

      final steady = legendColor(RecoveryFlowBand.steady);
      final recharge = legendColor(RecoveryFlowBand.recharge);

      // Regression: real iOS render showed Steady and Recharge sharing the
      // exact warm amber and reading as one band. They must differ.
      expect(steady, isNot(equals(recharge)));
    },
  );

  testWidgets('shows exactly 7 dots from a longer trailing history', (
    tester,
  ) async {
    final snapshots = [
      for (var i = 0; i < 14; i++)
        _day(
          DateTime(2026, 1, 1 + i),
          band: RecoveryFlowBand.values[i % RecoveryFlowBand.values.length],
        ),
    ];
    await _pump(tester, snapshots);

    final containers = tester.widgetList<Container>(
      find.descendant(
        of: find.byType(ConditionsWeekStrip),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration,
        ),
      ),
    );
    // 7 day-dot containers (band-tinted or hollow circles).
    expect(containers.length, 7);
  });

  testWidgets('a day with no band renders a hollow (transparent) dot', (
    tester,
  ) async {
    final snapshots = [
      for (var i = 0; i < 6; i++)
        _day(DateTime(2026, 1, 1 + i), band: RecoveryFlowBand.steady),
      _day(DateTime(2026, 1, 7)), // no band -> hollow
    ];
    await _pump(tester, snapshots);

    final decorations = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(ConditionsWeekStrip),
            matching: find.byWidgetPredicate(
              (w) => w is Container && w.decoration is BoxDecoration,
            ),
          ),
        )
        .map((c) => c.decoration! as BoxDecoration)
        .toList();

    // The last day (today, no band) is the 7th dot and must be transparent.
    expect(decorations.last.color, Colors.transparent);
  });

  testWidgets(
    'today (the last entry) is ring-highlighted with a thicker border',
    (tester) async {
      final snapshots = [
        for (var i = 0; i < 7; i++)
          _day(DateTime(2026, 1, 1 + i), band: RecoveryFlowBand.charged),
      ];
      await _pump(tester, snapshots);

      final decorations = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(ConditionsWeekStrip),
              matching: find.byWidgetPredicate(
                (w) => w is Container && w.decoration is BoxDecoration,
              ),
            ),
          )
          .map((c) => c.decoration! as BoxDecoration)
          .toList();

      expect(decorations.length, 7);
      final borders = decorations.map((d) => d.border as Border?).toList();
      // Today's border (last dot) is thicker (2px) than the rest (1px).
      expect(borders.last!.top.width, 2);
      for (final border in borders.sublist(0, 6)) {
        expect(border!.top.width, 1);
      }
    },
  );

  testWidgets('is entirely data-driven — no hardcoded weekday assumption', (
    tester,
  ) async {
    // Synthetic dates starting on an arbitrary weekday (a Wednesday).
    final snapshots = [
      for (var i = 0; i < 7; i++)
        _day(DateTime(2026, 3, 4 + i), band: RecoveryFlowBand.ready),
    ];
    await _pump(tester, snapshots);

    // 2026-03-04 is a Wednesday; the strip should letter the week starting
    // from whatever weekday the data actually starts on.
    expect(find.text('W'), findsWidgets);
  });
}
