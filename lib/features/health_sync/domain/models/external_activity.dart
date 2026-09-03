import 'package:equatable/equatable.dart';

/// A coarse classification of an external (non-Hustl) workout session, mapped
/// from the platform's activity type. Deliberately small: the receipt only
/// needs enough to name what drove today's strain, not the full taxonomy.
///
/// Any platform activity type we do not explicitly recognize maps to [other];
/// the raw platform label is preserved through [ExternalActivity.sourceName]
/// context rather than exploding this enum.
enum ExternalActivityKind {
  run,
  ride,
  swim,
  walk,
  hike,
  strengthTraining,
  hiit,
  yoga,
  other,
}

/// A single external workout session read from Apple Health / Health Connect.
///
/// This is a read-only projection of a platform `WORKOUT` point: it never
/// carries Hustl-authored sessions (those are filtered out upstream) and it is
/// intentionally free of any "today" assumptions so the same shape can back the
/// future 90-day historical drill-down.
class ExternalActivity extends Equatable {
  const ExternalActivity({
    required this.platformUuid,
    required this.sourceName,
    required this.kind,
    required this.start,
    required this.end,
    this.distanceMeters,
    this.activeEnergyKcal,
    this.averageHeartRateBpm,
    this.activityName,
  });

  /// The platform's stable identifier for this workout (HealthKit UUID /
  /// Health Connect record id). Used to exclude Hustl's own writeback echoes
  /// via the writeback mappings.
  final String platformUuid;

  /// The human-facing source of the workout (Apple Health source name on iOS;
  /// the originating app's package name on Android/Health Connect).
  final String sourceName;

  /// The coarse activity classification (see [ExternalActivityKind]).
  final ExternalActivityKind kind;

  final DateTime start;
  final DateTime end;

  /// Total distance in meters, when the source recorded it.
  final double? distanceMeters;

  /// Active energy in kilocalories, when the source recorded it. May be null
  /// (many strength/yoga sessions omit calories); attribution falls back to a
  /// duration-based estimate when this is absent.
  final double? activeEnergyKcal;

  /// Average heart rate in BPM, when available. The platform WORKOUT point does
  /// not expose this in v1, so it is currently always null; kept on the model
  /// so an HR-weighted refinement can populate it without a schema change.
  final double? averageHeartRateBpm;

  /// Human-readable platform activity name (e.g. `Soccer`, `Tennis`, `Pilates`)
  /// for ANY recognized platform workout type — the receipt shows this in place
  /// of the coarse [kind] label so it names the real activity the user did.
  /// Null only for the platform's catch-all types (`OTHER`/`UNKNOWN`) or an
  /// empty type, where the receipt falls back to the generic "Workout" label.
  final String? activityName;

  /// Wall-clock duration of the session.
  Duration get duration => end.difference(start);

  double get durationMinutes => duration.inMilliseconds / 60000.0;

  @override
  List<Object?> get props => [
    platformUuid,
    sourceName,
    kind,
    start,
    end,
    distanceMeters,
    activeEnergyKcal,
    averageHeartRateBpm,
    activityName,
  ];
}

final RegExp _activityTokenPattern = RegExp(r'[^a-z0-9]');

/// Collapses a raw platform activity type OR a prettified activity name into a
/// single lowercase-alphanumeric key, so `TRADITIONAL_STRENGTH_TRAINING`,
/// `traditionalStrengthTraining`, and `Traditional strength training` all yield
/// `traditionalstrengthtraining`. Shared by the kind mapper, the pretty-namer,
/// and the receipt's glyph lookup so their normalization can never drift apart.
String normalizeActivityToken(String raw) =>
    raw.toLowerCase().replaceAll(_activityTokenPattern, '');

