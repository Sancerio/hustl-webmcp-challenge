import 'package:flutter/foundation.dart';
import '../../../exercise_library/domain/models/exercise.dart';
import 'workout_exercise.dart';
import 'workout_set.dart';
import 'exercise_timeline_event.dart';

const _unset = _WorkoutSessionCopyWithUnset();

class _WorkoutSessionCopyWithUnset {
  const _WorkoutSessionCopyWithUnset();
}

/// Represents a complete workout session
class WorkoutSession {
  final String id;
  final String name;
  final DateTime startTime;
  final DateTime? endTime;
  final List<WorkoutExercise> exercises;
  final String? notes;
  final bool isCompleted;
  final DateTime? lastUpdatedAt;
  final bool dirty;

  /// When true, the phone requests that the watch should start recording when
  /// the watch app is opened for this session.
  final bool watchRecordingRequested;

  /// Local runtime state describing whether the watch is currently recording.
  /// Driven by watch connectivity events.
  final bool watchRecordingActive;
  final bool capturedOnWatch;
  final bool watchCapturePending;
  final DateTime? watchCapturePendingAt;
  final double? activeEnergyKilocalories;
  final double? averageHeartRateBpm;
  final double? maxHeartRateBpm;
  final int? watchDurationSeconds;
  final String? watchWorkoutUuid;
  final int? watchRecordingStartMs;
  final int? watchRecordingEndMs;
  final List<ExerciseTimelineEvent> timelineEvents;

  const WorkoutSession({
    required this.id,
    required this.name,
    required this.startTime,
    this.endTime,
    required this.exercises,
    this.notes,
    this.isCompleted = false,
    this.lastUpdatedAt,
    this.dirty = true,
    this.watchRecordingRequested = false,
    this.watchRecordingActive = false,
    this.capturedOnWatch = false,
    this.watchCapturePending = false,
    this.watchCapturePendingAt,
    this.activeEnergyKilocalories,
    this.averageHeartRateBpm,
    this.maxHeartRateBpm,
    this.watchDurationSeconds,
    this.watchWorkoutUuid,
    this.watchRecordingStartMs,
    this.watchRecordingEndMs,
    this.timelineEvents = const [],
  });

