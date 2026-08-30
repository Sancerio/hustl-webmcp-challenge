enum ExerciseTimelineEventKind {
  workoutStart,
  workoutEnd,
  select,
  setComplete,
  watchNav,
  restStart,
  restStop,
}

class ExerciseTimelineEvent {
  const ExerciseTimelineEvent({
    required this.tsMs,
    required this.kind,
    this.workoutExerciseId,
  });

  final int tsMs;
  final ExerciseTimelineEventKind kind;
  final String? workoutExerciseId;

  Map<String, dynamic> toMap() {
    return {
      'tsMs': tsMs,
      'kind': kind.name,
      'workoutExerciseId': workoutExerciseId,
    };
  }

  static ExerciseTimelineEvent? fromMap(Map<String, dynamic> map) {
    final ts = (map['tsMs'] as num?)?.toInt();
    final kindRaw = map['kind'];
    if (ts == null) return null;
    if (kindRaw is! String) return null;
    ExerciseTimelineEventKind? kind;
    for (final candidate in ExerciseTimelineEventKind.values) {
      if (candidate.name == kindRaw) {
        kind = candidate;
        break;
      }
    }
    if (kind == null) return null;
    final id = map['workoutExerciseId'] as String?;
    return ExerciseTimelineEvent(tsMs: ts, kind: kind, workoutExerciseId: id);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExerciseTimelineEvent &&
        other.tsMs == tsMs &&
        other.kind == kind &&
        other.workoutExerciseId == workoutExerciseId;
  }

  @override
  int get hashCode => Object.hash(tsMs, kind, workoutExerciseId);

  @override
  String toString() {
    return 'ExerciseTimelineEvent(tsMs: $tsMs, kind: ${kind.name}, workoutExerciseId: $workoutExerciseId)';
  }
}
