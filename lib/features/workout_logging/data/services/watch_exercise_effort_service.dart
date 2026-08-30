import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../health_sync/data/sources/health_platform_source.dart';
import '../../../health_sync/domain/models/heart_rate_sample.dart';
import '../../domain/models/exercise_timeline_event.dart';
import '../../domain/models/workout_session.dart';
import '../../domain/repositories/workout_repository.dart';

class WatchExerciseEffortService {
  WatchExerciseEffortService({
    Future<List<HeartRateSample>> Function(DateTime start, DateTime end)?
    readHeartRateSamples,
  }) : _readHeartRateSamples =
           readHeartRateSamples ?? HealthPlatformSource().readHeartRateSamples;

  final Future<List<HeartRateSample>> Function(DateTime start, DateTime end)
  _readHeartRateSamples;

  static const int _bucketSeconds = 5;
  static const int _minEffortSeconds = 120; // 2 minutes

  Future<bool> computeAndPersist({
    required WorkoutSession session,
    required WorkoutRepository workoutRepository,
    int? ageYears,
  }) async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    final startMs = session.watchRecordingStartMs;
    final endMs = session.watchRecordingEndMs;
    if (startMs == null || endMs == null) return false;
    if (endMs <= startMs) return false;

    final start = DateTime.fromMillisecondsSinceEpoch(startMs);
    final end = DateTime.fromMillisecondsSinceEpoch(endMs);

    final samples = await _readHeartRateSamples(start, end);
    if (samples.isEmpty) return false;

    final buckets = _bucketize(samples, startMs: startMs, endMs: endMs);
    if (buckets.isEmpty) return false;

    final updated = _applyEffort(
      session,
      buckets: buckets,
      startMs: startMs,
      endMs: endMs,
      ageYears: ageYears,
    );
    if (updated == null) return false;
    if (updated == session) return false;