/// Maps a platform `workoutActivityType.name` (e.g. `RUNNING`,
/// `TRADITIONAL_STRENGTH_TRAINING`, `HIGH_INTENSITY_INTERVAL_TRAINING`) to an
/// [ExternalActivityKind]. Matching is case-insensitive and tolerant of the
/// underscore/camelCase variants the health plugin can emit across platforms.
///
/// Unrecognized or empty labels map to [ExternalActivityKind.other].
ExternalActivityKind externalActivityKindFromPlatform(String? rawActivityType) {
  final raw = rawActivityType?.trim();
  if (raw == null || raw.isEmpty) return ExternalActivityKind.other;

  // Normalize `TRADITIONAL_STRENGTH_TRAINING`, `traditionalStrengthTraining`,
  // and similar into a single lowercase alphanumeric token.
  final token = normalizeActivityToken(raw);

  // Order matters: check the more specific tokens (HIIT, treadmill running)
  // before broader substrings.
  if (token.contains('highintensityinterval') || token == 'hiit') {
    return ExternalActivityKind.hiit;
  }
  if (token.contains('strengthtraining') ||
      token == 'strengthtraining' ||
      token.contains('weightlifting') ||
      token.contains('coretraining')) {
    return ExternalActivityKind.strengthTraining;
  }
  if (token.contains('yoga') ||
      token.contains('pilates') ||
      token.contains('mindandbody') ||
      token.contains('flexibility')) {
    return ExternalActivityKind.yoga;
  }
  if (token.contains('hiking')) return ExternalActivityKind.hike;
  if (token.contains('swimming')) return ExternalActivityKind.swim;
  if (token.contains('running') ||
      token == 'run' ||
      token.contains('wheelchairrun')) {
    return ExternalActivityKind.run;
  }
  if (token.contains('walking') ||
      token == 'walk' ||
      token.contains('wheelchairwalk')) {
    return ExternalActivityKind.walk;
  }
  if (token.contains('biking') ||
      token.contains('cycling') ||
      token.contains('bike')) {
    return ExternalActivityKind.ride;
  }
  return ExternalActivityKind.other;
}

/// Short, friendly display names for the handful of platform activity types
/// whose sentence-cased raw name is too long or reads awkwardly for a compact
/// receipt row. Keyed by the normalized (lowercase-alphanumeric) token. Every
/// other type keeps its own prettified name — this map exists ONLY to shorten
/// the clunky few, not to re-flatten the taxonomy.
const Map<String, String> _activityNameShortForms = {
  // "Strength training" / "Traditional strength training" -> "Strength".
  'strengthtraining': 'Strength',
  'traditionalstrengthtraining': 'Strength',
  'functionalstrengthtraining': 'Strength',
  // "High intensity interval training" -> "HIIT".
  'highintensityintervaltraining': 'HIIT',
  // Awkward "<x> treadmill/machine/pace/stationary" word order -> natural form.
  'runningtreadmill': 'Treadmill run',
  'walkingtreadmill': 'Treadmill walk',
  'stairclimbingmachine': 'Stair climbing',
  'bikingstationary': 'Stationary bike',
  'wheelchairrunpace': 'Wheelchair run',
  'wheelchairwalkpace': 'Wheelchair walk',
};

/// Prettifies a raw platform `workoutActivityType.name` (e.g. `SOCCER`,
/// `TENNIS`, `PILATES`, `AMERICAN_FOOTBALL`) into a friendly display name
/// (`Soccer`, `Tennis`, `Pilates`, `American football`).
///
/// The receipt shows the platform's OWN activity name for every workout — so a
/// tennis session reads "Tennis" and Pilates reads "Pilates" rather than being
/// re-flattened to the coarse [ExternalActivityKind] label. A small
/// [_activityNameShortForms] map only shortens the few names that are otherwise
/// too long/awkward for a row (e.g. HIIT, Strength). Returns null when the raw
/// type is empty or is the platform's catch-all (`OTHER`/`UNKNOWN`) — callers
/// fall back to the generic kind label ("Workout") in that case.
String? prettyExternalActivityName(String? rawActivityType) {
  final raw = rawActivityType?.trim();
  if (raw == null || raw.isEmpty) return null;

  // Reuse the mapper's normalization: if the type reduces to nothing, or to the
  // platform's catch-all, there is no real name to show.
  final token = normalizeActivityToken(raw);
  if (token.isEmpty || token == 'other' || token == 'unknown') return null;

  // A curated short form wins over the raw prettified name.
  final shortForm = _activityNameShortForms[token];
  if (shortForm != null) return shortForm;

  // Split on separators AND camelCase boundaries, lowercase each word, then
  // capitalize only the first letter (sentence case, per UI microcopy rules).
  final spaced = raw
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}');
  final words = spaced
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w.toLowerCase())
      .toList();
  if (words.isEmpty) return null;
  final joined = words.join(' ');
  return joined[0].toUpperCase() + joined.substring(1);
}
