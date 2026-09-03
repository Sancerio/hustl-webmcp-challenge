import '../../core/webmcp/workout_history_web_mcp_service.dart';
import '../../features/exercise_library/domain/models/exercise.dart';
import '../../features/workout_logging/domain/models/workout_exercise.dart';
import '../../features/workout_logging/domain/models/workout_session.dart';
import '../../features/workout_logging/domain/models/workout_set.dart';
import '../../features/workout_logging/domain/repositories/workout_repository.dart';

/// Bounded, repository-backed WebMCP history for the credential-free demo.
///
/// This adapter deliberately emits the same compact contract as the backend
/// reader without constructing token storage or a network client. Raw sets,
/// notes, account identifiers, and exercise row identifiers never leave the
/// in-memory repository.
class DemoWorkoutHistoryWebMcpService implements WorkoutHistoryWebMcpReader {
  const DemoWorkoutHistoryWebMcpService({
    required WorkoutRepository repository,
    required DateTime anchor,
  }) : _repository = repository,
       _anchor = anchor;

  final WorkoutRepository _repository;
  final DateTime _anchor;

  @override
  Future<Map<String, Object?>> loadWorkoutHistory({
    required int limit,
    String? cursor,
  }) async {
    final boundedLimit = limit.clamp(1, 20).toInt();
    final offset = _cursorOffset(cursor);
    final sessions = (await _repository.getWorkoutSessions())
        .where((session) => session.isCompleted)
        .toList(growable: false);
    final page = sessions
        .skip(offset)
        .take(boundedLimit)
        .toList(growable: false);
    final nextOffset = offset + page.length;
    final hasMore = nextOffset < sessions.length;

    return {
      'status': 'ready',
      'workoutCount': page.length,
      'hasMore': hasMore,
      'nextCursor': hasMore ? 'demo:$nextOffset' : null,
      'workouts': page.map(_workoutSummaryJson).toList(growable: false),
    };
  }

  @override
  Future<Map<String, Object?>> loadExerciseHistory({
    required int limit,
    required int sinceDays,
  }) async {
    final boundedLimit = limit.clamp(1, 20).toInt();
    final boundedDays = sinceDays.clamp(1, 3650).toInt();
    final since = DateTime(
      _anchor.year,
      _anchor.month,
      _anchor.day,
    ).subtract(Duration(days: boundedDays - 1));
    final sessions = (await _repository.getWorkoutSessions())
        .where(
          (session) =>
              session.isCompleted && !session.startTime.isBefore(since),
        )
        .toList(growable: false);
    final aggregates = <String, _ExerciseAggregate>{};
    for (final session in sessions) {
      for (final exercise in session.exercises) {
        final key = exercise.exercise.canonicalKey;
        if (key == null) continue;
        aggregates
            .putIfAbsent(
              key,
              () => _ExerciseAggregate(exercise: exercise.exercise),
            )
            .add(exercise, session);
      }
    }
    final sorted = aggregates.values.toList(growable: false)
      ..sort((left, right) {
        final frequency = right.frequency.compareTo(left.frequency);
        if (frequency != 0) return frequency;
        final recency = right.lastUsedAt.compareTo(left.lastUsedAt);
        if (recency != 0) return recency;
        return left.exercise.name.compareTo(right.exercise.name);
      });
    final items = sorted
        .take(boundedLimit)
        .map((aggregate) => aggregate.toJson())
        .toList(growable: false);

    return {
      'status': 'ready',
      'range': {'sinceDays': boundedDays, 'since': _date(since)},
      'exerciseCount': items.length,
      'exercises': items,
    };
  }

  static Map<String, Object?> _workoutSummaryJson(WorkoutSession session) => {
    'id': _bounded(session.id, 128),
    'name': _bounded(session.name, 120),
    'startAt': session.startTime.toUtc().toIso8601String(),
    'endAt': session.endTime?.toUtc().toIso8601String(),
    'durationSeconds': session.endTime?.difference(session.startTime).inSeconds,
    'status': 'completed',
  };

  static int _cursorOffset(String? cursor) {
    if (cursor == null || !cursor.startsWith('demo:')) return 0;
    final offset = int.tryParse(cursor.substring('demo:'.length));
    return offset != null && offset >= 0 ? offset : 0;
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _bounded(String value, int maximum) {
    final trimmed = value.trim();
    return trimmed.length <= maximum ? trimmed : trimmed.substring(0, maximum);
  }
}

class _ExerciseAggregate {
  _ExerciseAggregate({required this.exercise});

  final Exercise exercise;
  int frequency = 0;
  int totalSets = 0;
  int totalReps = 0;
  double totalWeight = 0;
  int measuredSets = 0;
  DateTime lastUsedAt = DateTime.fromMillisecondsSinceEpoch(0);

  void add(WorkoutExercise row, WorkoutSession session) {
    frequency += 1;
    final completedSets = row.sets
        .where((set) => set.isCompleted && set.setType != SetType.warmup)
        .toList(growable: false);
    totalSets += completedSets.length;
    for (final set in completedSets) {
      totalReps += set.reps;
      totalWeight += set.weight;
      measuredSets += 1;
    }
    final usedAt = session.endTime ?? session.startTime;
    if (usedAt.isAfter(lastUsedAt)) lastUsedAt = usedAt;
  }

  Map<String, Object?> toJson() {
    final mode = exercise.loggingMode;
    final isCardio = mode == ExerciseLoggingMode.distanceDuration;
    final isDurationOnly = mode == ExerciseLoggingMode.durationOnly;
    final averageSets = frequency == 0 ? null : (totalSets / frequency).round();
    final averageReps = measuredSets == 0
        ? null
        : (totalReps / measuredSets).round();
    final averageWeight = measuredSets == 0
        ? null
        : double.parse((totalWeight / measuredSets).toStringAsFixed(1));
    return {
      'name': _bounded(exercise.name, 120),
      'slug': exercise.slug == null ? null : _bounded(exercise.slug!, 120),
      'kind': exercise.kind.name,
      'loggingMode': switch (mode) {
        ExerciseLoggingMode.weightReps => 'weight_reps',
        ExerciseLoggingMode.distanceDuration => 'distance_duration',
        ExerciseLoggingMode.durationOnly => 'duration_only',
      },
      'source': exercise.visibility == ExerciseVisibility.catalog
          ? 'catalog'
          : 'custom',
      'primaryMuscles': exercise.muscles
          .map((muscle) => _bounded(muscle, 80))
          .take(20)
          .toList(growable: false),
      'frequency': frequency,
      'lastUsedAt': lastUsedAt.toUtc().toIso8601String(),
      'typicalSets': averageSets,
      if (isCardio || isDurationOnly) ...{
        'typicalDistance': isCardio ? averageWeight : null,
        'typicalDurationSeconds': averageReps,
      } else ...{
        'typicalReps': averageReps,
        'typicalWeight': averageWeight,
      },
    };
  }

  static String _bounded(String value, int maximum) {
    final trimmed = value.trim();
    return trimmed.length <= maximum ? trimmed : trimmed.substring(0, maximum);
  }
}
