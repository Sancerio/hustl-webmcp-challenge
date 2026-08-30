import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/dashboard/conditions_hero.dart';

Future<void> _pump(
  WidgetTester tester,
  DailyRecoverySnapshot? snapshot, {
  double? sleepBaselineMinutes,
  double? hrvBaseline,
  double? rhrBaseline,
}) async {
  final router = GoRouter(
    initialLocation: '/health',
    routes: [
      GoRoute(
        path: '/health',
        builder: (context, state) => Scaffold(
          body: SingleChildScrollView(
            child: ConditionsHero(
              snapshot: snapshot,
              sleepBaselineMinutes: sleepBaselineMinutes,
              hrvBaseline: hrvBaseline,
              rhrBaseline: rhrBaseline,
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
  double readiness = 70,
  int baselineCoverageDays = 21,
  bool isCalibrating = false,
  double? sleepMinutes,
  double? hrv,
  double? rhr,
}) {
  return DailyRecoverySnapshot(
    date: DateTime(2026, 1, 5),
    readinessScore: readiness,
    sleepDurationMinutes: sleepMinutes,
    hrvValue: hrv,
    restingHeartRateBpm: rhr,
    band: flowBand.legacyBand,
    flowBand: flowBand,
    confidence: RecoveryConfidence.high,
    baselineCoverageDays: baselineCoverageDays,
    isCalibrating: isCalibrating,
  );
}

void main() {
  group('ConditionsHero band word', () {
    testWidgets('renders the Charged band word', (tester) async {
      await _pump(tester, _snapshot(flowBand: RecoveryFlowBand.charged));
      expect(find.text('Charged.'), findsOneWidget);
    });

    testWidgets('renders the Recharge band word', (tester) async {
      await _pump(tester, _snapshot(flowBand: RecoveryFlowBand.recharge));
      expect(find.text('Recharge.'), findsOneWidget);
    });

    testWidgets('renders the readiness number and confidence chip', (
      tester,
    ) async {
      await _pump(
        tester,
        _snapshot(flowBand: RecoveryFlowBand.ready, readiness: 72),
      );
      expect(find.text('Readiness 72'), findsOneWidget);
      expect(find.text('High confidence'), findsOneWidget);
    });
  });

  group('ConditionsHero calibrating state', () {
    testWidgets('shows the building-baseline treatment, no band word', (
      tester,
    ) async {
      await _pump(
        tester,
        _snapshot(
          flowBand: RecoveryFlowBand.ready,
          isCalibrating: true,
          baselineCoverageDays: 5,
        ),
      );
      expect(
        find.textContaining('Building your baseline (5/14)'),
        findsWidgets,
      );
      expect(find.text('Ready.'), findsNothing);
    });

    testWidgets('with no snapshot at all renders the neutral building state', (
      tester,
    ) async {
      await _pump(tester, null);
      expect(find.textContaining('Building your baseline'), findsWidgets);
    });
  });

  group('ConditionsHero lede fallback', () {
    testWidgets('shows the data-woven lede when signals are present', (
      tester,
    ) async {
      await _pump(
        tester,
        _snapshot(flowBand: RecoveryFlowBand.steady, sleepMinutes: 432),
        sleepBaselineMinutes: 450,
      );
      expect(find.textContaining('You slept'), findsOneWidget);
    });

    testWidgets('falls back to coachHeadline copy when no signals have data', (
      tester,
    ) async {
      await _pump(tester, _snapshot(flowBand: RecoveryFlowBand.steady));
      // No lede sentence ("You slept" / "Your HRV" / "Your resting heart
      // rate") should appear; the vetted band headline shows instead.
      expect(find.textContaining('You slept'), findsNothing);
      expect(find.textContaining('below your usual'), findsOneWidget);
    });
  });

  group('ConditionsHero navigation', () {
    testWidgets('the "Last night" link pushes /health/night', (tester) async {
      await _pump(tester, _snapshot(flowBand: RecoveryFlowBand.ready));
      await tester.tap(find.text('Last night'));
      await tester.pumpAndSettle();
      expect(find.text('Night'), findsOneWidget);
    });
  });
}
