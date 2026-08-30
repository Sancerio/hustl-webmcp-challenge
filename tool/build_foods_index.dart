// build_foods_index.dart
//
// Transforms a USDA FoodData Central (FDC) bulk export into the compact
// `assets/data/foods_generic.json` asset used by the app's offline food search.
//
// USDA FDC data for the Foundation, SR Legacy, and Survey (FNDDS) datasets is
// lab-analyzed, complete, and released under CC0 (public domain), so it can be
// bundled directly. Branded foods are intentionally excluded (licensing +
// barcode/brand fields are out of scope for the generic index).
//
// Usage:
//   dart run tool/build_foods_index.dart <path-to-usda-export.json> [--output path/to/output.json]
//   dart run tool/build_foods_index.dart <path-to-usda-export.csv>  [--output path/to/output.json]
//   dart run tool/build_foods_index.dart --help
//
// Example:
//   # Download "Foundation Foods" or "SR Legacy" JSON from
//   # https://fdc.nal.usda.gov/download-datasets.html, unzip, then:
//   dart run tool/build_foods_index.dart FoodData_Central_foundation_food_json_2024.json
//   # -> writes assets/data/foods_generic.json
//
//   # Custom output location:
//   dart run tool/build_foods_index.dart sr_legacy.json --output /tmp/foods.json
//
// Output shape (one object per food):
//   {
//     "id": "fdc-171705",
//     "name": "Egg, whole, raw, fresh",
//     "caloriesPer100g": 143,
//     "proteinGramsPer100g": 12.6,
//     "carbsGramsPer100g": 0.72,
//     "fatGramsPer100g": 9.51,
//     "source": "fdc",
//     "dataType": "SR Legacy"
//   }
//
// Behavior:
//   - Filters to dataType in {Foundation, SR Legacy, Survey (FNDDS)}.
//   - Normalizes per-100g energy/protein/carb/fat from FDC nutrient numbers.
//   - Drops any row missing one or more of the four core macros.
//   - Omits barcode/brand fields (generic data only).
//   - Warns (non-zero exit) if the result is empty or malformed.
//
// Dependency-light by design: only dart:io and dart:convert.

import 'dart:convert';
import 'dart:io';

/// Allowed USDA dataTypes (lab-analyzed, complete, CC0-licensed).
const Set<String> _allowedDataTypes = {
  'Foundation',
  'SR Legacy',
  'Survey (FNDDS)',
};

/// FDC nutrient numbers for the four core macros. Energy has two numbers:
/// 208 (kcal) is preferred; 1008 is the newer "Energy" id; 957 is kJ-derived
/// Atwater energy which we ignore in favour of the kcal value.
const Set<String> _energyNutrientNumbers = {'208', '1008'};
const Set<String> _proteinNutrientNumbers = {'203', '1003'};
const Set<String> _carbNutrientNumbers = {'205', '1005'};
const Set<String> _fatNutrientNumbers = {'204', '1004'};

const String _defaultOutput = 'assets/data/foods_generic.json';

const String _helpText =
    '''
build_foods_index — USDA FoodData Central -> compact foods asset

Usage:
  dart run tool/build_foods_index.dart <path-to-usda-export.json> [--output <path>]
  dart run tool/build_foods_index.dart <path-to-usda-export.csv>  [--output <path>]
  dart run tool/build_foods_index.dart --help

Arguments:
  <path>            Path to a USDA FDC bulk export (.json or .csv).
  --output <path>   Output file (default: $_defaultOutput).
  -h, --help        Show this help.

Filters to dataType in {Foundation, SR Legacy, Survey (FNDDS)} and emits one
compact record per food with per-100g calories/protein/carbs/fat. Rows missing
any of the four core macros are dropped. Brand/barcode fields are omitted.
''';

void main(List<String> args) {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    stdout.write(_helpText);
    return;
  }

  String? inputPath;
  String outputPath = _defaultOutput;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--output' || arg == '-o') {
      if (i + 1 >= args.length) {
        _fail('Missing value for $arg');
      }
      outputPath = args[++i];
    } else if (arg.startsWith('--output=')) {
      outputPath = arg.substring('--output='.length);
    } else if (arg.startsWith('-')) {
      _fail('Unknown option: $arg');
    } else {
      if (inputPath != null) {
        _fail('Unexpected extra argument: $arg');
      }
      inputPath = arg;
    }
  }

  if (inputPath == null) {
    _fail('No input file provided. See --help.');
  }

  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    _fail('Input file not found: $inputPath');
  }

  final raw = inputFile.readAsStringSync();
  final lower = inputPath.toLowerCase();
  final List<Map<String, dynamic>> records;
  if (lower.endsWith('.csv')) {
    records = _parseCsvExport(raw);
  } else {
    records = _parseJsonExport(raw);
  }

  if (records.isEmpty) {
    _warn(
      'No qualifying foods were produced from $inputPath. '
      'Check that the export contains Foundation / SR Legacy / Survey '
      '(FNDDS) foods with complete macros.',
    );
    exit(2);
  }

  final encoded = const JsonEncoder.withIndent('  ').convert(records);

  // Validate that the output is itself valid JSON before writing.
  try {
    final reparsed = jsonDecode(encoded);
    if (reparsed is! List || reparsed.isEmpty) {
      _warn('Generated output is malformed (not a non-empty list).');
      exit(2);
    }
  } on FormatException catch (e) {
    _warn('Generated output failed re-parse validation: $e');
    exit(2);
  }

  final outFile = File(outputPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync('$encoded\n');

  stdout.writeln('Wrote ${records.length} foods to $outputPath');
}

