class NutritionLabelParseResult {
  const NutritionLabelParseResult({
    required this.rawText,
    this.productName,
    this.valuesPer100g = false,
    this.servingSizeGrams,
    this.caloriesKcal,
    this.proteinGrams,
    this.carbsGrams,
    this.fatGrams,
  });

  final String rawText;
  final String? productName;
  final bool valuesPer100g;
  final double? servingSizeGrams;
  final double? caloriesKcal;
  final double? proteinGrams;
  final double? carbsGrams;
  final double? fatGrams;

  double? get basisGrams => valuesPer100g ? 100 : servingSizeGrams;

  bool get hasAny =>
      caloriesKcal != null ||
      proteinGrams != null ||
      carbsGrams != null ||
      fatGrams != null;

  bool get hasMacros =>
      caloriesKcal != null &&
      proteinGrams != null &&
      carbsGrams != null &&
      fatGrams != null;
}

NutritionLabelParseResult parseNutritionLabelText(String rawText) {
  final trimmed = rawText.trim();
  final lower = trimmed.toLowerCase();
  final normalized = lower
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n+'), '\n');

  final lines = normalized
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList(growable: false);

  final valuesPer100g =
      RegExp(r'\bper\s*100\s*g\b').hasMatch(normalized) ||
      RegExp(r'\b100\s*g\s*serving\b').hasMatch(normalized);

  final servingSizeGrams = valuesPer100g
      ? null
      : _extractServingSizeGrams(normalized, lines: lines);

  final proteinGrams = _extractProteinGrams(normalized, lines: lines);
  final carbsGrams = _extractCarbsGrams(normalized, lines: lines);
  final fatGrams = _extractFatGrams(normalized, lines: lines);

  double? caloriesKcal = _extractCaloriesKcal(normalized, lines: lines);
  if (caloriesKcal == null &&
      proteinGrams != null &&
      carbsGrams != null &&
      fatGrams != null) {
    caloriesKcal = 4 * proteinGrams + 4 * carbsGrams + 9 * fatGrams;
  }

  return NutritionLabelParseResult(
    rawText: trimmed,
    productName: _guessProductName(trimmed),
    valuesPer100g: valuesPer100g,
    servingSizeGrams: servingSizeGrams,
    caloriesKcal: caloriesKcal,
    proteinGrams: proteinGrams,
    carbsGrams: carbsGrams,
    fatGrams: fatGrams,
  );
}

String? _guessProductName(String rawText) {
  final lines = rawText
      .replaceAll('\r', '\n')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList(growable: false);
  for (final line in lines) {
    final lower = line.toLowerCase();
    if (lower.contains('nutrition')) continue;
    if (lower.contains('facts')) continue;
    if (lower.contains('calories')) continue;
    if (lower.contains('protein')) continue;
    if (lower.contains('carb')) continue;
    if (lower.contains('fat')) continue;
    if (line.length < 3) continue;
    if (line.length > 60) continue;
    return line;
  }
  return null;
}

double? _extractServingSizeGrams(String text, {required List<String> lines}) {
  for (final line in lines) {
    if (!line.contains('serving size')) continue;
    final grams = _extractLastGrams(line);
    if (grams != null) return grams;
  }

  final fromText = _extractFromPatterns(text, const [
    r'\bserving\s+size\b[^\d]{0,40}(\d+(?:[.,]\d+)?)\s*g\b',
    r'\bper\s+serving\b[^\d]{0,40}\(?\s*(\d+(?:[.,]\d+)?)\s*g\)?\b',
  ]);
  return fromText;
}

double? _extractCaloriesKcal(String text, {required List<String> lines}) {
  final fromLine = _extractFromLines(
    lines,
    (l) => l.contains('calories') || l.contains('kcal'),
  );
  if (fromLine != null) return fromLine;

  return _extractFromPatterns(text, const [
    r'\bcalories\b[^\d]{0,20}(\d{1,4}(?:[.,]\d+)?)\b',
    r'\benergy\b[^\d]{0,20}(\d{1,4}(?:[.,]\d+)?)\s*kcal\b',
    r'\b(\d{1,4}(?:[.,]\d+)?)\s*kcal\b',
  ]);
}

double? _extractProteinGrams(String text, {required List<String> lines}) {
  final fromLine = _extractFromLines(lines, (l) => l.contains('protein'));
  if (fromLine != null) return fromLine;

  return _extractFromPatterns(text, const [
    r'\bprotein\b[^\d]{0,20}(\d{1,4}(?:[.,]\d+)?)\s*g?\b',
  ]);
}

double? _extractCarbsGrams(String text, {required List<String> lines}) {
  final fromLine = _extractFromLines(
    lines,
    (l) =>
        (l.contains('total carbohydrate') ||
            l.contains('carbohydrate') ||
            l.contains('carbs')) &&
        !l.contains('fiber') &&
        !l.contains('sugar'),
  );
  if (fromLine != null) return fromLine;

  return _extractFromPatterns(text, const [
    r'\btotal\s+carbohydrate\b[^\d]{0,20}(\d{1,4}(?:[.,]\d+)?)\s*g?\b',
    r'\bcarbohydrate\b[^\d]{0,20}(\d{1,4}(?:[.,]\d+)?)\s*g?\b',
    r'\bcarbs?\b[^\d]{0,20}(\d{1,4}(?:[.,]\d+)?)\s*g?\b',
  ]);
}

double? _extractFatGrams(String text, {required List<String> lines}) {
  final fromTotalFatLine = _extractFromLines(
    lines,
    (l) => l.contains('total fat'),
  );
  if (fromTotalFatLine != null) return fromTotalFatLine;

  final fromLine = _extractFromLines(
    lines,
    (l) =>
        l.contains('fat') &&
        !l.contains('saturated') &&
        !l.contains('trans') &&
        !l.contains('poly') &&
        !l.contains('mono'),
  );
  if (fromLine != null) return fromLine;

  return _extractFromPatterns(text, const [
    r'\btotal\s+fat\b[^\d]{0,20}(\d{1,4}(?:[.,]\d+)?)\s*g?\b',
    r'\bfat\b[^\d]{0,20}(\d{1,4}(?:[.,]\d+)?)\s*g?\b',
  ]);
}

double? _extractFromLines(List<String> lines, bool Function(String) predicate) {
  for (final line in lines) {
    if (!predicate(line)) continue;
    final value = _extractFirstNumber(line);
    if (value != null) return value;
  }
  return null;
}

double? _extractFromPatterns(String text, List<String> patterns) {
  for (final pattern in patterns) {
    final match = RegExp(pattern).firstMatch(text);
    if (match == null) continue;
    final parsed = _parseNumber(match.group(1));
    if (parsed != null) return parsed;
  }
  return null;
}

double? _extractFirstNumber(String text) {
  final match = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(text);
  return match == null ? null : _parseNumber(match.group(1));
}

double? _extractLastGrams(String text) {
  final matches = RegExp(r'(\d+(?:[.,]\d+)?)\s*g\b').allMatches(text);
  if (matches.isEmpty) return null;
  return _parseNumber(matches.last.group(1));
}

double? _parseNumber(String? raw) {
  if (raw == null) return null;
  final cleaned = raw.replaceAll(',', '.').trim();
  return double.tryParse(cleaned);
}
