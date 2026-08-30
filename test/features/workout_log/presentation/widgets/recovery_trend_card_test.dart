import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/recovery_trend_card.dart';

DailyRecoverySnapshot _day(
  int day, {
  RecoveryFlowBand flowBand = RecoveryFlowBand.ready,
  double readiness = 70,
  bool withData = true,
}) => DailyRecoverySnapshot(
  date: DateTime(2026, 6, day),
  sleepPerformanceScore: withData ? 80 : null,
  hrvValue: withData ? 56 : null,
  hrvKind: HrvKind.sdnn,
  restingHeartRateBpm: withData ? 55 : null,
  readinessScore: readiness,
  recoveryScore: readiness - 2,
  baselineCoverageDays: 21,
  band: flowBand.legacyBand,
  flowBand: flowBand,
  confidence: RecoveryConfidence.high,
);

Widget _host(Widget? child) =>
    MaterialApp(home: Scaffold(body: child ?? const SizedBox.shrink()));

void main() {
  testWidgets('renders the trend with recent snapshots', (tester) async {
    final snapshots = [
      _day(10, flowBand: RecoveryFlowBand.steady, readiness: 45),
      _day(11, flowBand: RecoveryFlowBand.ready, readiness: 68),
      _day(12, flowBand: RecoveryFlowBand.charged, readiness: 88),
    ];
    var tapped = false;
    await tester.pumpWidget(
      _host(RecoveryTrendCard.maybe(snapshots, onTap: () => tapped = true)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RecoveryTrendCard), findsOneWidget);
    expect(find.text('Recovery trend'), findsOneWidget);
    // Latest band is named in text for color-blind safety.
    expect(find.textContaining('Charged'), findsOneWidget);

    await tester.tap(find.byType(RecoveryTrendCard));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('maybe() returns null (renders nothing) with no usable data', (
    tester,
  ) async {
    expect(RecoveryTrendCard.maybe(const []), isNull);
    expect(RecoveryTrendCard.maybe([_day(10, withData: false)]), isNull);

    await tester.pumpWidget(_host(RecoveryTrendCard.maybe(const [])));
    await tester.pumpAndSettle();
    expect(find.byType(RecoveryTrendCard), findsNothing);
  });
}
