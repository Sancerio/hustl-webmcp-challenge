import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/charts/chart_axis.dart';

void main() {
  group('computeNiceAxis', () {
    test('kcal range lands on round hundreds', () {
      final axis = computeNiceAxis(2820, 3180);
      expect(axis.interval % 100, 0);
      expect(axis.min % axis.interval, 0);
      expect(axis.max % axis.interval, 0);
      expect(axis.min, lessThanOrEqualTo(2820));
      expect(axis.max, greaterThanOrEqualTo(3180));
      expect(axis.fractionDigits, 0);
    });

    test('tick labels are distinct', () {
      final axis = computeNiceAxis(2820, 3180);
      final labels = axis.tickLabels();
      expect(labels.toSet().length, labels.length, reason: 'dupes: $labels');
    });

    test('tight mode removes the breathing-room padding', () {
      final padded = computeNiceAxis(2820, 3180);
      final tight = computeNiceAxis(2820, 3180, tight: true);
      expect(tight.max - tight.min, lessThanOrEqualTo(padded.max - padded.min));
    });

    test('flat data opens a sensible window instead of collapsing', () {
      final axis = computeNiceAxis(3000, 3000);
      expect(axis.max, greaterThan(axis.min));
      expect(axis.isTick(axis.min), isTrue);
    });

    test('non-finite input degrades gracefully', () {
      final axis = computeNiceAxis(double.nan, double.infinity);
      expect(axis.min, 0);
      expect(axis.max, greaterThan(0));
    });
  });
}