    // Ensure completed sessions get synced after metrics are computed.
    await workoutRepository.updateWorkoutSession(
      updated,
      markDirty: session.endTime != null || session.isCompleted,
    );
    return true;
  }

  List<_HrBucket> _bucketize(
    List<HeartRateSample> samples, {
    required int startMs,
    required int endMs,
  }) {
    final byBucket = <int, _HrBucketAcc>{};
    const bucketMs = _bucketSeconds * 1000;

    for (final s in samples) {
      final ms = s.time.millisecondsSinceEpoch;
      if (ms < startMs || ms >= endMs) continue;
      final bpm = s.bpm;
      if (!bpm.isFinite || bpm <= 0) continue;
      // Bucket timestamps are relative to the recording start to avoid dropping
      // valid initial samples when `startMs` isn't aligned to the bucket size.
      final bucketStart = startMs + ((ms - startMs) ~/ bucketMs) * bucketMs;
      final acc = byBucket.putIfAbsent(bucketStart, _HrBucketAcc.new);
      acc.sum += bpm;
      acc.count += 1;
    }

    final buckets = <_HrBucket>[];
    for (final entry in byBucket.entries) {
      final avg = entry.value.count == 0
          ? 0.0
          : entry.value.sum / entry.value.count;
      if (!avg.isFinite || avg <= 0) continue;
      buckets.add(_HrBucket(tsMs: entry.key, bpm: avg));
    }
    buckets.sort((a, b) => a.tsMs.compareTo(b.tsMs));
    return buckets;
  }

  WorkoutSession? _applyEffort(
    WorkoutSession session, {
    required List<_HrBucket> buckets,
    required int startMs,
    required int endMs,
    int? ageYears,
  }) {
    final hrMax = _estimateHrMax(ageYears);

    final timeline = _buildEffectiveTimeline(session);
    final activityEvents =
        timeline
            .where((e) => _isActivityEvent(e) && e.workoutExerciseId != null)
            .toList()
          ..sort((a, b) => a.tsMs.compareTo(b.tsMs));
    if (activityEvents.isEmpty) return null;

    final segments = _buildSegments(
      activityEvents,
      startMs: startMs,
      endMs: endMs,
    );
    if (segments.isEmpty) return null;

    final rests = _buildRestIntervals(timeline, startMs: startMs, endMs: endMs);

    final accByExercise = <String, _ExerciseAcc>{};

    int segIdx = 0;
    int restIdx = 0;

    for (final bucket in buckets) {
      final ts = bucket.tsMs;
      if (ts < startMs || ts >= endMs) continue;

      while (segIdx < segments.length && ts >= segments[segIdx].endMs) {
        segIdx += 1;
      }
      if (segIdx >= segments.length) break;
      if (ts < segments[segIdx].startMs) continue;

      while (restIdx < rests.length && ts >= rests[restIdx].endMs) {
        restIdx += 1;
      }
      if (restIdx < rests.length &&
          ts >= rests[restIdx].startMs &&
          ts < rests[restIdx].endMs) {
        continue;
      }

      final exerciseId = segments[segIdx].workoutExerciseId;
      if (exerciseId == null || exerciseId.isEmpty) continue;

      final acc = accByExercise.putIfAbsent(exerciseId, _ExerciseAcc.new);
      acc.sumBpm += bucket.bpm;
      acc.count += 1;
      if (bucket.bpm > acc.maxBpm) acc.maxBpm = bucket.bpm;

      final zone = _zoneFor(bpm: bucket.bpm, hrMax: hrMax);
      acc.zonesSec[zone] = (acc.zonesSec[zone] ?? 0) + _bucketSeconds;
      acc.totalSec += _bucketSeconds;
    }

    if (accByExercise.isEmpty) return null;

    var updatedAny = false;
    final updatedExercises = [
      for (final ex in session.exercises)
        () {
          final acc = accByExercise[ex.id];
          if (acc == null) return ex;
          final metrics = _metricsForExercise(
            acc,
            startMs: startMs,
            endMs: endMs,
          );
          updatedAny = true;
          return ex.copyWith(metrics: metrics);
        }(),
    ];

    if (!updatedAny) return null;
    return session.copyWith(exercises: updatedExercises);
  }

  List<ExerciseTimelineEvent> _buildEffectiveTimeline(WorkoutSession session) {
    final combined = <ExerciseTimelineEvent>[...session.timelineEvents];

    final derived = <ExerciseTimelineEvent>[];
    for (final ex in session.exercises) {
      for (final set in ex.sets) {
        final ts = set.completedAt?.millisecondsSinceEpoch;
        if (ts == null) continue;
        derived.add(
          ExerciseTimelineEvent(
            tsMs: ts,
            kind: ExerciseTimelineEventKind.setComplete,
            workoutExerciseId: ex.id,
          ),
        );
      }
    }
    if (derived.isNotEmpty) {
      final seen = <String>{};
      for (final e in combined) {
        seen.add('${e.kind.name}|${e.workoutExerciseId ?? ""}|${e.tsMs}');
      }
      for (final e in derived) {
        final key = '${e.kind.name}|${e.workoutExerciseId ?? ""}|${e.tsMs}';
        if (seen.add(key)) {
          combined.add(e);
        }
      }
    }

    combined.sort((a, b) => a.tsMs.compareTo(b.tsMs));
    return combined;
  }

  bool _isActivityEvent(ExerciseTimelineEvent e) {
    return e.kind == ExerciseTimelineEventKind.select ||
        e.kind == ExerciseTimelineEventKind.setComplete ||
        e.kind == ExerciseTimelineEventKind.watchNav;
  }

  List<_Interval> _buildSegments(
    List<ExerciseTimelineEvent> activityEvents, {
    required int startMs,
    required int endMs,
  }) {
    final segments = <_Interval>[];

    for (var i = 0; i < activityEvents.length; i++) {
      final current = activityEvents[i];
      final exerciseId = current.workoutExerciseId;
      if (exerciseId == null || exerciseId.isEmpty) continue;

      final segStart = math.max(current.tsMs, startMs);
      final nextTs = i + 1 < activityEvents.length
          ? activityEvents[i + 1].tsMs
          : endMs;
      final segEnd = math.min(nextTs, endMs);
      if (segEnd <= segStart) continue;
      segments.add(
        _Interval(
          startMs: segStart,
          endMs: segEnd,
          workoutExerciseId: exerciseId,
        ),
      );
    }
    return segments;
  }

  List<_Interval> _buildRestIntervals(
    List<ExerciseTimelineEvent> timeline, {
    required int startMs,
    required int endMs,
  }) {
    final events =
        timeline
            .where(
              (e) =>
                  e.kind == ExerciseTimelineEventKind.restStart ||
                  e.kind == ExerciseTimelineEventKind.restStop,
            )
            .toList()
          ..sort((a, b) => a.tsMs.compareTo(b.tsMs));

    final intervals = <_Interval>[];
    int? openStart;

    for (final e in events) {
      if (e.tsMs < startMs || e.tsMs > endMs) continue;
      if (e.kind == ExerciseTimelineEventKind.restStart) {
        if (openStart != null) {
          // Close an unclosed rest window at the new start to keep intervals sane.
          final s = math.max(openStart, startMs);
          final t = math.min(e.tsMs, endMs);
          if (t > s) intervals.add(_Interval(startMs: s, endMs: t));
        }
        openStart = e.tsMs;
        continue;
      }

      if (e.kind == ExerciseTimelineEventKind.restStop && openStart != null) {
        final s = math.max(openStart, startMs);
        final t = math.min(e.tsMs, endMs);
        if (t > s) intervals.add(_Interval(startMs: s, endMs: t));
        openStart = null;
      }
    }

    if (openStart != null) {
      final s = math.max(openStart, startMs);
      final t = endMs;
      if (t > s) intervals.add(_Interval(startMs: s, endMs: t));
    }

    intervals.sort((a, b) => a.startMs.compareTo(b.startMs));
    return intervals;
  }

  double _estimateHrMax(int? ageYears) {
    if (ageYears == null) return 190.0;
    final age = ageYears.clamp(10, 100);
    return 208.0 - 0.7 * age;
  }

  String _zoneFor({required double bpm, required double hrMax}) {
    final ratio = hrMax <= 0 ? 0.0 : bpm / hrMax;
    if (ratio < 0.60) return 'z1';
    if (ratio < 0.70) return 'z2';
    if (ratio < 0.80) return 'z3';
    if (ratio < 0.90) return 'z4';
    return 'z5';
  }

  Map<String, dynamic> _metricsForExercise(
    _ExerciseAcc acc, {
    required int startMs,
    required int endMs,
  }) {
    final avg = acc.count == 0 ? 0.0 : acc.sumBpm / acc.count;
    final zones = <String, int>{
      'z1': acc.zonesSec['z1'] ?? 0,
      'z2': acc.zonesSec['z2'] ?? 0,
      'z3': acc.zonesSec['z3'] ?? 0,
      'z4': acc.zonesSec['z4'] ?? 0,
      'z5': acc.zonesSec['z5'] ?? 0,
    };

    final effort = _effortScore(zonesSec: zones, totalSec: acc.totalSec);

    return {
      'hr': {
        'source': 'healthkit',
        'recordingStartMs': startMs,
        'recordingEndMs': endMs,
        'avgBpm': avg,
        'maxBpm': acc.maxBpm.isFinite ? acc.maxBpm : 0.0,
        'zonesSec': zones,
      },
      'effort': {'method': 'zones_v1', if (effort != null) 'hr1to10': effort},
    };
  }

  int? _effortScore({
    required Map<String, int> zonesSec,
    required int totalSec,
  }) {
    if (totalSec < _minEffortSeconds) return null;
    final z2 = (zonesSec['z2'] ?? 0) / 60.0;
    final z3 = (zonesSec['z3'] ?? 0) / 60.0;
    final z4 = (zonesSec['z4'] ?? 0) / 60.0;
    final z5 = (zonesSec['z5'] ?? 0) / 60.0;
    final points = 0.5 * z2 + 1.0 * z3 + 1.5 * z4 + 2.0 * z5;
    final score = 1 + (points / 3.0).round();
    return score.clamp(1, 10);
  }
}

class _HrBucket {
  const _HrBucket({required this.tsMs, required this.bpm});
  final int tsMs;
  final double bpm;
}

class _HrBucketAcc {
  double sum = 0.0;
  int count = 0;
}

class _ExerciseAcc {
  double sumBpm = 0.0;
  int count = 0;
  double maxBpm = 0.0;
  int totalSec = 0;
  final Map<String, int> zonesSec = <String, int>{};
}

class _Interval {
  const _Interval({
    required this.startMs,
    required this.endMs,
    this.workoutExerciseId,
  });
  final int startMs;
  final int endMs;
  final String? workoutExerciseId;
}
