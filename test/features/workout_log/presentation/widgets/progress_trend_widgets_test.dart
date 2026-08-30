import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/body_score/overview_trend_sparkline.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/progress_skeleton.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/progress_trend_stat_card.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
  }

  group('TrendStatCard', () {
    testWidgets('renders the label, value, and cue', (tester) async {
      await pump(
        tester,
        const TrendStatCard(
          label: 'Volume · last 8 wk',
          value: '1,240 kg',
          cue: 'Up 8%',
          series: [],
        ),
      );

      expect(find.text('Volume · last 8 wk'), findsOneWidget);
      expect(find.text('1,240 kg'), findsOneWidget);
      expect(find.text('Up 8%'), findsOneWidget);
    });

    testWidgets('draws the sparkline with 3+ points', (tester) async {
      await pump(
        tester,
        const TrendStatCard(
          label: 'Volume',
          value: '900 kg',
          series: [4, 6, 5, 8],
        ),
      );

      expect(find.byType(OverviewTrendSparkline), findsOneWidget);
    });

    testWidgets('omits the sparkline with fewer than 3 points (reads as noise)', (
      tester,
    ) async {
      await pump(
        tester,
        const TrendStatCard(
          label: 'Volume',
          value: '900 kg',
          series: [4, 6],
        ),
      );

      expect(find.byType(OverviewTrendSparkline), findsNothing);
    });
  });

  group('ProgressSkeleton', () {
    testWidgets('reserves four card placeholders', (tester) async {
      // A tall viewport so the lazy ListView builds every placeholder (the
      // reserved heights sum past a default 600px test viewport).
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pump(tester, const ProgressSkeleton());

      // Hero + balance + chart + strength.
      expect(find.byType(AppSkeleton), findsNWidgets(4));
    });

    testWidgets('does not overflow a short viewport (regression)', (
      tester,
    ) async {
      // The skeleton's reserved heights sum past a short/landscape viewport, so
      // it must scroll-clip rather than throw a RenderFlex overflow (the bug
      // that shipped when it was a bare fixed-height Column).
      await pump(
        tester,
        const SizedBox(height: 320, child: ProgressSkeleton()),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
