import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/charts/chart_stat_header.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: child));

  testWidgets('renders both stats, units, and the date range', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ChartStatHeader(
          leadingLabel: 'Average',
          leadingValue: '153.5',
          leadingUnit: 'lb',
          trailingLabel: 'Difference',
          trailingValue: '−1.6',
          trailingUnit: 'lb',
          dateRangeText: 'Apr 6 – Apr 12, 2025',
        ),
      ),
    );

    expect(find.text('Average'), findsOneWidget);
    expect(find.text('153.5'), findsOneWidget);
    expect(find.text('Difference'), findsOneWidget);
    expect(find.text('−1.6'), findsOneWidget);
    expect(find.text('lb'), findsNWidgets(2));
    expect(find.text('Apr 6 – Apr 12, 2025'), findsOneWidget);
  });

  testWidgets('the fit button only renders when a handler is provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const ChartStatHeader(
          leadingLabel: 'Average',
          leadingValue: '153.5',
          leadingUnit: 'lb',
          trailingLabel: 'Difference',
          trailingValue: '−1.6',
          trailingUnit: 'lb',
          dateRangeText: 'Apr 6 – Apr 12, 2025',
        ),
      ),
    );
    expect(find.byIcon(Icons.unfold_more), findsNothing);

    var toggled = 0;
    await tester.pumpWidget(
      wrap(
        ChartStatHeader(
          leadingLabel: 'Average',
          leadingValue: '153.5',
          leadingUnit: 'lb',
          trailingLabel: 'Difference',
          trailingValue: '−1.6',
          trailingUnit: 'lb',
          dateRangeText: 'Apr 6 – Apr 12, 2025',
          onToggleFit: () => toggled++,
        ),
      ),
    );
    expect(find.byIcon(Icons.unfold_more), findsOneWidget);
    await tester.tap(find.byIcon(Icons.unfold_more));
    expect(toggled, 1);
  });
}
