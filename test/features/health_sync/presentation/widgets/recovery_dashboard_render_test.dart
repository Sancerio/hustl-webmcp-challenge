import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/dashboard/health_dashboard_today.dart';

// TodayOverviewGroup end-to-end: the "Conditions Report" hero (band word +
// lede + readiness/confidence/learn-more), the instruments row, the coach's
// route call (CoachCard, unchanged pipeline), and the 7-day strip. Renders
// through a GoRouter host since the hero/instruments now push /health/night.
Future<void> _pump(WidgetTester tester, DailyRecoverySnapshot? snapshot) async {
  final router = GoRouter(
    initialLocation: '/health',
    routes: [
      GoRoute(
        path: '/health',
        builder: (context, state) => Scaffold(
          body: SingleChildScrollView(
            child: TodayOverviewGroup(
              snapshot: snapshot,
              recoverySnapshots: snapshot == null ? const [] : [snapshot],
              lastSyncedAt: null,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/health/night',
        builder: (context, state) => const Scaffold(body: Text('Night')),
      ),
      GoRoute(
        path: '/learn/:slug',
        builder: (context, state) => const Scaffold(body: Text('Learn')),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();
}

DailyRecoverySnapshot _snapshot({
  required RecoveryFlowBand flowBand,
  required RecoveryConfidence confidence,
  double readiness = 70,
  double recovery = 66,
  int baselineCoverageDays = 21,
  bool isCalibrating = false,
  List<String> anomalyFlags = const [],
}) {
  return DailyRecoverySnapshot(
    date: DateTime(2025, 3, 1),
    readinessScore: readiness,
    recoveryScore: recovery,
    sleepDurationMinutes: 430,
    sleepPerformanceScore: 82,
    strainScore: 11,
    loadRatio: 1.05,
    band: flowBand.legacyBand,
    flowBand: flowBand,
    confidence: confidence,
    baselineCoverageDays: baselineCoverageDays,
    isCalibrating: isCalibrating,
    anomalyFlags: anomalyFlags,
  );
}

void main() {
  group('TodayOverviewGroup band rendering', () {
    testWidgets('renders the Charged band word and high-confidence qualifier', (
      tester,
    ) async {
      await _pump(
        tester,
        _snapshot(
          flowBand: RecoveryFlowBand.charged,
          confidence: RecoveryConfidence.high,
          readiness: 88,
          recovery: 84,
        ),
      );

      expect(find.text('Charged.'), findsOneWidget);
      expect(find.text('High confidence'), findsOneWidget);
      // Charged band guidance is the kind "push if you're feeling it" copy,
      // carried by the route-call CoachCard (unchanged coach pipeline).
      expect(find.textContaining("Great day to push"), findsOneWidget);
    });

    testWidgets('renders the Recharge band with warm, non-alarmist copy', (
      tester,
    ) async {
      await _pump(
        tester,
        _snapshot(
          flowBand: RecoveryFlowBand.recharge,
          confidence: RecoveryConfidence.high,
          readiness: 30,
          recovery: 32,
        ),
      );

      // Band word is always present beside the tint (color-blind safe).
      expect(find.text('Recharge.'), findsOneWidget);
      // Kind invitation, never a command / never "red / danger" — carried by
      // the route-call CoachCard's headline.
      expect(
        find.textContaining("Your body's asking for a lighter day."),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text && (w.data?.toLowerCase().contains('danger') ?? false),
        ),
        findsNothing,
      );
    });

    testWidgets('renders the Steady band for a low-confidence rough estimate', (
      tester,
    ) async {
      await _pump(
        tester,
        _snapshot(
          flowBand: RecoveryFlowBand.steady,
          confidence: RecoveryConfidence.low,
          readiness: 50,
          recovery: 48,
        ),
      );

      expect(find.text('Steady.'), findsOneWidget);
      expect(find.text('Rough estimate'), findsOneWidget);
      // Low confidence softens the coaching copy.
      expect(
        find.textContaining('rough, sleep-based estimate'),
        findsOneWidget,
      );
    });

    testWidgets(
      'shows the building-baseline calibration state instead of a hard band word',
      (tester) async {
        await _pump(
          tester,
          _snapshot(
            flowBand: RecoveryFlowBand.ready,
            confidence: RecoveryConfidence.low,
            readiness: 64,
            recovery: 60,
            baselineCoverageDays: 5,
            isCalibrating: true,
          ),
        );

        // The calibration line shows progress toward the 14-day target. It
        // appears on the hero AND is echoed by the coach's route-call
        // headline (both delegate to the same vetted calibration copy).
        expect(
          find.textContaining('Building your baseline (5/14)'),
          findsWidgets,
        );
        expect(find.text('Ready.'), findsNothing);
      },
    );

    testWidgets('appends a kind off-baseline note for anomaly flags', (
      tester,
    ) async {
      await _pump(
        tester,
        _snapshot(
          flowBand: RecoveryFlowBand.steady,
          confidence: RecoveryConfidence.high,
          readiness: 52,
          recovery: 50,
          anomalyFlags: const ['elevated_resting_hr', 'low_hrv'],
        ),
      );

      expect(
        find.textContaining('Your markers look a bit off baseline today'),
        findsOneWidget,
      );
    });

    testWidgets('carries the non-medical disclaimer on the recovery surface', (
      tester,
    ) async {
      await _pump(
        tester,
        _snapshot(
          flowBand: RecoveryFlowBand.ready,
          confidence: RecoveryConfidence.high,
        ),
      );

      expect(find.textContaining('not medical advice'), findsOneWidget);
    });

    testWidgets(
      'with no snapshot renders exactly as today (no band, no crash)',
      (tester) async {
        await _pump(tester, null);

        // No flow band → the building fallback, no band word claim, no
        // disclaimer.
        expect(find.textContaining('Building your baseline'), findsWidgets);
        expect(find.textContaining('not medical advice'), findsNothing);
      },
    );

    testWidgets('omits the day-ledger receipt when health DI is unregistered '
        '(absent-safe dashboard)', (tester) async {
      // No health DI registered in this test host, so the day-ledger section
      // must resolve to a null ledger and render zero height — the dashboard
      // stays pixel-identical even though the snapshot carries a strain score.
      await _pump(
        tester,
        _snapshot(
          flowBand: RecoveryFlowBand.ready,
          confidence: RecoveryConfidence.high,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("The day's ledger"), findsNothing);
      expect(find.byKey(const Key('dayLedgerReceipt')), findsNothing);
    });

    testWidgets(
      'exposes the learn-more link to assistive tech (it sits outside '
      'the hero\'s excluded-semantics summary)',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(
          tester,
          _snapshot(
            flowBand: RecoveryFlowBand.steady,
            confidence: RecoveryConfidence.medium,
          ),
        );

        // Visible affordance...
        expect(find.text('How we read this'), findsOneWidget);
        // ...and reachable in the semantics tree (would be findsNothing if it
        // were inside the hero's excludeSemantics node).
        expect(find.bySemanticsLabel(RegExp('How we read this')), findsWidgets);
        handle.dispose();
      },
    );
  });
}
