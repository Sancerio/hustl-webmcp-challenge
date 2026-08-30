import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/utils/weight_unit.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/weight_stat_strip.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/weight_trend_cards.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  List<FlSpot> rampSpots() => const [
    FlSpot(0, 71.4),
    FlSpot(1, 71.0),
    FlSpot(2, 70.6),
    FlSpot(3, 70.1),
    FlSpot(4, 69.7),
  ];

  WeightTrendChart chart({bool showScale = true, bool showTrend = true}) =>
      WeightTrendChart(
        baseDate: DateTime(2024, 6, 1),
        scaleSpots: rampSpots(),
        trendSpots: rampSpots(),
        showScale: showScale,
        showTrend: showTrend,
        minY: 69.7,
        maxY: 71.4,
        unit: const WeightUnit('kg'),
        rangeDays: 30,
      );

  group('WeightTrendChart', () {
    testWidgets('renders a single LineChart inside a RepaintBoundary', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(chart()));
      await tester.pump();
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.byType(RepaintBoundary), findsWidgets);
    });

    testWidgets('show toggles control which lines render', (tester) async {
      await tester.pumpWidget(wrap(chart()));
      await tester.pump();
      expect(
        tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData,
        hasLength(2),
      );

      await tester.pumpWidget(wrap(chart(showScale: false)));
      await tester.pump();
      expect(
        tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData,
        hasLength(1),
      );
    });

    testWidgets('trend line has no area fill (clean reference look)', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(chart(showScale: false)));
      await tester.pump();
      final bars = tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .lineBarsData;
      expect(bars.single.belowBarData.show, isFalse);
    });

    testWidgets('right y-axis tick labels are distinct (no duplicate ticks)', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(chart(showScale: false)));
      await tester.pumpAndSettle();
      final c = tester.widget<LineChart>(find.byType(LineChart));
      final rightTitles = c.data.titlesData.rightTitles.sideTitles;
      final interval = rightTitles.interval!;
      final labels = <String>[];
      for (var v = c.data.minY; v <= c.data.maxY + 1e-6; v += interval) {
        final widget = rightTitles.getTitlesWidget(
          v,
          TitleMeta(
            min: c.data.minY,
            max: c.data.maxY,
            parentAxisSize: 200,
            axisPosition: 0,
            appliedInterval: interval,
            sideTitles: rightTitles,
            formattedValue: '',
            axisSide: AxisSide.right,
            rotationQuarterTurns: 0,
          ),
        );
        if (widget is Padding && widget.child is Text) {
          labels.add((widget.child as Text).data!);
        }
      }
      expect(labels, isNotEmpty);
      expect(labels.toSet().length, labels.length, reason: 'dupes: $labels');
    });
  });

  group('WeightStatStrip', () {
    testWidgets('renders change / weekly rate / average', (tester) async {
      await tester.pumpWidget(
        wrap(
          const WeightStatStrip(
            unit: WeightUnit('kg'),
            periodChangeKg: -1.7,
            weeklyRateKg: -0.42,
            periodAverageKg: 70.5,
            goalType: 'lose',
            periodLabel: '1M',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Change · 1M'), findsOneWidget);
      expect(find.text('−1.7 kg'), findsOneWidget);
      expect(find.text('Weekly rate'), findsOneWidget);
      expect(find.text('−0.42 kg/wk'), findsOneWidget);
      expect(find.text('Average'), findsOneWidget);
      expect(find.text('70.5 kg'), findsOneWidget);
    });

    testWidgets('em dashes when values are unknown', (tester) async {
      await tester.pumpWidget(
        wrap(
          const WeightStatStrip(
            unit: WeightUnit('kg'),
            periodChangeKg: null,
            weeklyRateKg: null,
            periodAverageKg: null,
            goalType: null,
            periodLabel: '1W',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('—'), findsWidgets);
    });
  });
}
