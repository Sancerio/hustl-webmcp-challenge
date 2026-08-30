import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/summary/strain_recovery_note.dart';

DailyRecoverySnapshot _snapshot({
  RecoveryFlowBand? flowBand = RecoveryFlowBand.recharge,
  RecoveryConfidence? confidence = RecoveryConfidence.high,
  int? strainScore = 16,
  bool withData = true,
}) => DailyRecoverySnapshot(
  date: DateTime(2026, 6, 13),
  sleepPerformanceScore: withData ? 70 : null,
  hrvValue: withData ? 48 : null,
  hrvKind: HrvKind.sdnn,
  restingHeartRateBpm: withData ? 60 : null,
  readinessScore: 36,
  recoveryScore: 34,
  strainScore: strainScore,
  baselineCoverageDays: 21,
  band: flowBand?.legacyBand,
  flowBand: flowBand,
  confidence: confidence,
);

Widget _host(Widget? child) =>
    MaterialApp(home: Scaffold(body: child ?? const SizedBox.shrink()));

void main() {
  testWidgets('renders a kind note for a confident low-band snapshot', (
    tester,
  ) async {
    await tester.pumpWidget(_host(StrainRecoveryNote.maybe(_snapshot())));
    await tester.pumpAndSettle();

    expect(find.byType(StrainRecoveryNote), findsOneWidget);
    expect(find.textContaining('lighter day'), findsOneWidget);
    // The band + strain meta line is shown.
    expect(find.textContaining('Recharge'), findsOneWidget);
    expect(find.textContaining('strain 16'), findsOneWidget);
  });

  testWidgets('maybe() returns null (renders nothing) for null snapshot', (
    tester,
  ) async {
    expect(StrainRecoveryNote.maybe(null), isNull);

    await tester.pumpWidget(_host(StrainRecoveryNote.maybe(null)));
    await tester.pumpAndSettle();

    expect(find.byType(StrainRecoveryNote), findsNothing);
  });

  testWidgets('maybe() returns null for a low-confidence snapshot', (
    tester,
  ) async {
    expect(
      StrainRecoveryNote.maybe(_snapshot(confidence: RecoveryConfidence.low)),
      isNull,
    );
  });

  testWidgets('renders affirmation for a good band', (tester) async {
    await tester.pumpWidget(
      _host(
        StrainRecoveryNote.maybe(
          _snapshot(flowBand: RecoveryFlowBand.charged, strainScore: 7),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('recovering well'), findsOneWidget);
  });
}
