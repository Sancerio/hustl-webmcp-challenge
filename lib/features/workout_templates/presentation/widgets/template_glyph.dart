/// Maps a saved-routine name to a leading glyph asset so the template list is
/// visually scannable instead of a column of identical dumbbells.
///
/// The icon set has no per-muscle glyphs, so pure strength splits
/// (push / pull / legs / upper / lower) share the dumbbell — but distinct
/// training *types* (cardio, conditioning, intervals, core, mobility, full
/// body, a challenge day) each get their own glyph. Pure and deterministic so
/// it is trivially unit-testable.
String templateGlyphAsset(String name) {
  final n = name.toLowerCase();
  // Match at a leading word boundary so short tokens don't fire mid-word
  // ("run" must not match "Crunch"/"Trunk"), while still allowing suffixes
  // ("interval" → "intervals", "run" → "running").
  bool has(List<String> keywords) =>
      keywords.any((k) => RegExp(r'\b' + RegExp.escape(k)).hasMatch(n));

  // Order matters: match the more specific training types before falling back
  // to the strength dumbbell.

  // Conditioning / cardio — energy.
  if (has([
    'hiit',
    'cardio',
    'conditioning',
    'sweat',
    'burn',
    'run',
    'sprint',
    'bike',
    'cycle',
    'cycling',
    'erg',
    'metcon',
    'sled',
    'assault',
  ])) {
    return 'assets/icons/ic_flame.svg';
  }

  // Timed / circuit formats — the clock.
  if (has([
    'circuit',
    'emom',
    'amrap',
    'tabata',
    'interval',
    'for time',
    'wod',
    'crossfit',
    'timed',
    'superset day',
  ])) {
    return 'assets/icons/ic_timer.svg';
  }

  // A benchmark / max-out day — the trophy.
  if (has([
    'challenge',
    'benchmark',
    'test day',
    '1rm',
    'max out',
    'maxout',
    'pr day',
    'pb day',
  ])) {
    return 'assets/icons/ic_trophy.svg';
  }

  // Core / midsection — a focused target.
  if (has(['core', 'abs', 'ab day', 'oblique', 'midsection', 'plank'])) {
    return 'assets/icons/ic_target.svg';
  }

  // Easy / restorative work — the heart.
  if (has([
    'mobility',
    'stretch',
    'yoga',
    'recovery',
    'cooldown',
    'cool down',
    'rehab',
    'zone 2',
    'zone2',
    'steady',
    'endurance',
  ])) {
    return 'assets/icons/ic_heart.svg';
  }

  // Whole-body sessions — the training figure.
  if (has(['full body', 'full-body', 'fullbody', 'total body', 'whole body'])) {
    return 'assets/icons/nav_train.svg';
  }

  // Strength splits and everything else.
  return 'assets/icons/ic_dumbbell.svg';
}
