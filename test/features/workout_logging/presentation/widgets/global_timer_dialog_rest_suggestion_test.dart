import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/core/services/notification_service.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/workout_logging/domain/services/rest_timer_service.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/global_timer_dialog.dart';

DailyRecoverySnapshot _snapshot({
  RecoveryFlowBand? flowBand = RecoveryFlowBand.recharge,
  RecoveryConfidence? confidence = RecoveryConfidence.high,
}) => DailyRecoverySnapshot(
  date: DateTime(2026, 6, 13),
  sleepPerformanceScore: 70,
  hrvValue: 48,
  hrvKind: HrvKind.sdnn,
  restingHeartRateBpm: 60,
  readinessScore: 36,
  recoveryScore: 34,
  strainScore: 15,
  baselineCoverageDays: 21,
  band: flowBand?.legacyBand,
  flowBand: flowBand,
  confidence: confidence,
);

void main() {
  late RestTimerService service;

  setUp(() {
    service = RestTimerService(notificationService: NotificationService());
  });

  Widget host({
    DailyRecoverySnapshot? snapshot,
    void Function(int)? onStart,
    VoidCallback? onResolved,
  }) => MaterialApp(
    home: Scaffold(
      body: GlobalTimerDialog(
        restTimerService: service,
        recoverySnapshot: snapshot,
        onSuggestionResolved: onResolved,
        onStartTimer: onStart ?? (_) {},
        onClose: () {},
      ),
    ),
  );

  testWidgets('shows the suggestion on a low-readiness day', (tester) async {
    await tester.pumpWidget(host(snapshot: _snapshot()));
    await tester.pumpAndSettle();

    expect(find.textContaining('consider a bit more rest'), findsOneWidget);
    expect(find.text('Use +30s'), findsOneWidget);
  });

  testWidgets('shows NO suggestion with no snapshot (rest flow as today)', (
    tester,
  ) async {
    await tester.pumpWidget(host(snapshot: null));
    await tester.pumpAndSettle();

    expect(find.textContaining('consider a bit more rest'), findsNothing);
  });

  testWidgets('shows NO suggestion on a good band', (tester) async {
    await tester.pumpWidget(
      host(snapshot: _snapshot(flowBand: RecoveryFlowBand.charged)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('consider a bit more rest'), findsNothing);
  });

  testWidgets('accepting +30s bumps the suggested default and resolves', (
    tester,
  ) async {
    var resolved = 0;
    var startedSeconds = -1;
    await tester.pumpWidget(
      host(
        snapshot: _snapshot(),
        onStart: (s) => startedSeconds = s,
        onResolved: () => resolved++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use +30s'));
    await tester.pumpAndSettle();

    // Suggestion resolved (hidden, callback fired once).
    expect(find.textContaining('consider a bit more rest'), findsNothing);
    expect(find.text('Use +30s'), findsNothing);
    expect(resolved, 1);

    // The bump is reflected in the value the dialog would START with: the
    // default 90s + 30s = 120s. (We never change the running timer silently.)
    await tester.tap(find.text('Start Timer'));
    await tester.pumpAndSettle();
    expect(startedSeconds, 120);
  });

  testWidgets('dismissing hides the suggestion and resolves once', (
    tester,
  ) async {
    var resolved = 0;
    await tester.pumpWidget(
      host(
        snapshot: _snapshot(),
        onResolved: () {
          resolved++;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    expect(find.textContaining('consider a bit more rest'), findsNothing);
    expect(resolved, 1);
  });
}
