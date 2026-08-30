import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hustl_app/core/widgets/app_section.dart';
import 'package:hustl_app/core/widgets/coach_card.dart';
import 'package:hustl_app/core/widgets/staggered_entrance.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_health_summary.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/domain/usecases/derive_health_insights.dart';
import 'package:hustl_app/features/health_sync/presentation/bloc/health_overview_bloc.dart';
import 'package:hustl_app/features/health_sync/presentation/preview/health_overview_preview_repository.dart';
import 'package:hustl_app/features/health_sync/presentation/screens/health_overview_screen.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/dashboard/conditions_week_strip.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/dashboard/health_dashboard_biology.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/dashboard/health_dashboard_insights.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/health_overview_content.dart';

class _MockHealthOverviewBloc
    extends MockBloc<HealthOverviewEvent, HealthOverviewState>
    implements HealthOverviewBloc {}

DailyRecoverySnapshot _day(int i) => DailyRecoverySnapshot(
  date: DateTime(2026, 6, 20 + i),
  readinessScore: 47,
  recoveryScore: 45,
  sleepDurationMinutes: 395, // 6h35m
  sleepPerformanceScore: 74,
  hrvValue: 32,
  hrvKind: HrvKind.sdnn,
  restingHeartRateBpm: 83,
  strainScore: 11,
  loadRatio: 1.05,
  band: RecoveryFlowBand.steady.legacyBand,
  flowBand: RecoveryFlowBand.steady,
  confidence: RecoveryConfidence.high,
  baselineCoverageDays: 21,
);

HealthOverviewState _readyState() => HealthOverviewState.initial().copyWith(
  status: HealthOverviewStatus.ready,
  summaries: [
    for (var i = 0; i < 10; i++)
      DailyHealthSummary(
        date: DateTime(2026, 6, 20 + i),
        latestWeightKg: 81.2 - i * 0.1,
        latestHeightCm: 182,
        bodyMassIndex: 24.5,
        metrics: const [],
        nutritionLogs: const [],
        macros: const DailyMacroBreakdown(
          calories: 2200,
          proteinGrams: 150,
          carbsGrams: 210,
          fatGrams: 70,
        ),
      ),
  ],
  recoverySnapshots: [for (var i = 0; i < 10; i++) _day(i)],
  latestWeightKg: 80.3,
  latestBmi: 24.5,
  weeklyWeightChangeKg: -0.4,
  lastSyncedAt: DateTime(2026, 6, 29, 7, 12),
  insights: const [
    HealthInsight(
      title: 'Sleep dipped below your baseline',
      message: 'Last night ran short. A steadier bedtime helps HRV recover.',
      severity: HealthInsightSeverity.warning,
    ),
  ],
);

double _effectiveOpacity(WidgetTester tester, Finder f) {
  var opacity = 1.0;
  f.first.evaluate().first.visitAncestorElements((ancestor) {
    final w = ancestor.widget;
    if (w is Opacity) opacity *= w.opacity;
    if (w is FadeTransition) opacity *= w.opacity.value;
    return true;
  });
  return opacity;
}

double _top(WidgetTester tester, Finder f) {
  final ro = tester.renderObject(f.first) as RenderBox;
  return ro.localToGlobal(Offset.zero).dy;
}

void main() {
  setUp(StaggeredEntrance.resetForTest);

  testWidgets(
    'Biology dashboard paints every section below the coach header at phone '
    'size even when the entrance cannot tick (no "blank at the bottom")',
    (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final bloc = _MockHealthOverviewBloc();
      final ready = _readyState();
      when(() => bloc.state).thenReturn(ready);
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: BlocProvider<HealthOverviewBloc>.value(
            value: bloc,
            // Hardening against entrance-gated visibility: under a muted
            // ticker the staggered entrance's flutter_animate controllers can
            // never advance, and without the TickerMode guard these sections
            // would reserve scroll space while painting at opacity 0. The
            // entrance must fall back to static content.
            child: const Scaffold(
              body: TickerMode(enabled: false, child: HealthOverviewContent()),
            ),
          ),
        ),
      );
      await tester.pump();

      // The four surfaces the bug report called out as blank.
      final coachCard = find.byType(CoachCard);
      final pastWeek = find.widgetWithText(SectionHeader, 'Past week');
      final weekStrip = find.byType(ConditionsWeekStrip);
      final bodyHeader = find.widgetWithText(SectionHeader, 'Body');
      final biologyGrid = find.byType(BiologyGrid);
      final insightsHeader = find.widgetWithText(SectionHeader, 'Insights');
      final insightDeck = find.byType(InsightDeck);

      for (final entry in <String, Finder>{
        'CoachCard': coachCard,
        'Past week header': pastWeek,
        'ConditionsWeekStrip': weekStrip,
        'Body header': bodyHeader,
        'BiologyGrid': biologyGrid,
        'Insights header': insightsHeader,
        'InsightDeck': insightDeck,
      }.entries) {
        expect(
          entry.value,
          findsOneWidget,
          reason: '${entry.key} should be in the tree',
        );
        expect(
          _effectiveOpacity(tester, entry.value),
          1.0,
          reason: '${entry.key} must be painted (opacity 1), not blank',
        );
      }

      // They also lay out in the expected top-to-bottom reading order (the
      // coach card leads the group; the insight deck trails it).
      expect(
        _top(tester, coachCard),
        lessThan(_top(tester, weekStrip)),
      );
      expect(
        _top(tester, weekStrip),
        lessThan(_top(tester, biologyGrid)),
      );
      expect(
        _top(tester, biologyGrid),
        lessThan(_top(tester, insightDeck)),
      );
    },
  );

  testWidgets(
    'Biology dashboard scrolls edge-to-edge under the home indicator — no '
    'letterbox band, and the last section clears the safe-area inset',
    (tester) async {
      // iPhone-sized viewport with a 34pt home-indicator inset, dark theme —
      // the exact conditions of the reported "blank at the bottom": the
      // scrollable dashboard's viewport ended ~66pt above the physical bottom
      // (34pt SafeArea + 16pt screen padding + 16pt always-reserved prompt
      // slot), guillotining the coach card and leaving a dead band below it.
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      tester.view.padding = FakeViewPadding(bottom: (34 * 3).toDouble());
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);

      // The real screen (MainScaffold + SafeArea + permissions gate + bloc)
      // with the preview repository's realistic ready snapshot.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const HealthOverviewScreen(
            repositoryOverride: PreviewHealthMetricsRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // (a) The dashboard scrollport's bottom paint edge reaches the physical
      // bottom of the screen — content draws under the home indicator.
      final viewportBottom = tester.getRect(find.byType(ListView)).bottom;
      expect(
        viewportBottom,
        moreOrLessEquals(844.0, epsilon: 0.1),
        reason:
            'The scroll viewport must reach the physical screen bottom; '
            'anything less is a letterbox band (was ~778 before the fix)',
      );

      // (b) Scrolled to the end, the last section sits fully above the
      // home-indicator inset — content clears it while drawing under it.
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
      final deckBottom = tester.getRect(find.byType(InsightDeck)).bottom;
      expect(
        deckBottom,
        lessThanOrEqualTo(844.0 - 34.0),
        reason:
            'At max scroll the last section must clear the 34pt '
            'home-indicator inset',
      );
    },
  );
}
