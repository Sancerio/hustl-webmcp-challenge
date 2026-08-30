import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/domain/models/recovery_signal_availability.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/dashboard/conditions_copy.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/dashboard/conditions_instruments.dart';

Future<void> _pump(
  WidgetTester tester, {
  required DailyRecoverySnapshot? snapshot,
  required ConditionsBaselines baselines,
  required RecoverySignalAvailability signalAvailability,
}) async {
  final router = GoRouter(
    initialLocation: '/health',
    routes: [
      GoRoute(
        path: '/health',
        builder: (context, state) => Scaffold(
          body: ConditionsInstruments(
            snapshot: snapshot,
            baselines: baselines,
            signalAvailability: signalAvailability,
          ),
        ),
      ),
      GoRoute(
        path: '/health/night',
        builder: (context, state) => const Scaffold(body: Text('Night')),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();
}

void main() {
  const fullAvailability = RecoverySignalAvailability(
    hrv: true,
    restingHeartRate: true,
    sleep: true,
    respiratoryRate: true,
  );

  testWidgets('renders values and deltas for all three signals', (
    tester,
  ) async {
    final snapshot = DailyRecoverySnapshot(
      date: DateTime(2026, 1, 5),
      sleepDurationMinutes: 432,
      hrvValue: 58,
      restingHeartRateBpm: 52,
    );
    await _pump(
      tester,
      snapshot: snapshot,
      baselines: const ConditionsBaselines(
        sleepMinutes: 450,
        hrvValue: 62,
        restingHeartRateBpm: 48,
      ),
      signalAvailability: fullAvailability,
    );

    expect(find.text('7h 12m'), findsOneWidget);
    expect(find.text('58 ms'), findsOneWidget);
    expect(find.text('52 bpm'), findsOneWidget);
    expect(find.text('18m under'), findsOneWidget);
    expect(find.text('4 ms easier'), findsOneWidget);
    expect(find.text('4 over'), findsOneWidget);
  });

  testWidgets('missing signal renders — and "No data yet"', (tester) async {
    await _pump(
      tester,
      snapshot: DailyRecoverySnapshot(date: DateTime(2026, 1, 5)),
      baselines: const ConditionsBaselines(),
      signalAvailability: const RecoverySignalAvailability(),
    );

    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('No data yet'), findsNWidgets(3));
  });

  testWidgets(
    'display is value-first: values render even when availability is empty '
    '(cached loads / older states default availability to empty)',
    (tester) async {
      final snapshot = DailyRecoverySnapshot(
        date: DateTime(2026, 1, 5),
        sleepDurationMinutes: 432,
        hrvValue: 58,
        restingHeartRateBpm: 52,
      );
      await _pump(
        tester,
        snapshot: snapshot,
        baselines: const ConditionsBaselines(
          sleepMinutes: 450,
          hrvValue: 62,
          restingHeartRateBpm: 48,
        ),
        signalAvailability: const RecoverySignalAvailability(),
      );

      // Values and deltas render from the snapshot alone; no dashes, no
      // "No data yet".
      expect(find.text('7h 12m'), findsOneWidget);
      expect(find.text('58 ms'), findsOneWidget);
      expect(find.text('52 bpm'), findsOneWidget);
      expect(find.text('18m under'), findsOneWidget);
      expect(find.text('—'), findsNothing);
      expect(find.text('No data yet'), findsNothing);
    },
  );

  testWidgets('a null value on a flowing signal reads "Building baseline", not '
      '"No data yet"', (tester) async {
    await _pump(
      tester,
      snapshot: DailyRecoverySnapshot(date: DateTime(2026, 1, 5)),
      baselines: const ConditionsBaselines(),
      signalAvailability: fullAvailability,
    );

    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('Building baseline'), findsNWidgets(3));
    expect(find.text('No data yet'), findsNothing);
  });

  testWidgets(
    'a present signal with no baseline yet reads "Building baseline"',
    (tester) async {
      final snapshot = DailyRecoverySnapshot(
        date: DateTime(2026, 1, 5),
        sleepDurationMinutes: 432,
        hrvValue: 58,
        restingHeartRateBpm: 52,
      );
      await _pump(
        tester,
        snapshot: snapshot,
        baselines: const ConditionsBaselines(),
        signalAvailability: fullAvailability,
      );

      expect(find.text('Building baseline'), findsNWidgets(3));
    },
  );

  testWidgets('tapping the Sleep tile pushes /health/night', (tester) async {
    final snapshot = DailyRecoverySnapshot(
      date: DateTime(2026, 1, 5),
      sleepDurationMinutes: 432,
    );
    await _pump(
      tester,
      snapshot: snapshot,
      baselines: const ConditionsBaselines(),
      signalAvailability: fullAvailability,
    );

    await tester.tap(find.text('7h 12m'));
    await tester.pumpAndSettle();
    expect(find.text('Night'), findsOneWidget);
  });
}
