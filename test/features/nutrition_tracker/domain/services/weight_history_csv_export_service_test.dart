import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/services/weight_history_csv_export_service.dart';

void main() {
  const exporter = WeightHistoryCsvExportService();

  const expectedHeader = 'date,weight_kg,trend_kg,source';

  test('happy path: one row per weigh-in with trend joined by date', () {
    final csv = exporter.buildCsv({
      'scale': [
        // Out of order on purpose — export must sort by date.
        {'date': '2024-06-03', 'weightKg': 79.4, 'source': 'apple_health'},
        {'date': '2024-06-01', 'weightKg': 80.0, 'source': 'self'},
      ],
      'trend': [
        {'date': '2024-06-01', 'trendKg': 80.05},
        {'date': '2024-06-03', 'trendKg': 79.8},
      ],
    });

    final lines = csv.split('\n');
    expect(lines.first, expectedHeader);
    // Stored kg only (80.0 -> 80, no display-unit conversion).
    expect(lines[1], '2024-06-01,80,80.05,self');
    expect(lines[2], '2024-06-03,79.4,79.8,apple_health');
  });

  test('empty payload exports just the header', () {
    expect(exporter.buildCsv(const {}), expectedHeader);
    expect(
      exporter.buildCsv(const {'scale': [], 'trend': []}),
      expectedHeader,
    );
  });

  test('a weigh-in without a trend point leaves trend_kg empty', () {
    final csv = exporter.buildCsv({
      'scale': [
        {'date': '2024-06-02', 'weightKg': 81, 'source': 'self'},
      ],
      'trend': const [],
    });

    expect(csv.split('\n')[1], '2024-06-02,81,,self');
  });

  test('malformed points are skipped, sources with commas are quoted', () {
    final csv = exporter.buildCsv({
      'scale': [
        {'date': '2024-06-01'}, // no weightKg
        {'weightKg': 75}, // no date
        {'date': '2024-06-02', 'weightKg': 74.5, 'source': 'scale, smart'},
        {'date': '2024-06-03', 'weightKg': 74.25}, // no source
      ],
      'trend': const [],
    });

    final lines = csv.split('\n');
    expect(lines, hasLength(3));
    expect(lines[1], '2024-06-02,74.5,,"scale, smart"');
    expect(lines[2], '2024-06-03,74.25,,');
  });

  test('file name is dated', () {
    expect(
      exporter.fileName(now: DateTime(2024, 7, 5)),
      'hustl-weight-20240705.csv',
    );
  });
}
