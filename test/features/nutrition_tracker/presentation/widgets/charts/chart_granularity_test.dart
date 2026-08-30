import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/charts/chart_granularity.dart';

void main() {
  group('availableGranularities', () {
    test('a one-week window only offers daily', () {
      expect(availableGranularities(7), [ChartGranularity.day]);
      expect(defaultGranularity(7), ChartGranularity.day);
    });

    test('a month offers daily + weekly, defaulting to daily', () {
      expect(availableGranularities(30), [
        ChartGranularity.day,
        ChartGranularity.week,
      ]);
      expect(defaultGranularity(30), ChartGranularity.day);
    });

    test('long ranges drop daily in favour of weekly/monthly', () {
      expect(availableGranularities(365), [
        ChartGranularity.week,
        ChartGranularity.month,
      ]);
      expect(availableGranularities(0), [
        ChartGranularity.week,
        ChartGranularity.month,
      ]);
      expect(defaultGranularity(0), ChartGranularity.week);
    });
  });

  group('aggregateSpots', () {
    test('daily granularity returns the spots untouched', () {
      final spots = [for (var i = 0; i < 10; i++) FlSpot(i.toDouble(), i * 1.0)];
      expect(aggregateSpots(spots, ChartGranularity.day), spots);
    });

    test('weekly granularity averages 7-day buckets', () {
      // 14 days, value == day index. Buckets: days 0-6 (avg 3), 7-13 (avg 10).
      final spots = [for (var i = 0; i < 14; i++) FlSpot(i.toDouble(), i * 1.0)];
      final out = aggregateSpots(spots, ChartGranularity.week);
      expect(out, hasLength(2));
      expect(out[0].y, closeTo(3.0, 1e-9));
      expect(out[1].y, closeTo(10.0, 1e-9));
    });

    test('sparse series (< 3 points) is left untouched', () {
      final spots = [const FlSpot(0, 1), const FlSpot(8, 2)];
      expect(aggregateSpots(spots, ChartGranularity.week), spots);
    });
  });
}
