import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/utils/number_format_util.dart';

void main() {
  group('NumberFormatUtil.formatWeight', () {
    test('preserves micro-plate precision (regression: 3.75 must not become '
        '3.8)', () {
      expect(NumberFormatUtil.formatWeight(3.75), '3.75');
      expect(NumberFormatUtil.formatWeight(1.25), '1.25');
      expect(NumberFormatUtil.formatWeight(11.25), '11.25');
    });

    test('shows whole numbers with no decimals', () {
      expect(NumberFormatUtil.formatWeight(60), '60');
      expect(NumberFormatUtil.formatWeight(100), '100');
      expect(NumberFormatUtil.formatWeight(0), '0');
    });

    test('keeps half-kilo plates', () {
      expect(NumberFormatUtil.formatWeight(62.5), '62.5');
      expect(NumberFormatUtil.formatWeight(2.5), '2.5');
    });

    test('trims trailing zeros', () {
      expect(NumberFormatUtil.formatWeight(3.70), '3.7');
      expect(NumberFormatUtil.formatWeight(3.50), '3.5');
    });

    test('handles negative (assisted) weights', () {
      expect(NumberFormatUtil.formatWeight(-20), '-20');
      expect(NumberFormatUtil.formatWeight(-12.5), '-12.5');
    });
  });
}
