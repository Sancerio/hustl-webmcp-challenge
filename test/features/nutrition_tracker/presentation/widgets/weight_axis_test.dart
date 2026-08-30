import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/weight_axis.dart';

void main() {
  group('computeWeightAxis', () {
    test('produces distinct gridline labels for a tight sub-1kg range', () {
      // The old chart rounded a ~2kg span to 0 decimals over a 0.5kg interval,
      // collapsing ticks into "71, 71, 70, 70, 69". A clean axis must not.
      final axis = computeWeightAxis(69.2, 71.4);
      final labels = axis.tickLabels();

      expect(labels.length, greaterThanOrEqualTo(3));
      expect(
        labels.toSet().length,
        labels.length,
        reason: 'no duplicate y-axis tick labels: $labels',
      );
    });

    test('bounds snap to multiples of the interval and contain the data', () {
      final axis = computeWeightAxis(69.2, 71.4);

      expect(axis.min, lessThanOrEqualTo(69.2));
      expect(axis.max, greaterThanOrEqualTo(71.4));
      expect((axis.min / axis.interval) % 1, closeTo(0, 1e-9));
      expect((axis.max / axis.interval) % 1, closeTo(0, 1e-9));
    });

    test('every rendered tick reads as a distinct value', () {
      // Sweep a few realistic ranges; none may yield a duplicate label.
      for (final pair in const [
        [69.0, 71.0],
        [70.1, 70.9],
        [80.0, 95.0],
        [55.3, 58.8],
      ]) {
        final axis = computeWeightAxis(pair[0], pair[1]);
        final labels = axis.tickLabels();
        expect(
          labels.toSet().length,
          labels.length,
          reason: 'duplicate labels for $pair -> $labels',
        );
      }
    });

    test('isTick only accepts values on the gridline', () {
      final axis = computeWeightAxis(70.0, 74.0);
      expect(axis.isTick(axis.min), isTrue);
      expect(axis.isTick(axis.min + axis.interval), isTrue);
      expect(axis.isTick(axis.min + axis.interval / 3), isFalse);
      expect(axis.isTick(axis.max + axis.interval), isFalse);
    });

    test('flat data opens a sensible window instead of a single line', () {
      final axis = computeWeightAxis(70.0, 70.0);
      expect(axis.max, greaterThan(axis.min));
      expect(axis.min, lessThanOrEqualTo(70.0));
      expect(axis.max, greaterThanOrEqualTo(70.0));
      expect(axis.tickLabels().toSet().length, axis.tickLabels().length);
    });

    test('uses 1 decimal only when the interval is sub-1kg', () {
      expect(computeWeightAxis(70.0, 90.0).fractionDigits, 0);
      expect(computeWeightAxis(70.2, 71.0).fractionDigits, 1);
    });
  });
}
