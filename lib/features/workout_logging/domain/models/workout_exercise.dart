import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'workout_set.dart';
import '../../../exercise_library/domain/models/exercise.dart';

/// Sentinel used by [WorkoutExercise.copyWith] so nullable fields can be
/// explicitly cleared back to null (mirrors the idiom in `WorkoutSession`).
const _unset = _WorkoutExerciseCopyWithUnset();

class _WorkoutExerciseCopyWithUnset {
  const _WorkoutExerciseCopyWithUnset();
}

/// Represents an exercise instance within a workout session
class WorkoutExercise {
  final String id;
  final Exercise exercise;
  final List<WorkoutSet> sets;
  final List<WorkoutSet>?
  previousSessionSets; // Previous workout's sets for comparison
  final String? notes;
  final int? restTimerSeconds; // Per-exercise rest timer in seconds
  final Map<String, dynamic>? metrics;

  /// Exercises sharing this id form one superset/giant set/circuit group.
  /// Null = legacy flat behavior (ungrouped).
  final String? supersetGroupId;

  /// 0-based position of this exercise within its superset group.
  /// Null when [supersetGroupId] is null.
  final int? supersetOrder;

  /// True when this phone row was MINTED from a watch snapshot (a wrist-picked /
  /// catalog exercise the phone never authored). Such a row carries a fresh phone
  /// ROW UUID in [id] while [exercise.id] holds the watch/catalog id the watch keeps
  /// re-sending as `WatchSessionExercise.exerciseId`. The live-merge uses this flag to
  /// re-match the row on later snapshots by [exercise.id] (the watch never echoes the
  /// phone ROW UUID for these), so it is reconciled instead of duplicated on each
  /// update. Phone-authored rows leave this false so a coincidental catalog-id collision
  /// can never collapse two distinct phone instances (the inverse-of-#359 hazard).
  final bool createdFromWatch;

  const WorkoutExercise({
    required this.id,
    required this.exercise,
    required this.sets,
    this.previousSessionSets,
    this.notes,
    this.restTimerSeconds,
    this.metrics,
    this.supersetGroupId,
    this.supersetOrder,
    this.createdFromWatch = false,
  });

  // Convert model to a Map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      // The library/catalog id for this exercise. Persisted so it survives a cold
      // relaunch (the local repo reads it back as `exMap['exerciseId']`). The live
      // watch-merge relies on it to re-match a wrist-minted (`createdFromWatch`) row.
      'exerciseId': exercise.id,
      'exerciseName': exercise.name,
      'exerciseSlug': exercise.slug,
      'exerciseMuscles': exercise.muscles,
      'exerciseKind': exercise.kind.name,
      'exerciseLoggingMode': exercise.loggingMode.name,
      'sets': sets.map((set) => set.toMap()).toList(),
      'previousSessionSets': previousSessionSets
          ?.map((set) => set.toMap())
          .toList(),
      'notes': notes,
      'restTimerSeconds': restTimerSeconds,
      'metrics': metrics,
      'superset_group_id': supersetGroupId,
      'superset_order': supersetOrder,
      'createdFromWatch': createdFromWatch,
    };
  }

  // Create model from a Map
  factory WorkoutExercise.fromMap(Map<String, dynamic> map, Exercise exercise) {
    return WorkoutExercise(
      id: map['id'] ?? '',
      exercise: exercise,
      sets:
          (map['sets'] as List?)
              ?.map((set) => WorkoutSet.fromMap(set))
              .toList() ??
          [],
      previousSessionSets: (map['previousSessionSets'] as List?)
          ?.map((set) => WorkoutSet.fromMap(set))
          .toList(),
      notes: map['notes'],
      restTimerSeconds: map['restTimerSeconds'],
      metrics: map['metrics'] is Map
          ? Map<String, dynamic>.from(map['metrics'])
          : null,
      // Tolerant of missing keys (legacy maps) -> null.
      supersetGroupId: map['superset_group_id'] as String?,
      supersetOrder: (map['superset_order'] as num?)?.toInt(),
      createdFromWatch: map['createdFromWatch'] as bool? ?? false,
    );
  }

  // Create a copy of this WorkoutExercise with the given fields replaced
  WorkoutExercise copyWith({
    String? id,
    Exercise? exercise,
    List<WorkoutSet>? sets,
    List<WorkoutSet>? previousSessionSets,
    String? notes,
    int? restTimerSeconds,
    Map<String, dynamic>? metrics,
    Object? supersetGroupId = _unset,
    Object? supersetOrder = _unset,
    bool? createdFromWatch,
  }) {
    return WorkoutExercise(
      id: id ?? this.id,
      exercise: exercise ?? this.exercise,
      sets: sets ?? this.sets,
      previousSessionSets: previousSessionSets ?? this.previousSessionSets,
      notes: notes ?? this.notes,
      restTimerSeconds: restTimerSeconds ?? this.restTimerSeconds,
      metrics: metrics ?? this.metrics,
      supersetGroupId: supersetGroupId == _unset
          ? this.supersetGroupId
          : supersetGroupId as String?,
      supersetOrder: supersetOrder == _unset
          ? this.supersetOrder
          : supersetOrder as int?,
      createdFromWatch: createdFromWatch ?? this.createdFromWatch,
    );
  }

  // Add a new set to this exercise
  WorkoutExercise addSet(WorkoutSet set) {
    return copyWith(sets: [...sets, set]);
  }

  // Update a set at a specific index
  WorkoutExercise updateSet(int index, WorkoutSet set) {
    if (index < 0 || index >= sets.length) {
      return this;
    }

    final newSets = [...sets];
    newSets[index] = set;

    return copyWith(sets: newSets);
  }

  // Remove a set at a specific index
  WorkoutExercise removeSet(int index) {
    if (index < 0 || index >= sets.length) {
      return this;
    }

    final newSets = [...sets];
    newSets.removeAt(index);

    return copyWith(sets: newSets);
  }

  @override
  String toString() {
    return 'WorkoutExercise(id: $id, exercise: ${exercise.name}, sets: $sets, previousSessionSets: $previousSessionSets, notes: $notes, supersetGroupId: $supersetGroupId, supersetOrder: $supersetOrder, createdFromWatch: $createdFromWatch)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    const deep = DeepCollectionEquality();
    return other is WorkoutExercise &&
        other.id == id &&
        other.exercise == exercise &&
        listEquals(other.sets, sets) &&
        listEquals(other.previousSessionSets, previousSessionSets) &&
        other.notes == notes &&
        other.restTimerSeconds == restTimerSeconds &&
        deep.equals(other.metrics, metrics) &&
        other.supersetGroupId == supersetGroupId &&
        other.supersetOrder == supersetOrder &&
        other.createdFromWatch == createdFromWatch;
  }

  @override
  int get hashCode {
    const deep = DeepCollectionEquality();
    return Object.hash(
      id,
      exercise,
      Object.hashAll(sets),
      previousSessionSets == null ? null : Object.hashAll(previousSessionSets!),
      notes,
      restTimerSeconds,
      deep.hash(metrics),
      supersetGroupId,
      supersetOrder,
      createdFromWatch,
    );
  }
}
