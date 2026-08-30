import 'package:flutter/widgets.dart';

import '../../domain/models/workout_exercise.dart';
import '../../domain/models/workout_session.dart';
import '../../domain/models/workout_set.dart';
import '../../../exercise_library/domain/models/exercise.dart';

class WorkoutServerMapper {
  const WorkoutServerMapper._();

  static WorkoutSession sessionFromServerMap(Map<String, dynamic> map) {
    final idVal = map['id'];
    if (idVal is! String || idVal.isEmpty) {
      throw const FormatException('workout.id missing or invalid');
    }

    final name = (map['name'] as String?) ?? 'Workout';

    final startRaw = map['start_time'];
    if (startRaw is! String || startRaw.isEmpty) {
      throw const FormatException('workout.start_time missing or invalid');
    }
    final start = DateTime.parse(startRaw).toLocal();

    DateTime? end;
    final endRaw = map['end_time'];
    if (endRaw is String && endRaw.isNotEmpty) {
      end = DateTime.tryParse(endRaw)?.toLocal();
    }

    final exercises = (map['exercises'] is List)
        ? (map['exercises'] as List)
              .whereType<Map>()
              .map((m) => exerciseFromServerMap(Map<String, dynamic>.from(m)))
              .toList(growable: false)
        : const <WorkoutExercise>[];

    final statusStr =
        (map['status'] as String?) ?? (end != null ? 'completed' : 'active');
    final isCompleted = statusStr == 'completed';

    return WorkoutSession(
      id: idVal,
      name: name,
      startTime: start,
      endTime: end,
      exercises: exercises,
      notes: map['notes'] as String?,
      isCompleted: isCompleted,
      lastUpdatedAt: DateTime.now(),
      dirty: false,
    );
  }