/// Parses a USDA FDC JSON export. Handles both the wrapped object shape
/// (`{"FoundationFoods": [...]}`, `{"SRLegacyFoods": [...]}`,
/// `{"SurveyFoods": [...]}`) and a flat top-level array of food objects.
List<Map<String, dynamic>> _parseJsonExport(String raw) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (e) {
    _fail('Input is not valid JSON: $e');
  }

  final List<dynamic> foods = [];
  if (decoded is List) {
    foods.addAll(decoded);
  } else if (decoded is Map<String, dynamic>) {
    for (final key in const [
      'FoundationFoods',
      'SRLegacyFoods',
      'SurveyFoods',
    ]) {
      final value = decoded[key];
      if (value is List) {
        foods.addAll(value);
      }
    }
    if (foods.isEmpty) {
      // Fall back to the first list-valued top-level key.
      for (final value in decoded.values) {
        if (value is List) {
          foods.addAll(value);
          break;
        }
      }
    }
  } else {
    _fail('Unsupported JSON top-level type: ${decoded.runtimeType}');
  }

  return transformUsdaExport(foods.whereType<Map>().toList());
}

/// Pure transform: maps a list of raw FDC food objects into compact records.
///
/// Exposed (no file I/O, no `exit`) so the USDA -> JSON transformation can be
/// unit-tested directly. The CLI calls this after extracting the food list from
/// whichever wrapper shape the export used.
///
/// Each input item is mapped via [_mapJsonFood]; out-of-scope rows (wrong
/// dataType, missing description/id) and rows missing any of the four core
/// macros are dropped.
List<Map<String, dynamic>> transformUsdaExport(List<Map> items) {
  final out = <Map<String, dynamic>>[];
  for (final food in items) {
    final record = _mapJsonFood(food.cast<String, dynamic>());
    if (record != null) out.add(record);
  }
  return out;
}

/// Maps a single FDC JSON food object into a compact record, or null if it is
/// out of scope (wrong dataType) or missing a core macro.
Map<String, dynamic>? _mapJsonFood(Map<String, dynamic> food) {
  final dataType = (food['dataType'] as String?)?.trim();
  if (dataType == null || !_allowedDataTypes.contains(dataType)) {
    return null;
  }

  final fdcId = food['fdcId'];
  final description = (food['description'] as String?)?.trim();
  if (fdcId == null || description == null || description.isEmpty) {
    return null;
  }

  final nutrients = food['foodNutrients'];
  if (nutrients is! List) return null;

  double? calories;
  double? protein;
  double? carbs;
  double? fat;

  for (final entry in nutrients) {
    if (entry is! Map) continue;
    final nutrient = entry['nutrient'];
    String? number;
    if (nutrient is Map && nutrient['number'] != null) {
      number = nutrient['number'].toString();
    } else if (entry['nutrientNumber'] != null) {
      number = entry['nutrientNumber'].toString();
    }
    if (number == null) continue;

    final amount = _asDouble(entry['amount']);
    if (amount == null) continue;

    if (_energyNutrientNumbers.contains(number)) {
      calories ??= amount;
    } else if (_proteinNutrientNumbers.contains(number)) {
      protein ??= amount;
    } else if (_carbNutrientNumbers.contains(number)) {
      carbs ??= amount;
    } else if (_fatNutrientNumbers.contains(number)) {
      fat ??= amount;
    }
  }

  return _buildRecord(
    fdcId: fdcId,
    description: description,
    dataType: dataType,
    calories: calories,
    protein: protein,
    carbs: carbs,
    fat: fat,
  );
}

