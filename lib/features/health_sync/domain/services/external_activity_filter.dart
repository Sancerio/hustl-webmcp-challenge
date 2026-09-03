import '../../../workout_logging/domain/models/workout_session.dart';
import '../models/external_activity.dart';

/// Pure filter that reduces raw external workout reads down to the set of
/// genuinely-external, non-duplicated sessions worth attributing strain to.
///
/// Rules are applied in order; each stage only removes records, never adds or
/// mutates them:
///
/// 1. **Hustl echoes** — drop any activity whose platform UUID is a known
///    Hustl writeback UUID, or whose source name mentions "hustl". (The
///    metadata-based half of Hustl-authorship detection runs earlier, in the
///    reader, where the raw point metadata is still available; this stage is
///    the [ExternalActivity]-visible defense plus the writeback-UUID exclusion.)
/// 2. **Watch overlap** — drop any activity that overlaps a Hustl watch-recorded
///    session by more than 50% of the shorter interval. A Hustl session counts
///    as watch-recorded when `capturedOnWatch` is true or it has a
///    `watchWorkoutUuid`. This prevents double-counting a session the watch
///    already recorded and that surfaces again as an external workout.
/// 3. **Cross-app duplicates** — cluster the survivors by kind where they
///    overlap by more than 50%, and keep only the richest record in each
///    cluster (most of energy/distance/HR populated), tie-broken by the
///    alphabetically-earliest source name. This collapses the same run logged
///    by two apps (e.g. Strava and Apple Fitness) into one.
///
/// The filter is free of "today" assumptions so the future 90-day drill-down
/// can reuse it unchanged.
class ExternalActivityFilter {
  const ExternalActivityFilter();

  /// Minimum overlap (as a fraction of the shorter interval) for two sessions
  /// to be treated as the same physical activity.
  static const double _overlapThreshold = 0.5;

  List<ExternalActivity> filter({
    required List<ExternalActivity> activities,
    required Set<String> hustlWritebackUuids,
    required List<WorkoutSession> hustlSessions,
  }) {
    // Stage 1: Hustl echoes.
    final afterAuthorship = activities.where((a) {
      if (hustlWritebackUuids.contains(a.platformUuid)) return false;
      if (a.sourceName.toLowerCase().contains('hustl')) return false;
      return true;
    }).toList();

    // Stage 2: watch-recorded overlap.
    final watchSessions = hustlSessions
        .where((s) => s.capturedOnWatch || (s.watchWorkoutUuid != null))
        .toList();
    final afterWatch = afterAuthorship.where((a) {
      for (final session in watchSessions) {
        final sessionEnd = session.endTime;
        if (sessionEnd == null) continue;
        if (_overlapFraction(
              a.start,
              a.end,
              session.startTime,
              sessionEnd,
            ) >
            _overlapThreshold) {
          return false;
        }
      }
      return true;
    }).toList();

    // Stage 3: cross-app same-kind duplicate clusters.
    return _dedupeCrossApp(afterWatch);
  }

  /// Fraction of the *shorter* of the two intervals that overlaps the other.
  ///
  /// Zero-length intervals are handled BEFORE any early return: a zero-length
  /// interval whose instant lies within the other interval (inclusive bounds)
  /// counts as fully overlapping (1.0); outside it, 0. Malformed intervals
  /// (end before start — defensive against bad platform data) are normalized
  /// to zero-length at their start and take the same instant semantics.
  static double _overlapFraction(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) {
    // Normalize malformed intervals (end < start) to zero-length at start.
    final aEndN = aEnd.isBefore(aStart) ? aStart : aEnd;
    final bEndN = bEnd.isBefore(bStart) ? bStart : bEnd;

    final aMs = aEndN.difference(aStart).inMilliseconds;
    final bMs = bEndN.difference(bStart).inMilliseconds;

    // Zero-length interval: fully overlapping iff its instant lies within the
    // other (normalized) interval, inclusive of both bounds.
    if (aMs == 0 || bMs == 0) {
      final instant = aMs == 0 ? aStart : bStart;
      final otherStart = aMs == 0 ? bStart : aStart;
      final otherEnd = aMs == 0 ? bEndN : aEndN;
      final inside =
          !instant.isBefore(otherStart) && !instant.isAfter(otherEnd);
      return inside ? 1.0 : 0.0;
    }

    final overlapStart = aStart.isAfter(bStart) ? aStart : bStart;
    final overlapEnd = aEndN.isBefore(bEndN) ? aEndN : bEndN;
    final overlapMs = overlapEnd.difference(overlapStart).inMilliseconds;
    if (overlapMs <= 0) return 0;

    final shorterMs = aMs < bMs ? aMs : bMs;
    return overlapMs / shorterMs;
  }

  List<ExternalActivity> _dedupeCrossApp(List<ExternalActivity> activities) {
    if (activities.length <= 1) return List.of(activities);

    // Preserve input order for stable output; cluster greedily.
    final clusters = <List<ExternalActivity>>[];
    for (final activity in activities) {
      List<ExternalActivity>? target;
      for (final cluster in clusters) {
        final joins = cluster.any(
          (member) =>
              member.kind == activity.kind &&
              _overlapFraction(
                    activity.start,
                    activity.end,
                    member.start,
                    member.end,
                  ) >
                  _overlapThreshold,
        );
        if (joins) {
          target = cluster;
          break;
        }
      }
      if (target == null) {
        clusters.add([activity]);
      } else {
        target.add(activity);
      }
    }

    final kept = <ExternalActivity>{};
    for (final cluster in clusters) {
      kept.add(cluster.length == 1 ? cluster.first : _richest(cluster));
    }

    // Emit survivors in original input order.
    return activities.where(kept.contains).toList();
  }

  /// Keep the record with the most populated of (energy, distance, HR). Ties
  /// break on the alphabetically-earliest source name, then earliest start,
  /// then platform UUID for full determinism.
  static ExternalActivity _richest(List<ExternalActivity> cluster) {
    ExternalActivity best = cluster.first;
    for (final candidate in cluster.skip(1)) {
      if (_isRicher(candidate, best)) best = candidate;
    }
    return best;
  }

  static bool _isRicher(ExternalActivity a, ExternalActivity b) {
    final ap = _populatedCount(a);
    final bp = _populatedCount(b);
    if (ap != bp) return ap > bp;

    final byName = a.sourceName.toLowerCase().compareTo(
      b.sourceName.toLowerCase(),
    );
    if (byName != 0) return byName < 0;

    if (!a.start.isAtSameMomentAs(b.start)) return a.start.isBefore(b.start);

    return a.platformUuid.compareTo(b.platformUuid) < 0;
  }

  static int _populatedCount(ExternalActivity a) {
    var count = 0;
    if (a.activeEnergyKcal != null) count++;
    if (a.distanceMeters != null) count++;
    if (a.averageHeartRateBpm != null) count++;
    return count;
  }
}