  static WorkoutExercise exerciseFromServerMap(Map<String, dynamic> map) {
    final exerciseName = (map['exercise_name'] as String?) ?? 'Unknown';
    final kind = _parseKind(map['exercise_kind']);
    final rawSets = (map['sets'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);

    final loggingMode = inferLoggingMode(kind, rawSets);
    final sets = rawSets
        .map((m) => setFromServerMap(m, loggingMode: loggingMode))
        .toList(growable: false);

    final primaryMuscles = _extractMuscles(map['primary_muscles']);
    final secondaryMuscles = _extractMuscles(map['secondary_muscles']);
    final combinedMuscles = _normalizeMuscleList([
      ...primaryMuscles,
      ...secondaryMuscles,
    ]);

    final slugRaw = map['exercise_slug'] ?? map['slug'];
    final slug = (slugRaw is String && slugRaw.trim().isNotEmpty)
        ? slugRaw.trim()
        : null;

    final ex = Exercise(
      name: exerciseName,
      muscles: combinedMuscles,
      slug: slug,
      kind: kind,
      loggingMode: loggingMode,
    );

    return WorkoutExercise(
      id: (map['id'] as String?) ?? UniqueKey().toString(),
      exercise: ex,
      sets: sets,
      notes: map['notes'] as String?,
      restTimerSeconds: (map['rest_time'] as num?)?.toInt(),
      metrics: map['metrics'] is Map
          ? Map<String, dynamic>.from(map['metrics'])
          : null,
      // Missing on read -> null (legacy flat behavior).
      supersetGroupId: map['superset_group_id'] as String?,
      supersetOrder: (map['superset_order'] as num?)?.toInt(),
    );
  }

  static WorkoutSet setFromServerMap(
    Map<String, dynamic> map, {
    ExerciseLoggingMode? loggingMode,
  }) {
    final setType = WorkoutSet.parseSetType(map['set_type']);

    final weight = (map['weight'] as num?)?.toDouble();
    final reps = (map['reps'] as num?)?.toInt();
    final duration = (map['duration'] as num?)?.toInt();
    final distance = (map['distance'] as num?)?.toDouble();

    bool hasNonZeroNum(num? v) => v != null && v != 0;

    final resolvedWeight = switch (loggingMode) {
      // For cardio history, newer server payloads use the dedicated `distance`
      // column (METRES per the backend/MCP contract) — convert to the app's km
      // model. Older synced workouts omitted the cardio columns and stored the
      // km distance in `weight`, so fall back to `weight` (already km) when the
      // distance column is absent/zero.
      ExerciseLoggingMode.distanceDuration =>
        hasNonZeroNum(distance) ? ((distance ?? 0.0) / 1000.0) : (weight ?? 0.0),
      ExerciseLoggingMode.durationOnly => 0.0,
      _ => weight ?? 0.0,
    };

    final resolvedReps = switch (loggingMode) {
      ExerciseLoggingMode.distanceDuration =>
        hasNonZeroNum(duration) ? (duration ?? 0) : (reps ?? 0),
      ExerciseLoggingMode.durationOnly =>
        hasNonZeroNum(duration) ? (duration ?? 0) : (reps ?? 0),
      _ => reps ?? 0,
    };

    return WorkoutSet(
      id: map['id'] as String,
      weight: resolvedWeight,
      reps: resolvedReps,
      rpe: (map['rpe'] as num?)?.toInt(),
      setType: setType,
      isCompleted: (map['is_completed'] as bool?) ?? false,
      // Dropset linkage; missing on read -> null (legacy/standalone set).
      parentSetId: map['parent_set_id'] as String?,
      dropIndex: (map['drop_index'] as num?)?.toInt(),
    );
  }

  /// Infer the logging mode from a server exercise's kind and its raw set maps.
  /// Prefers explicit `distance`/`duration` columns, then falls back to the
  /// legacy convention where cardio folded distance->weight and duration->reps.
  /// Shared with [WorkoutSyncService] so the sync-pull and history paths resolve
  /// cardio/timed sets identically.
  static ExerciseLoggingMode inferLoggingMode(
    ExerciseKind kind,
    List<Map<String, dynamic>> sets,
  ) {
    // A *present* distance column (even 0) means the set was logged as
    // distance+duration. Presence — not non-zero — is the signal: distance
    // writers set the column, while duration-only holds (e.g. Plank) never write
    // `distance` at all. This keeps a zero-distance cardio set (a treadmill
    // logged with time but no distance) classified as distance+duration instead
    // of collapsing to duration-only after sync import.
    for (final set in sets) {
      if (set['distance'] is num) {
        return ExerciseLoggingMode.distanceDuration;
      }
    }
    for (final set in sets) {
      final duration = set['duration'];
      if (duration is num && duration != 0) {
        return ExerciseLoggingMode.durationOnly;
      }
    }

    if (kind != ExerciseKind.cardio) {
      return ExerciseLoggingMode.weightReps;
    }

    // Back-compat: cardio workouts synced from the Flutter app historically
    // stored `distance` in `weight` and `duration` in `reps`.
    for (final set in sets) {
      final weight = set['weight'];
      if (weight is num && weight != 0) {
        return ExerciseLoggingMode.distanceDuration;
      }
    }
    for (final set in sets) {
      final reps = set['reps'];
      if (reps is num && reps != 0) {
        return ExerciseLoggingMode.durationOnly;
      }
    }

    return ExerciseLoggingMode.distanceDuration;
  }

  static ExerciseKind _parseKind(dynamic rawKind) {
    if (rawKind is String) {
      switch (rawKind.trim().toLowerCase()) {
        case 'cardio':
          return ExerciseKind.cardio;
        case 'assisted':
          return ExerciseKind.assisted;
        default:
          return ExerciseKind.strength;
      }
    }
    if (rawKind is int &&
        rawKind >= 0 &&
        rawKind < ExerciseKind.values.length) {
      return ExerciseKind.values[rawKind];
    }
    return ExerciseKind.strength;
  }

  static List<String> _extractMuscles(dynamic raw) {
    if (raw is List) {
      final list = raw
          .map((v) => v?.toString() ?? '')
          .where((s) => s.isNotEmpty);
      return _normalizeMuscleList(list);
    }
    return const <String>[];
  }

  static List<String> _normalizeMuscleList(Iterable<String> muscles) {
    final seen = <String>{};
    final result = <String>[];
    for (final m in muscles) {
      final trimmed = m.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (!seen.add(key)) continue;
      result.add(trimmed);
    }
    return result;
  }
}