/// Parses a joined USDA CSV export (`food.csv` joined with `food_nutrient.csv`).
///
/// Two layouts are supported:
///   1. A pre-joined flat CSV with columns: fdc_id, description, data_type,
///      and macro columns named energy_kcal/protein_g/carbohydrate_g/fat_g
///      (case-insensitive, underscores or spaces tolerated).
///   2. The raw `food_nutrient.csv` long format with columns fdc_id,
///      nutrient_id (FDC number), amount — paired with food rows that carry
///      description/data_type.
List<Map<String, dynamic>> _parseCsvExport(String raw) {
  final rows = _parseCsvRows(raw);
  if (rows.isEmpty) return [];

  final header = rows.first.map((c) => _normalizeHeader(c)).toList();
  int idx(List<String> names) {
    for (final n in names) {
      final i = header.indexOf(n);
      if (i >= 0) return i;
    }
    return -1;
  }

  final fdcIdx = idx(['fdc_id', 'fdcid', 'id']);
  final descIdx = idx(['description', 'name']);
  final typeIdx = idx(['data_type', 'datatype']);

  // Wide layout: macros as their own columns.
  final calIdx = idx(['energy_kcal', 'calories', 'energy', 'kcal']);
  final proIdx = idx(['protein_g', 'protein', 'protein_grams']);
  final carbIdx = idx(['carbohydrate_g', 'carbs', 'carbohydrate', 'carbs_g']);
  final fatIdx = idx(['total_fat_g', 'fat', 'fat_g', 'total_lipid_fat']);

  if (fdcIdx >= 0 &&
      descIdx >= 0 &&
      calIdx >= 0 &&
      proIdx >= 0 &&
      carbIdx >= 0 &&
      fatIdx >= 0) {
    final out = <Map<String, dynamic>>[];
    for (final row in rows.skip(1)) {
      if (row.length <= fdcIdx) continue;
      final dataType = typeIdx >= 0 && row.length > typeIdx
          ? row[typeIdx].trim()
          : '';
      // Only filter when a data_type column exists; otherwise trust the input.
      if (typeIdx >= 0 && !_allowedDataTypes.contains(dataType)) continue;

      final record = _buildRecord(
        fdcId: row[fdcIdx].trim(),
        description: row[descIdx].trim(),
        dataType: dataType.isEmpty ? 'SR Legacy' : dataType,
        calories: _asDouble(_cell(row, calIdx)),
        protein: _asDouble(_cell(row, proIdx)),
        carbs: _asDouble(_cell(row, carbIdx)),
        fat: _asDouble(_cell(row, fatIdx)),
      );
      if (record != null) out.add(record);
    }
    return out;
  }

  _fail(
    'Unsupported CSV layout. Expected a pre-joined export with columns '
    'fdc_id, description, data_type, energy_kcal, protein_g, '
    'carbohydrate_g, total_fat_g. For raw multi-file CSV exports, join them '
    'first or use the JSON export instead.',
  );
}

/// Builds a compact record from raw values, returning null if any of the four
/// core macros is missing.
Map<String, dynamic>? _buildRecord({
  required Object fdcId,
  required String description,
  required String dataType,
  required double? calories,
  required double? protein,
  required double? carbs,
  required double? fat,
}) {
  if (calories == null || protein == null || carbs == null || fat == null) {
    return null;
  }
  return {
    'id': 'fdc-$fdcId',
    'name': description,
    'caloriesPer100g': _trim(calories),
    'proteinGramsPer100g': _trim(protein),
    'carbsGramsPer100g': _trim(carbs),
    'fatGramsPer100g': _trim(fat),
    'source': 'fdc',
    'dataType': dataType,
  };
}

/// Returns an int when the value is whole, otherwise a double rounded to 2dp.
num _trim(double value) {
  final rounded = double.parse(value.toStringAsFixed(2));
  if (rounded == rounded.roundToDouble()) return rounded.round();
  return rounded;
}

String _cell(List<String> row, int index) =>
    index >= 0 && index < row.length ? row[index] : '';

double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

String _normalizeHeader(String h) =>
    h.trim().toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');

/// Minimal RFC-4180-ish CSV parser (quotes, escaped quotes, embedded commas
/// and newlines). Kept inline to avoid third-party dependencies.
List<List<String>> _parseCsvRows(String input) {
  final rows = <List<String>>[];
  var field = StringBuffer();
  var row = <String>[];
  var inQuotes = false;

  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else {
      if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        row.add(field.toString());
        field = StringBuffer();
      } else if (ch == '\n') {
        row.add(field.toString());
        field = StringBuffer();
        rows.add(row);
        row = <String>[];
      } else if (ch == '\r') {
        // Skip; handled by the following \n (or treat lone \r as line end).
        if (i + 1 >= input.length || input[i + 1] != '\n') {
          row.add(field.toString());
          field = StringBuffer();
          rows.add(row);
          row = <String>[];
        }
      } else {
        field.write(ch);
      }
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  // Drop fully-empty trailing rows.
  rows.removeWhere((r) => r.length == 1 && r.first.trim().isEmpty);
  return rows;
}

Never _fail(String message) {
  stderr.writeln('Error: $message');
  exit(64); // EX_USAGE
}

void _warn(String message) {
  stderr.writeln('Warning: $message');
}
