import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/presentation/screens/night_detail_screen.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/dashboard/night_panel.dart';

DailyRecoverySnapshot _fullNight() => DailyRecoverySnapshot(
  date: DateTime(2026, 1, 5),
  sleepDurationMinutes: 432,
  awakeMinutes: 54,
  sleepEfficiency: 0.92,
  deepSleepMinutes: 90,
  lightSleepMinutes: 200,
  remSleepMinutes: 88,
  sleepStart: DateTime(2026, 1, 4, 23, 4),
  sleepEnd: DateTime(2026, 1, 5, 6, 16),
  hrvValue: 58,
  restingHeartRateBpm: 52,
  readinessScore: 68,
  band: RecoveryFlowBand.steady.legacyBand,
  flowBand: RecoveryFlowBand.steady,
  confidence: RecoveryConfidence.high,
  baselineCoverageDays: 21,
);

Future<void> _pump(WidgetTester tester, NightDetailArgs args) async {
  await tester.pumpWidget(MaterialApp(home: NightDetailScreen(args: args)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the full story of last night from a full snapshot', (
    tester,
  ) async {
    final night = _fullNight();
    await _pump(
      tester,
      NightDetailArgs(
        recoverySnapshots: [night],
        lastSyncedAt: DateTime(2026, 1, 5, 6, 31),
      ),
    );

    expect(find.text('Last night'), findsOneWidget);
    expect(find.text('What tonight built'), findsOneWidget);
    expect(find.text('Today, adjusted'), findsOneWidget);
    expect(find.textContaining('7h 12m asleep'), findsOneWidget);
    expect(find.textContaining('54m awake'), findsOneWidget);
    expect(find.textContaining('92% efficiency'), findsOneWidget);
    // Time labels present since sleepStart/sleepEnd are set.
    expect(find.textContaining('11:04'), findsOneWidget);
    expect(find.textContaining('6:16'), findsOneWidget);
    // Legend entries for the staged sleep segments.
    expect(find.text('Deep'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('REM'), findsOneWidget);
  });

  testWidgets(
    'stage-composition bar segments paint with real height (regression: a '
    'childless ColoredBox in a loose-cross-axis Row collapses to zero)',
    (tester) async {
      await _pump(tester, NightDetailArgs(recoverySnapshots: [_fullNight()]));

      final segments = find.descendant(
        of: find.byType(NightPanelHero),
        matching: find.byType(ColoredBox),
      );
      // Deep, Light, REM, Awake.
      expect(segments, findsNWidgets(4));
      for (final element in segments.evaluate()) {
        expect(element.size!.height, greaterThan(0));
        expect(element.size!.width, greaterThan(0));
      }
    },
  );

  testWidgets('omits time labels when the sleep window is null', (
    tester,
  ) async {
    final night = DailyRecoverySnapshot(
      date: DateTime(2026, 1, 5),
      sleepDurationMinutes: 432,
      deepSleepMinutes: 90,
      lightSleepMinutes: 200,
      remSleepMinutes: 88,
      // sleepStart / sleepEnd intentionally omitted (null).
    );
    await _pump(tester, NightDetailArgs(recoverySnapshots: [night]));

    expect(find.textContaining('11:04'), findsNothing);
    expect(find.textContaining('6:16'), findsNothing);
    // The rest of the story still renders.
    expect(find.text('What tonight built'), findsOneWidget);
  });

  testWidgets('shows a gentle empty state when there is no sleep data', (
    tester,
  ) async {
    final blank = DailyRecoverySnapshot(date: DateTime(2026, 1, 5));
    await _pump(tester, NightDetailArgs(recoverySnapshots: [blank]));

    expect(find.text('No sleep data for last night yet'), findsOneWidget);
    expect(find.text('What tonight built'), findsNothing);
  });

  testWidgets('empty state action navigates back to the overview', (
    tester,
  ) async {
    final blank = DailyRecoverySnapshot(date: DateTime(2026, 1, 5));
    final router = GoRouter(
      initialLocation: '/health/night',
      routes: [
        GoRoute(
          path: '/health',
          builder: (context, state) => const Scaffold(body: Text('Overview')),
        ),
        GoRoute(
          path: '/health/night',
          builder: (context, state) => NightDetailScreen(
            args: NightDetailArgs(recoverySnapshots: [blank]),
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back to overview'));
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsOneWidget);
  });
}
