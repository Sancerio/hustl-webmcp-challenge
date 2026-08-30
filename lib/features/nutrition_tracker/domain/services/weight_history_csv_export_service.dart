import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

/// Builds the weight-history CSV export from the raw
/// `NutritionTargetsRepository.getWeightTrend` payload
/// (`{scale: [{date, weightKg, source}], trend: [{date, trendKg}], ...}`).
///
/// Pure and unit-testable, mirroring `StrongCsvExportService`: fixed column
/// order, RFC-4180 quoting, ISO dates, kilograms only (the stored unit —
/// display-unit conversion is deliberately NOT applied so the export is
/// unambiguous).
class WeightHistoryCsvExportService {
  const WeightHistoryCsvExportService();

  /// One row per scale weigh-in day; `trend_kg` is joined by date and empty
  /// when the backend has no trend point for that day. `source` comes from
  /// the scale point itself (e.g. `self`, `apple_health`).
  static const List<String> header = [
    'date',
    'weight_kg',
    'trend_kg',
    'source',
  ];

  static final DateFormat _fileDateFormat = DateFormat('yyyyMMdd');

  String fileName({DateTime? now}) {
    final date = (now ?? DateTime.now()).toLocal();
    return 'hustl-weight-${_fileDateFormat.format(date)}.csv';
  }

  String buildCsv(Map<String, dynamic> trendPayload) {
    final scale = (trendPayload['scale'] as List?) ?? const [];
    final trend = (trendPayload['trend'] as List?) ?? const [];

    final trendByDate = <String, double>{
      for (final point in trend)
        if (point is Map &&
            point['date'] is String &&
            point['trendKg'] is num)
          point['date'] as String: (point['trendKg'] as num).toDouble(),
    };

    final rows = <List<String>>[header];
    final scalePoints = scale
        .whereType<Map>()
        .where((p) => p['date'] is String && p['weightKg'] is num)
        .toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    for (final point in scalePoints) {
      final date = point['date'] as String;
      final trendKg = trendByDate[date];
      rows.add([
        date,
        _formatNumber((point['weightKg'] as num).toDouble()),
        trendKg == null ? '' : _formatNumber(trendKg),
        point['source']?.toString() ?? '',
      ]);
    }

    return const ListToCsvConverter(eol: '\n').convert(rows);
  }

  String _formatNumber(double value) {
    final fixed = value.toStringAsFixed(3);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
