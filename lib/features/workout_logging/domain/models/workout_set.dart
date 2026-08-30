/// Enum to represent different types of workout sets
enum SetType { regular, warmup, failure, dropset, superset }

/// Sentinel used by [WorkoutSet.copyWith] so nullable fields can be explicitly
/// cleared back to null (e.g. to un-link a drop from its parent). Mirrors the
/// idiom used in `WorkoutExercise`/`WorkoutSession`.
const _unset = _WorkoutSetCopyWithUnset();

class _WorkoutSetCopyWithUnset {
  const _WorkoutSetCopyWithUnset();
}

/// Represents a single set of an exercise in a workout
class WorkoutSet {
  final String id;
  final double weight;
  final int reps;
  final int? rpe; // Rate of Perceived Exertion (1-10)
  final SetType setType;
  final String? notes;
  final bool isCompleted;
  final DateTime? completedAt;
  final bool isPr; // Personal Record flag

  /// Watch command id that created or completed this set. This makes replayed
  /// watch commands idempotent even if the app is killed after the set write but
  /// before the bridge ack/dedupe ledger is persisted.
  final String? watchCommandId;

  /// Dropset linkage: the id of the working set this drop belongs to.
  ///
  /// A working set has `parentSetId == null`. A drop has
  /// `setType == SetType.dropset`, `parentSetId == <parent.id>`, and a non-null
  /// [dropIndex]. Linkage is id-based (never index-based) so it survives
  /// reordering and id-based deletion. Null = legacy / standalone set.
  final String? parentSetId;

  /// 1-based ordering of this drop within its dropset (1, 2, 3 …).
  /// Null for working sets; set only on drops.
  final int? dropIndex;

  const WorkoutSet({
    required this.id,
    required this.weight,
    required this.reps,
    this.rpe,
    this.setType = SetType.regular,
    this.notes,
    this.isCompleted = false,
    this.completedAt,
    this.isPr = false,
    this.watchCommandId,
    this.parentSetId,
    this.dropIndex,
  });

  /// Whether this set carries any logged value. The lossy two-field model
  /// stores every logging mode in `weight`/`reps`:
  /// - weight+reps  -> weight and/or reps
  /// - duration-only -> reps (seconds)
  /// - distance+time -> weight (distance) and/or reps (duration)
  /// so a set with no weight and no reps has nothing logged. This is the signal
  /// for a skipped/untouched exercise (its generated sets were completed without
  /// entry), which must NOT surface as a "Previous" value (e.g. `00:00`).
  /// Bodyweight (reps only) and assisted (negative weight) still count.
  bool get hasLoggedValue => weight != 0 || reps != 0;

  // Convert model to a Map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'weight': weight,
      'reps': reps,
      'rpe': rpe,
      'setType': setType.name,
      'notes': notes,
      'isCompleted': isCompleted,
      'completedAt': completedAt?.millisecondsSinceEpoch,
      'isPr': isPr,
      'watch_command_id': watchCommandId,
      'parent_set_id': parentSetId,
      'drop_index': dropIndex,
    };
  }

  // Create model from a Map
  factory WorkoutSet.fromMap(Map<String, dynamic> map) {
    return WorkoutSet(
      id: map['id'] ?? '',
      weight: (map['weight'] is int)
          ? (map['weight'] as int).toDouble()
          : map['weight'] ?? 0.0,
      reps: map['reps'] ?? 0,
      // Coerce like every server-read path so a JSON double (e.g. 7.0) never
      // gets assigned straight into `int? rpe` and throws at runtime.
      rpe: (map['rpe'] as num?)?.toInt(),
      setType: parseSetType(map['setType']),
      notes: map['notes'],
      isCompleted: map['isCompleted'] ?? false,
      completedAt: map['completedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['completedAt'])
          : null,
      isPr: map['isPr'] ?? false,
      watchCommandId: map['watch_command_id'] as String?,
      // Missing keys (legacy maps) -> null, preserving flat behavior.
      parentSetId: map['parent_set_id'] as String?,
      dropIndex: (map['drop_index'] as num?)?.toInt(),
    );
  }

  static SetType parseSetType(dynamic raw) {
    if (raw is String) {
      return SetType.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => SetType.regular,
      );
    }
    if (raw is int) {
      return (raw >= 0 && raw < SetType.values.length)
          ? SetType.values[raw]
          : SetType.regular;
    }
    return SetType.regular;
  }

  // Create a copy of this WorkoutSet with the given fields replaced.
  //
  // [rpe], [parentSetId] and [dropIndex] use the [_unset] sentinel so they can
  // be explicitly cleared back to null (e.g. un-setting a logged RPE, or
  // converting a drop back to a standalone set); passing `null` clears,
  // omitting preserves.
  WorkoutSet copyWith({
    String? id,
    double? weight,
    int? reps,
    Object? rpe = _unset,
    SetType? setType,
    String? notes,
    bool? isCompleted,
    DateTime? completedAt,
    bool? isPr,
    Object? watchCommandId = _unset,
    Object? parentSetId = _unset,
    Object? dropIndex = _unset,
  }) {
    return WorkoutSet(
      id: id ?? this.id,
      weight: weight ?? this.weight,
      reps: reps ?? this.reps,
      rpe: rpe == _unset ? this.rpe : rpe as int?,
      setType: setType ?? this.setType,
      notes: notes ?? this.notes,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      isPr: isPr ?? this.isPr,
      watchCommandId: watchCommandId == _unset
          ? this.watchCommandId
          : watchCommandId as String?,
      parentSetId: parentSetId == _unset
          ? this.parentSetId
          : parentSetId as String?,
      dropIndex: dropIndex == _unset ? this.dropIndex : dropIndex as int?,
    );
  }

  @override
  String toString() {
    return 'WorkoutSet(id: $id, weight: $weight, reps: $reps, rpe: $rpe, setType: $setType, notes: $notes, isCompleted: $isCompleted, completedAt: $completedAt, isPr: $isPr, watchCommandId: $watchCommandId, parentSetId: $parentSetId, dropIndex: $dropIndex)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WorkoutSet &&
        other.id == id &&
        other.weight == weight &&
        other.reps == reps &&
        other.rpe == rpe &&
        other.setType == setType &&
        other.notes == notes &&
        other.isCompleted == isCompleted &&
        other.completedAt == completedAt &&
        other.isPr == isPr &&
        other.watchCommandId == watchCommandId &&
        other.parentSetId == parentSetId &&
        other.dropIndex == dropIndex;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        weight.hashCode ^
        reps.hashCode ^
        rpe.hashCode ^
        setType.hashCode ^
        notes.hashCode ^
        isCompleted.hashCode ^
        completedAt.hashCode ^
        isPr.hashCode ^
        watchCommandId.hashCode ^
        parentSetId.hashCode ^
        dropIndex.hashCode;
  }
}
