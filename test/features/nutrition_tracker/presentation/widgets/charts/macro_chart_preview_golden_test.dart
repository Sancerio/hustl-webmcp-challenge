import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/utils/weight_unit.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/charts/chart_changes_card.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/charts/chart_granularity.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/charts/chart_legend_card.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/charts/chart_range_bar.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/charts/chart_stat_header.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/charts/expenditure_trend_chart.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/weight_trend_cards.dart';

/// Renders the two redesigned trend stacks with the real dark theme + DM Sans so
/// the goldens read as the shipping UI. Run with `--update-goldens` to refresh
/// the preview PNGs under goldens/.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Load every bundled font from the generated manifest (DM Sans + the
    // framework's MaterialIcons) so icons and text render as on device.
    final manifest =
        json.decode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final family = entry['family'] as String;
      final loader = FontLoader(family);
      for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  Future<void> pumpStack(WidgetTester tester, Widget child) async {
    tester.view.devicePixelRatio = 2.0;
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.x2),
              child: child,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  testWidgets('weight trend preview', (tester) async {
    const trend = [154.4, 154.0, 153.6, 153.2, 152.9, 152.7, 152.8];
    const scale = [154.6, 153.0, 154.2, 151.8, 150.6, 151.0, 152.9];
    final trendSpots = [
      for (var i = 0; i < trend.length; i++) FlSpot(i.toDouble(), trend[i]),
    ];
    final scaleSpots = [
      for (var i = 0; i < scale.length; i++) FlSpot(i.toDouble(), scale[i]),
    ];

    await pumpStack(
      tester,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ChartStatHeader(
            leadingLabel: 'Average',
            leadingValue: '153.5',
            leadingUnit: 'lb',
            trailingLabel: 'Difference',
            trailingValue: '−1.6',
            trailingUnit: 'lb',
            dateRangeText: 'Apr 6 – Apr 12, 2025',
            onToggleFit: _noop,
          ),
          const SizedBox(height: AppSpacing.x2),
          WeightTrendChart(
            baseDate: DateTime(2025, 4, 6),
            scaleSpots: scaleSpots,
            trendSpots: trendSpots,
            showScale: true,
            showTrend: true,
            minY: 150.6,
            maxY: 154.6,
            unit: const WeightUnit('lb'),
            rangeDays: 7,
          ),
          const SizedBox(height: AppSpacing.x2),
          ChartRangeBar(
            rangeOptions: const [7, 30, 90, 180, 365, 0],
            selectedRange: 7,
            rangeLabels: const {
              7: '1W',
              30: '1M',
              90: '3M',
              180: '6M',
              365: '1Y',
              0: 'All',
            },
            onSelectRange: (_) {},
            granularities: availableGranularities(7),
            selectedGranularity: ChartGranularity.day,
            onSelectGranularity: (_) {},
          ),
          const SizedBox(height: AppSpacing.x2),
          Builder(
            builder: (context) => ChartLegendCard(
              entries: [
                ChartLegendEntry(
                  swatch: ChartSwatch.line,
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.55),
                  label: 'Scale weight',
                ),
                ChartLegendEntry(
                  swatch: ChartSwatch.lineDot,
                  color: Theme.of(context).colorScheme.primary,
                  label: 'Trend weight',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          Builder(
            builder: (context) => Text(
              'Insights & data',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Builder(
            builder: (context) => ChartChangesCard(
              title: 'Weight changes',
              accentColor: Theme.of(context).colorScheme.primary,
              rows: const [
                ChartChangeRow(
                  label: '3-day',
                  sparkline: [153.2, 152.9, 152.7, 152.8],
                  valueText: '−0.3 lb',
                  direction: ChangeDirection.decrease,
                ),
                ChartChangeRow(
                  label: '7-day',
                  sparkline: scale,
                  valueText: '−1.6 lb',
                  direction: ChangeDirection.decrease,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/weight_trend_preview.png'),
    );
  });

  testWidgets('expenditure trend preview', (tester) async {
    final exp = [
      for (var i = 0; i < 15; i++) 2820.0 + (268.0 / 14.0) * i + (i % 3) * 6,
    ];
    final intake = [
      for (var i = 0; i < 15; i++) 2500.0 + ((i % 4) - 1.5) * 70,
    ];
    final expSpots = [
      for (var i = 0; i < exp.length; i++) FlSpot(i.toDouble(), exp[i]),
    ];
    final intakeSpots = [
      for (var i = 0; i < intake.length; i++) FlSpot(i.toDouble(), intake[i]),
    ];

    await pumpStack(
      tester,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ChartStatHeader(
            leadingLabel: 'Average',
            leadingValue: '2940',
            leadingUnit: 'kcal',
            trailingLabel: 'Difference',
            trailingValue: '+268',
            trailingUnit: 'kcal',
            dateRangeText: 'Apr 1 – Apr 15, 2025',
            onToggleFit: _noop,
          ),
          const SizedBox(height: AppSpacing.x2),
          ExpenditureTrendChart(
            baseDate: DateTime(2025, 4, 1),
            expenditureSpots: expSpots,
            intakeSpots: intakeSpots,
            showExpenditure: true,
            showIntake: true,
            minY: 2400,
            maxY: 3100,
            rangeDays: 30,
          ),
          const SizedBox(height: AppSpacing.x2),
          ChartRangeBar(
            rangeOptions: const [7, 30, 90, 180, 365, 0],
            selectedRange: 30,
            rangeLabels: const {
              7: '1W',
              30: '1M',
              90: '3M',
              180: '6M',
              365: '1Y',
              0: 'All',
            },
            onSelectRange: (_) {},
            granularities: availableGranularities(30),
            selectedGranularity: ChartGranularity.day,
            onSelectGranularity: (_) {},
          ),
          const SizedBox(height: AppSpacing.x2),
          ChartLegendCard(
            entries: [
              ChartLegendEntry(
                swatch: ChartSwatch.lineDot,
                color: expenditureColor,
                label: 'Expenditure',
              ),
              ChartLegendEntry(
                swatch: ChartSwatch.line,
                color: intakeColor,
                label: 'Intake',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x3),
          Builder(
            builder: (context) => Text(
              'Insights & data',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          ChartChangesCard(
            title: 'Expenditure changes',
            accentColor: expenditureColor,
            rows: const [
              ChartChangeRow(
                label: '3-day',
                sparkline: [2980, 3000, 3020, 3060],
                valueText: '+31 kcal',
                direction: ChangeDirection.increase,
              ),
              ChartChangeRow(
                label: '7-day',
                sparkline: [2900, 2940, 2980, 3000, 3020, 3040, 3060],
                valueText: '+135 kcal',
                direction: ChangeDirection.increase,
              ),
            ],
          ),
        ],
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/expenditure_trend_preview.png'),
    );
  });
}

void _noop() {}
