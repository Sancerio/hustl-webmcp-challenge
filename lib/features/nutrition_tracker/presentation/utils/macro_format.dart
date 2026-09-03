/// Canonical inline macro-breakdown text used across the nutrition surfaces
/// (diary rows, recipes, search, plate, edit sheets).
///
/// MacroFactor-style: one order — `P` then `F` then `C` — number-then-letter,
/// dot-separated, e.g. `33P · 7F · 0C`. Pass [calories] to prefix `NNN Cal · `.
/// Colored macro chips are reserved for the hero/bar contexts (diary header,
/// strategy cards); inline rows use this muted single-line string.
///
/// A null macro is OMITTED rather than shown as `0` — a partially-estimated
/// item (e.g. an AI scan unsure of carbs) must never read as a true zero.
String formatMacros({
  required double? protein,
  required double? fat,
  required double? carbs,
  double? calories,
}) {
  final parts = <String>[
    if (calories != null) '${calories.toStringAsFixed(0)} Cal',
    if (protein != null) '${protein.toStringAsFixed(0)}P',
    if (fat != null) '${fat.toStringAsFixed(0)}F',
    if (carbs != null) '${carbs.toStringAsFixed(0)}C',
  ];
  return parts.join(' · ');
}
