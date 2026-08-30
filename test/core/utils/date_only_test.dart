import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/core/utils/date_only.dart';

void main() {
  test('parseLocalDateOnly parses YYYY-MM-DD into a local calendar date', () {
    final dt = parseLocalDateOnly('2024-06-10');
    expect(dt.year, 2024);
    expect(dt.month, 6);
    expect(dt.day, 10);
    expect(dt.hour, 0);
    expect(dt.minute, 0);
  });

  test('tryParseLocalDateOnly rejects invalid dates', () {
    expect(tryParseLocalDateOnly(''), isNull);
    expect(tryParseLocalDateOnly('foo'), isNull);
    expect(tryParseLocalDateOnly('2024-02-30'), isNull);
    expect(tryParseLocalDateOnly('2024-6-1'), isNull);
  });
}