  // Calculate the session duration
  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  // Convert duration to human-readable format (00:00)
  String get durationFormatted {
    final dur = duration;
    final minutes = dur.inMinutes.remainder(60).toString().padLeft(2, '0');
    final hours = dur.inHours.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  // Calculate total volume (weight * reps across all sets). Warm-up sets are
  // excluded so they never inflate session/home volume (cross-app consensus).
  double get totalVolume {
    double volume = 0;
    for (final exercise in exercises) {
      if (exercise.exercise.loggingMode != ExerciseLoggingMode.weightReps) {
        continue;
      }
      for (final set in exercise.sets) {
        if (set.isCompleted && set.setType != SetType.warmup) {
          volume += set.weight * set.reps;
        }
      }
    }
    return volume;
  }

  // Convert model to a Map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime?.millisecondsSinceEpoch,
      'exercises': exercises.map((e) => e.toMap()).toList(),
      'notes': notes,
      'isCompleted': isCompleted,
      'lastUpdatedAt': lastUpdatedAt?.millisecondsSinceEpoch,
      'dirty': dirty,
      'watchRecordingRequested': watchRecordingRequested,
      'watchRecordingActive': watchRecordingActive,
      'capturedOnWatch': capturedOnWatch,
      'watchCapturePending': watchCapturePending,
      'watchCapturePendingAt': watchCapturePendingAt?.millisecondsSinceEpoch,
      'activeEnergyKilocalories': activeEnergyKilocalories,
      'averageHeartRateBpm': averageHeartRateBpm,
      'maxHeartRateBpm': maxHeartRateBpm,
      'watchDurationSeconds': watchDurationSeconds,
      'watchWorkoutUuid': watchWorkoutUuid,
      'watchRecordingStartMs': watchRecordingStartMs,
      'watchRecordingEndMs': watchRecordingEndMs,
      'timelineEvents': timelineEvents.map((e) => e.toMap()).toList(),
    };
  }

  // Create model from a Map
  factory WorkoutSession.fromMap(
    Map<String, dynamic> map,
    List<WorkoutExercise> resolvedExercises,
  ) {
    return WorkoutSession(
      id: map['id'] ?? '',
      name: map['name'] ?? 'Workout',
      startTime: DateTime.fromMillisecondsSinceEpoch(map['startTime']),
      endTime: map['endTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['endTime'])
          : null,
      exercises: resolvedExercises,
      notes: map['notes'],
      isCompleted: map['isCompleted'] ?? false,
      lastUpdatedAt: map['lastUpdatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastUpdatedAt'])
          : null,
      // Default to true so legacy data gets uploaded at least once
      dirty: map['dirty'] is bool ? (map['dirty'] as bool) : true,
      watchRecordingRequested: map['watchRecordingRequested'] as bool? ?? false,
      watchRecordingActive: map['watchRecordingActive'] as bool? ?? false,
      capturedOnWatch: map['capturedOnWatch'] as bool? ?? false,
      watchCapturePending: map['watchCapturePending'] as bool? ?? false,
      watchCapturePendingAt: map['watchCapturePendingAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['watchCapturePendingAt'] as num).toInt(),
            )
          : null,
      activeEnergyKilocalories: (map['activeEnergyKilocalories'] as num?)
          ?.toDouble(),
      averageHeartRateBpm: (map['averageHeartRateBpm'] as num?)?.toDouble(),
      maxHeartRateBpm: (map['maxHeartRateBpm'] as num?)?.toDouble(),
      watchDurationSeconds: (map['watchDurationSeconds'] as num?)?.toInt(),
      watchWorkoutUuid: map['watchWorkoutUuid'] as String?,
      watchRecordingStartMs: (map['watchRecordingStartMs'] as num?)?.toInt(),
      watchRecordingEndMs: (map['watchRecordingEndMs'] as num?)?.toInt(),
      timelineEvents: (map['timelineEvents'] is List)
          ? (map['timelineEvents'] as List)
                .whereType<Map>()
                .map(
                  (raw) => ExerciseTimelineEvent.fromMap(
                    Map<String, dynamic>.from(raw),
                  ),
                )
                .whereType<ExerciseTimelineEvent>()
                .toList()
          : const [],
    );
  }

  // Create a copy of this WorkoutSession with the given fields replaced
  WorkoutSession copyWith({
    String? id,
    String? name,
    DateTime? startTime,
    DateTime? endTime,
    List<WorkoutExercise>? exercises,
    String? notes,
    bool? isCompleted,
    DateTime? lastUpdatedAt,
    bool? dirty,
    bool? watchRecordingRequested,
    bool? watchRecordingActive,
    bool? capturedOnWatch,
    bool? watchCapturePending,
    Object? watchCapturePendingAt = _unset,
    double? activeEnergyKilocalories,
    double? averageHeartRateBpm,
    double? maxHeartRateBpm,
    int? watchDurationSeconds,
    String? watchWorkoutUuid,
    int? watchRecordingStartMs,
    int? watchRecordingEndMs,
    List<ExerciseTimelineEvent>? timelineEvents,
  }) {
    return WorkoutSession(
      id: id ?? this.id,
      name: name ?? this.name,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      exercises: exercises ?? this.exercises,
      notes: notes ?? this.notes,
      isCompleted: isCompleted ?? this.isCompleted,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      dirty: dirty ?? this.dirty,
      watchRecordingRequested:
          watchRecordingRequested ?? this.watchRecordingRequested,
      watchRecordingActive: watchRecordingActive ?? this.watchRecordingActive,
      capturedOnWatch: capturedOnWatch ?? this.capturedOnWatch,
      watchCapturePending: watchCapturePending ?? this.watchCapturePending,
      watchCapturePendingAt: watchCapturePendingAt == _unset
          ? this.watchCapturePendingAt
          : watchCapturePendingAt as DateTime?,
      activeEnergyKilocalories:
          activeEnergyKilocalories ?? this.activeEnergyKilocalories,
      averageHeartRateBpm: averageHeartRateBpm ?? this.averageHeartRateBpm,
      maxHeartRateBpm: maxHeartRateBpm ?? this.maxHeartRateBpm,
      watchDurationSeconds: watchDurationSeconds ?? this.watchDurationSeconds,
      watchWorkoutUuid: watchWorkoutUuid ?? this.watchWorkoutUuid,
      watchRecordingStartMs:
          watchRecordingStartMs ?? this.watchRecordingStartMs,
      watchRecordingEndMs: watchRecordingEndMs ?? this.watchRecordingEndMs,
      timelineEvents: timelineEvents ?? this.timelineEvents,
    );
  }

  // Mark the session as completed, pruning any incomplete sets.
  WorkoutSession complete() {
    // Remove incomplete sets but retain exercises even if none are finished.
    final cleanedExercises = <WorkoutExercise>[
      for (final ex in exercises)
        ex.copyWith(sets: ex.sets.where((s) => s.isCompleted).toList()),
    ];

    return copyWith(
      exercises: cleanedExercises,
      endTime: DateTime.now(),
      isCompleted: true,
    );
  }

  // Add an exercise to the session
  WorkoutSession addExercise(WorkoutExercise exercise) {
    return copyWith(exercises: [...exercises, exercise]);
  }

  // Update an exercise at a specific index
  WorkoutSession updateExercise(int index, WorkoutExercise exercise) {
    if (index < 0 || index >= exercises.length) {
      return this;
    }

    final newExercises = [...exercises];
    newExercises[index] = exercise;

    return copyWith(exercises: newExercises);
  }

  // Remove an exercise at a specific index
  WorkoutSession removeExercise(int index) {
    if (index < 0 || index >= exercises.length) {
      return this;
    }

    final newExercises = [...exercises];
    newExercises.removeAt(index);

    return copyWith(exercises: newExercises);
  }

  @override
  String toString() {
    return 'WorkoutSession(id: $id, name: $name, startTime: $startTime, endTime: $endTime, exercises: $exercises, notes: $notes, isCompleted: $isCompleted, lastUpdatedAt: $lastUpdatedAt, dirty: $dirty, watchRecordingRequested: $watchRecordingRequested, watchRecordingActive: $watchRecordingActive, capturedOnWatch: $capturedOnWatch, watchCapturePending: $watchCapturePending, watchCapturePendingAt: $watchCapturePendingAt, activeEnergyKilocalories: $activeEnergyKilocalories, averageHeartRateBpm: $averageHeartRateBpm, maxHeartRateBpm: $maxHeartRateBpm, watchDurationSeconds: $watchDurationSeconds, watchWorkoutUuid: $watchWorkoutUuid, watchRecordingStartMs: $watchRecordingStartMs, watchRecordingEndMs: $watchRecordingEndMs, timelineEvents: ${timelineEvents.length})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WorkoutSession &&
        other.id == id &&
        other.name == name &&
        other.startTime == startTime &&
        other.endTime == endTime &&
        listEquals(other.exercises, exercises) &&
        other.notes == notes &&
        other.isCompleted == isCompleted &&
        other.dirty == dirty &&
        other.lastUpdatedAt == lastUpdatedAt &&
        other.watchRecordingRequested == watchRecordingRequested &&
        other.watchRecordingActive == watchRecordingActive &&
        other.capturedOnWatch == capturedOnWatch &&
        other.watchCapturePending == watchCapturePending &&
        other.watchCapturePendingAt == watchCapturePendingAt &&
        other.activeEnergyKilocalories == activeEnergyKilocalories &&
        other.averageHeartRateBpm == averageHeartRateBpm &&
        other.maxHeartRateBpm == maxHeartRateBpm &&
        other.watchDurationSeconds == watchDurationSeconds &&
        other.watchWorkoutUuid == watchWorkoutUuid &&
        other.watchRecordingStartMs == watchRecordingStartMs &&
        other.watchRecordingEndMs == watchRecordingEndMs &&
        listEquals(other.timelineEvents, timelineEvents);
  }

  @override
  int get hashCode {
    return Object.hashAll([
      id,
      name,
      startTime,
      endTime,
      Object.hashAll(exercises),
      notes,
      isCompleted,
      dirty,
      lastUpdatedAt,
      watchRecordingRequested,
      watchRecordingActive,
      capturedOnWatch,
      watchCapturePending,
      watchCapturePendingAt,
      activeEnergyKilocalories,
      averageHeartRateBpm,
      maxHeartRateBpm,
      watchDurationSeconds,
      watchWorkoutUuid,
      watchRecordingStartMs,
      watchRecordingEndMs,
      Object.hashAll(timelineEvents),
    ]);
  }
}
