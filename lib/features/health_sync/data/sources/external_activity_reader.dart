import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:health/health.dart';

import '../../domain/models/external_activity.dart';
import '../writeback/hustl_workout_authorship.dart';

/// Reads external (platform-recorded) workout sessions from Apple Health /
/// Health Connect for a given time range and maps them to [ExternalActivity].
///
/// It fetches `HealthDataType.WORKOUT` points and projects them. Hustl's own
/// writeback echoes are dropped here using the shared [isLikelyHustlWorkout]
/// predicate — this is the read path's use of that extraction, and it is done
/// here (not in the filter) because it depends on point metadata that
/// [ExternalActivity] intentionally does not carry. The reader does NOT dedupe
/// across apps or attribute strain — those are the filter's and attribution
/// service's jobs. Keeping it free of "today" assumptions lets the future
/// 90-day drill-down reuse it unchanged.
///
/// It wraps the `health` plugin directly (like the duplicate-cleanup service)
/// rather than [HealthPlatformSource] so it can silently probe the WORKOUT read
/// scope and be unit-tested with a mock [Health] without touching that source.
class ExternalActivityReader {
  ExternalActivityReader({Health? health}) : _health = health ?? Health();

  final Health _health;

  /// How far before the requested window the platform query starts. HealthKit's
  /// sample predicate matches on start date, so a workout that starts before
  /// the window but ends inside it (e.g. 23:30 -> 00:30 crossing midnight)
  /// would be missed by an exact-window query. Padding the query start by the
  /// maximum supported workout length (24 h) and then filtering by actual
  /// overlap in Dart makes the `[start, end)` overlap contract self-enforcing
  /// regardless of the plugin's predicate semantics.
  static const Duration maxWorkoutLookback = Duration(hours: 24);

  /// Fetch and map external workouts overlapping the `[start, end)` window.
  ///
  /// "Overlapping" is enforced in Dart (`activity.end > start &&
  /// activity.start < end`) over a query padded by [maxWorkoutLookback], so
  /// workouts that start before the window but end inside it are included.
  ///
  /// SILENT by design: this read path NEVER calls `requestAuthorization`, so a
  /// passive surface (the dashboard) can never pop an unprompted OS permission
  /// dialog. Granting WORKOUT read access remains the job of the existing
  /// health-connect consent flow. The `hasPermissions` probe drives a
  /// cross-platform matrix:
  ///
  /// - `true` → proceed with the read.
  /// - `false` → skip; empty externals (Android Health Connect gives real
  ///   read-permission answers).
  /// - `null` → PROCEED with the silent query. iOS/HealthKit hides read grants
  ///   by design, so the probe is *always* undetermined there; an unauthorized
  ///   HealthKit read does not prompt and simply returns no data. The query
  ///   stays inside the try/catch below, so a platform that throws instead
  ///   (e.g. a Health Connect SecurityException) still resolves to empty.
  /// - probe throws → skip; empty externals.
  ///
  /// Returns an empty list on web, when permissions are known-absent, or when
  /// the platform read throws — reads are best-effort and never fatal to the
  /// caller. Points with an empty platform UUID are dropped (they cannot be
  /// excluded or attributed reliably).
  Future<List<ExternalActivity>> readActivities({
    required DateTime start,
    required DateTime end,
  }) async {
    if (kIsWeb) return const [];

    try {
      await _health.configure();
    } catch (_) {
      // Configure failures are non-fatal; the plugin can still work.
    }

    bool? granted;
    try {
      granted = await _health.hasPermissions(
        const [HealthDataType.WORKOUT],
        permissions: const [HealthDataAccess.READ],
      );
    } catch (_) {
      // Probe failure → skip. Never fall through to a query we can't vouch is
      // prompt-free.
      return const [];
    }
    // Only an explicit false skips: null is iOS's by-design "read grants are
    // hidden" answer, and the silent query below is prompt-free and empty when
    // unauthorized.
    if (granted == false) return const [];

    List<HealthDataPoint> points = const [];
    try {
      points = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.WORKOUT],
        startTime: start.subtract(maxWorkoutLookback),
        endTime: end,
      );
    } catch (_) {
      return const [];
    }

    final activities = <ExternalActivity>[];
    for (final point in points) {
      if (point.type != HealthDataType.WORKOUT) continue;
      if (point.uuid.isEmpty) continue;
      // Drop Hustl's own writeback echoes at the source, using metadata that
      // ExternalActivity does not preserve.
      if (isLikelyHustlWorkout(point)) continue;
      final activity = mapWorkoutPoint(point);
      // Enforce the [start, end) overlap contract in Dart: the padded query
      // may return workouts entirely before the window.
      if (!activity.end.isAfter(start) || !activity.start.isBefore(end)) {
        continue;
      }
      activities.add(activity);
    }
    return activities;
  }

  /// Maps a single platform WORKOUT [point] to an [ExternalActivity]. Exposed
  /// for testing the projection independently of the platform read.
  static ExternalActivity mapWorkoutPoint(HealthDataPoint point) {
    final value = point.value;
    final workout = value is WorkoutHealthValue ? value : null;

    final rawType =
        workout?.workoutActivityType.name ?? point.workoutSummary?.workoutType;

    final energyKcal = _positiveOrNull(
      workout?.totalEnergyBurned ?? point.workoutSummary?.totalEnergyBurned,
    );
    final distanceMeters = _positiveOrNull(
      workout?.totalDistance ?? point.workoutSummary?.totalDistance,
    );

    final kind = externalActivityKindFromPlatform(rawType);
    // Preserve the platform's real activity name for EVERY recognized type
    // (Tennis, Pilates, Running, …), not just the `other` bucket, so the
    // receipt names what the user actually did rather than the coarse kind.
    // Null only for the platform catch-all (OTHER/UNKNOWN) -> "Workout".
    final activityName = prettyExternalActivityName(rawType);

    return ExternalActivity(
      platformUuid: point.uuid,
      sourceName: point.sourceName,
      kind: kind,
      start: point.dateFrom,
      end: point.dateTo,
      distanceMeters: distanceMeters,
      activeEnergyKcal: energyKcal,
      activityName: activityName,
    );
  }

  static double? _positiveOrNull(num? value) {
    if (value == null) return null;
    final asDouble = value.toDouble();
    if (!asDouble.isFinite || asDouble <= 0) return null;
    return asDouble;
  }
}
