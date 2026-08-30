import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

import '../models/food_log_entry.dart';

/// Builds the nutrition (food log) CSV export.
///
/// Pure, deterministic, and unit-testable — mirrors
/// `StrongCsvExportService`: fixed column order, RFC-4180 quoting via
/// `ListToCsvConverter`, ISO dates, gram/mg units straight from
/// [FoodLogEntry] (no conversions, so exported numbers always match the app).
class FoodLogCsvExportService {
  const FoodLogCsvExportService();

  /// Column order is a documented contract — the widget test and any
  /// downstream import rely on it. Every column maps 1:1 to a
  /// [FoodLogEntry] field; nullable fields export as empty strings.
  static const List<String> header = [
    'date',
    'logged_at',
    'food_name',
    'brand',
    'portion',
    'serving_grams',
    'calories',
    'protein_g',
    'carbs_g',
    'fat_g',
    'fiber_g',
    'sugar_g',
    'sodium_mg',
    'source',
  ];

  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _timestampFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
  static final DateFormat _fileDateFormat = DateFormat('yyyyMMdd');

  String fileName({DateTime? now}) {
    final date = (now ?? DateTime.now()).toLocal();
    return 'hustl-nutrition-${_fileDateFormat.format(date)}.csv';
  }

  String buildCsv(List<FoodLogEntry> entries) {
    final stableEntries = [...entries]
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) return byDate;
        return a.loggedAt.compareTo(b.loggedAt);
      });

    final rows = <List<String>>[header];
    for (final entry in stableEntries) {
      rows.add([
        _dateFormat.format(entry.date),
        _timestampFormat.format(entry.loggedAt.toLocal()),
        entry.foodName ?? entry.food?.name ?? '',
        entry.food?.brand ?? '',
        entry.portionLabel ?? '',
        _formatNumber(entry.servingGrams),
        _formatNumber(entry.calories),
        _formatNumber(entry.proteinGrams),
        _formatNumber(entry.carbsGrams),
        _formatNumber(entry.fatGrams),
        _formatOptional(entry.fiberGrams),
        _formatOptional(entry.sugarGrams),
        _formatOptional(entry.sodiumMg),
        entry.source,
      ]);
    }

    return const ListToCsvConverter(eol: '\n').convert(rows);
  }

  String _formatOptional(double? value) =>
      value == null ? '' : _formatNumber(value);

  String _formatNumber(double value) {
    final fixed = value.toStringAsFixed(3);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
