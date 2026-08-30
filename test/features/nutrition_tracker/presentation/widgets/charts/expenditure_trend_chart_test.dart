import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/charts/expenditure_trend_chart.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  List<FlSpot> expSpots() => const [
    FlSpot(0, 2900),
    FlSpot(1, 2940),
    FlSpot(2, 2980),
    FlSpot(3, 3020),
    FlSpot(4, 3060),
  ];
  List<FlSpot> intakeSpots() => const [
    FlSpot(0, 2500),
    FlSpot(1, 2450),
    FlSpot(2, 2600),
    FlSpot(3, 2550),
    FlSpot(4, 2480),
  ];

  ExpenditureTrendChart chart({
    bool showExpenditure = true,
    bool showIntake = true,
  }) => ExpenditureTrendChart(
    baseDate: DateTime(2025, 4, 1),
    expenditureSpots: expSpots(),
    intakeSpots: intakeSpots(),
    showExpenditure: showExpenditure,
    showIntake: showIntake,
    minY: 2450,
    maxY: 3060,
    rangeDays: 30,
  );

  testWidgets('renders a single LineChart with both series', (tester) async {
    await tester.pumpWidget(wrap(chart()));
    await tester.pump();
    expect(find.byType(LineChart), findsOneWidget);
    expect(
      tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData,
      hasLength(2),
    );
  });

  testWidgets('only the expenditure series carries the area fill', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(chart()));
    await tester.pump();
    final bars = tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .lineBarsData;
    final filled = bars.where((b) => b.belowBarData.show).toList();
    expect(filled, hasLength(1));
  });

  testWidgets('toggling intake off leaves just the filled expenditure line', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(chart(showIntake: false)));
    await tester.pump();
    final bars = tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .lineBarsData;
    expect(bars, hasLength(1));
    expect(bars.single.belowBarData.show, isTrue);
  });
}
