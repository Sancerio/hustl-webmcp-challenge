import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/readiness_today_row.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/home/readiness_today_slot.dart';

DailyRecoverySnapshot _snapshot({
  RecoveryFlowBand? flowBand = RecoveryFlowBand.ready,
  RecoveryConfidence? confidence = RecoveryConfidence.high,
  bool isCalibrating = false,
  int baselineCoverageDays = 21,
  double? readinessScore = 74,
}) => DailyRecoverySnapshot(
  date: DateTime(2026, 6, 13),
  sleepPerformanceScore: 82,
  hrvValue: 58,
  hrvKind: HrvKind.sdnn,
  restingHeartRateBpm: 54,
  readinessScore: readinessScore,
  recoveryScore: 71,
  baselineCoverageDays: baselineCoverageDays,
  band: flowBand?.legacyBand,
  flowBand: flowBand,
  confidence: confidence,
  isCalibrating: isCalibrating,
);

void main() {
  String? pushedRoute;

  Widget host(Widget? child) {
    pushedRoute = null;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: child ?? const SizedBox.shrink()),
        ),
        GoRoute(
          path: '/health',
          builder: (_, _) {
            pushedRoute = '/health';
            return const Scaffold(body: Text('Health dashboard'));
          },
        ),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('renders the band label + readiness with a confident snapshot', (
    tester,
  ) async {
    await tester.pumpWidget(host(ReadinessTodayRow.maybe(_snapshot())));
    await tester.pumpAndSettle();

    expect(find.byType(ReadinessTodayRow), findsOneWidget);
    expect(find.text('Readiness'), findsOneWidget);
    // Band label is always shown beside the color dot (color-blind safety),
    // here joined with the score: "Ready · 74".
    expect(find.textContaining('Ready'), findsOneWidget);
    expect(find.textContaining('74'), findsOneWidget);
  });

  testWidgets('maybe() returns null (renders nothing) with no snapshot', (
    tester,
  ) async {
    expect(ReadinessTodayRow.maybe(null), isNull);

    await tester.pumpWidget(host(ReadinessTodayRow.maybe(null)));
    await tester.pumpAndSettle();

    expect(find.byType(ReadinessTodayRow), findsNothing);
    expect(find.text('Readiness'), findsNothing);
  });

  testWidgets('tapping the row deep-links to /health', (tester) async {
    await tester.pumpWidget(host(ReadinessTodayRow.maybe(_snapshot())));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ReadinessTodayRow));
    await tester.pumpAndSettle();

    expect(pushedRoute, '/health');
    expect(find.text('Health dashboard'), findsOneWidget);
  });

  testWidgets('shows a gentle calibration variant while building baseline', (
    tester,
  ) async {
    final calibrating = _snapshot(
      flowBand: null,
      confidence: RecoveryConfidence.low,
      isCalibrating: true,
      baselineCoverageDays: 5,
      readinessScore: null,
    );
    await tester.pumpWidget(host(ReadinessTodayRow.maybe(calibrating)));
    await tester.pumpAndSettle();

    expect(find.byType(ReadinessTodayRow), findsOneWidget);
    // The "(n/14)" baseline label appears; no hard band name is shown.
    expect(find.textContaining('5/14'), findsOneWidget);
    expect(find.textContaining('Recharge'), findsNothing);
  });

  testWidgets('softens to a rough estimate on low confidence', (tester) async {
    final lowConfidence = _snapshot(
      flowBand: RecoveryFlowBand.steady,
      confidence: RecoveryConfidence.low,
    );
    await tester.pumpWidget(host(ReadinessTodayRow.maybe(lowConfidence)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Rough estimate'), findsOneWidget);
  });

  testWidgets('unavailable slot stays useful and deep-links to Health', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(const ReadinessTodaySlot(state: ReadinessTodayState.unavailable())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Readiness'), findsOneWidget);
    expect(find.text('Not available yet'), findsOneWidget);
    expect(
      tester.getSize(find.byType(ReadinessTodaySlot)).height,
      ReadinessTodaySlot.height,
    );
    final semanticsNode = tester.getSemantics(
      find.bySemanticsLabel(RegExp('Readiness, not available yet')),
    );
    expect(
      semanticsNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
      reason: 'the merged semantics button must expose its tap action',
    );
    semantics.dispose();

    await tester.tap(find.text('Not available yet'));
    await tester.pumpAndSettle();

    expect(pushedRoute, '/health');
  });

  testWidgets('reduced motion replaces the static placeholder immediately', (
    tester,
  ) async {
    final liveState = ValueNotifier<ReadinessTodayState>(
      const ReadinessTodayState.loading(),
    );
    addTearDown(liveState.dispose);

    await tester.pumpWidget(
      host(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ValueListenableBuilder<ReadinessTodayState>(
            valueListenable: liveState,
            builder: (_, state, _) => ReadinessTodaySlot(state: state),
          ),
        ),
      ),
    );
    await tester.pump();

    final switcher = tester.widget<AnimatedSwitcher>(
      find.descendant(
        of: find.byType(ReadinessTodaySlot),
        matching: find.byType(AnimatedSwitcher),
      ),
    );
    expect(switcher.duration, Duration.zero);
    expect(find.byKey(const ValueKey('readiness-loading')), findsOneWidget);

    liveState.value = ReadinessTodayState.available(_snapshot());
    await tester.pump();

    expect(find.byKey(const ValueKey('readiness-loading')), findsNothing);
    expect(find.byType(ReadinessTodayRow), findsOneWidget);
  });

  testWidgets('slot keeps stable geometry without overflow at large text', (
    tester,
  ) async {
    final liveState = ValueNotifier<ReadinessTodayState>(
      const ReadinessTodayState.loading(),
    );
    addTearDown(liveState.dispose);
    const scaler = TextScaler.linear(2);

    await tester.pumpWidget(
      host(
        MediaQuery(
          data: const MediaQueryData(textScaler: scaler),
          child: ValueListenableBuilder<ReadinessTodayState>(
            valueListenable: liveState,
            builder: (_, state, _) => ReadinessTodaySlot(state: state),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final expectedHeight = ReadinessTodaySlot.heightFor(scaler);
    expect(
      tester.getSize(find.byType(ReadinessTodaySlot)).height,
      expectedHeight,
    );
    expect(tester.takeException(), isNull);

    liveState.value = ReadinessTodayState.available(_snapshot());
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(ReadinessTodaySlot)).height,
      expectedHeight,
    );
    expect(tester.takeException(), isNull);

    liveState.value = const ReadinessTodayState.unavailable();
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(ReadinessTodaySlot)).height,
      expectedHeight,
    );
    expect(tester.takeException(), isNull);
  });
}
