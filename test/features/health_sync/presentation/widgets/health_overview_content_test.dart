import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hustl_app/core/widgets/app_section.dart';
import 'package:hustl_app/core/widgets/hustl_inline_skeleton.dart';
import 'package:hustl_app/core/widgets/staggered_entrance.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_health_summary.dart';
import 'package:hustl_app/features/health_sync/domain/models/daily_recovery_snapshot.dart';
import 'package:hustl_app/features/health_sync/presentation/bloc/health_overview_bloc.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/health_overview_content.dart';

class _MockHealthOverviewBloc
    extends MockBloc<HealthOverviewEvent, HealthOverviewState>
    implements HealthOverviewBloc {}

void main() {
  group('HealthOverviewContent', () {
    // The dashboard plays a one-time staggered entrance; reset the played-key
    // registry between tests so each renders the animation deterministically.
    setUp(StaggeredEntrance.resetForTest);

    testWidgets('shows sync guidance while waiting for first data', (
      WidgetTester tester,
    ) async {
      final bloc = _MockHealthOverviewBloc();
      final emptyState = HealthOverviewState.initial().copyWith(
        status: HealthOverviewStatus.empty,
        lastSyncedAt: DateTime(2024, 9, 24, 10, 27),
      );

      when(() => bloc.state).thenReturn(emptyState);
      when(() => bloc.stream).thenAnswer((_) => Stream.value(emptyState));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: BlocProvider<HealthOverviewBloc>.value(
            value: bloc,
            child: const Scaffold(body: HealthOverviewContent()),
          ),
        ),
      );

      await tester.pump();

      expect(
        find.textContaining('Health Connect can take a few minutes'),
        findsOneWidget,
      );
      expect(find.textContaining('sleep, recovery, activity'), findsOneWidget);
      expect(find.textContaining('We last checked'), findsOneWidget);
    });

    testWidgets('renders warning banner when sync warnings are present', (
      WidgetTester tester,
    ) async {
      final bloc = _MockHealthOverviewBloc();
      final warningState = HealthOverviewState.initial().copyWith(
        status: HealthOverviewStatus.empty,
        syncWarnings: const ['Weight access was denied.'],
      );

      when(() => bloc.state).thenReturn(warningState);
      when(() => bloc.stream).thenAnswer((_) => Stream.value(warningState));

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<HealthOverviewBloc>.value(
            value: bloc,
            child: const Scaffold(body: HealthOverviewContent()),
          ),
        ),
      );

      await tester.pump();

      expect(
        find.textContaining('signals still need attention'),
        findsOneWidget,
      );
      expect(find.textContaining('Weight access was denied.'), findsOneWidget);
    });

    testWidgets('renders recovery overview when recovery data is present', (
      WidgetTester tester,
    ) async {
      final bloc = _MockHealthOverviewBloc();
      final readyState = HealthOverviewState.initial().copyWith(
        status: HealthOverviewStatus.ready,
        summaries: [
          DailyHealthSummary(
            date: DateTime(2025, 1, 2),
            metrics: const [],
            nutritionLogs: const [],
            macros: const DailyMacroBreakdown(
              calories: 0,
              proteinGrams: 0,
              carbsGrams: 0,
              fatGrams: 0,
            ),
          ),
        ],
        recoverySnapshots: [
          DailyRecoverySnapshot(
            date: DateTime(2025, 1, 2),
            readinessScore: 84,
            recoveryScore: 78,
            sleepDurationMinutes: 465,
            loadRatio: 1.08,
            strainScore: 13,
            band: RecoveryReadinessBand.high,
            flowBand: RecoveryFlowBand.charged,
            confidence: RecoveryConfidence.high,
            baselineCoverageDays: 21,
          ),
        ],
      );

      when(() => bloc.state).thenReturn(readyState);
      when(() => bloc.stream).thenAnswer((_) => Stream.value(readyState));

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<HealthOverviewBloc>.value(
            value: bloc,
            child: const Scaffold(body: HealthOverviewContent()),
          ),
        ),
      );

      // Settle the dashboard's one-time staggered entrance before asserting.
      await tester.pumpAndSettle();

      // "Conditions Report": the "Today" block leads with the conditions hero
      // — the band word, the readiness number, and the confidence qualifier.
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Charged.'), findsOneWidget);
      expect(find.text('Readiness 84'), findsOneWidget);
      expect(find.text('High confidence'), findsOneWidget);

      // The instruments row and the week strip follow.
      expect(find.widgetWithText(SectionHeader, 'Instruments'), findsOneWidget);
      expect(find.widgetWithText(SectionHeader, 'Past week'), findsOneWidget);

      // The quiet coaching card (now doubling as the route-call card) follows.
      expect(find.widgetWithText(SectionHeader, 'Coaching'), findsOneWidget);
    });

    testWidgets(
      'a refreshing dashboard stays rendered with no loading skeleton',
      (WidgetTester tester) async {
        final bloc = _MockHealthOverviewBloc();
        final refreshingState = HealthOverviewState.initial().copyWith(
          status: HealthOverviewStatus.ready,
          isRefreshing: true,
          summaries: [
            DailyHealthSummary(
              date: DateTime(2025, 1, 2),
              metrics: const [],
              nutritionLogs: const [],
              macros: const DailyMacroBreakdown(
                calories: 0,
                proteinGrams: 0,
                carbsGrams: 0,
                fatGrams: 0,
              ),
            ),
          ],
          recoverySnapshots: [
            DailyRecoverySnapshot(
              date: DateTime(2025, 1, 2),
              readinessScore: 84,
              recoveryScore: 78,
              sleepDurationMinutes: 465,
              loadRatio: 1.08,
              strainScore: 13,
              band: RecoveryReadinessBand.high,
              flowBand: RecoveryFlowBand.charged,
              confidence: RecoveryConfidence.high,
              baselineCoverageDays: 21,
            ),
          ],
        );

        when(() => bloc.state).thenReturn(refreshingState);
        when(
          () => bloc.stream,
        ).thenAnswer((_) => Stream.value(refreshingState));

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<HealthOverviewBloc>.value(
              value: bloc,
              child: const Scaffold(body: HealthOverviewContent()),
            ),
          ),
        );

        // Settle the dashboard's one-time staggered entrance before asserting.
        await tester.pumpAndSettle();

        // The dashboard rendered, not the full-screen loading skeleton — an
        // in-flight refetch keeps the previous data on screen.
        expect(find.text('Today'), findsOneWidget);
        expect(find.byType(HustlInlineSkeleton), findsNothing);
      },
    );

    testWidgets('a refresh failure surfaces a quiet snack without leaving the '
        'dashboard', (WidgetTester tester) async {
      final bloc = _MockHealthOverviewBloc();
      final readyState = HealthOverviewState.initial().copyWith(
        status: HealthOverviewStatus.ready,
        summaries: [
          DailyHealthSummary(
            date: DateTime(2025, 1, 2),
            metrics: const [],
            nutritionLogs: const [],
            macros: const DailyMacroBreakdown(
              calories: 0,
              proteinGrams: 0,
              carbsGrams: 0,
              fatGrams: 0,
            ),
          ),
        ],
      );
      final failedState = readyState.copyWith(
        isRefreshing: false,
        refreshError:
            "Couldn't refresh your health data. Showing your last synced "
            'view.',
      );

      // whenListen keeps bloc.state in sync with each emitted item, so the
      // widget observes the ready -> ready+refreshError transition exactly
      // as it would from the real bloc.
      whenListen(
        bloc,
        Stream.fromIterable([readyState, failedState]),
        initialState: readyState,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<HealthOverviewBloc>.value(
            value: bloc,
            child: const Scaffold(body: HealthOverviewContent()),
          ),
        ),
      );

      // Let the stream deliver both states and the snack bar animate in.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining("Couldn't refresh your health data"),
        findsOneWidget,
      );
      // The dashboard is still the rendered content, not a full-screen
      // error state.
      expect(find.text('Today'), findsOneWidget);
    });
  });
}
