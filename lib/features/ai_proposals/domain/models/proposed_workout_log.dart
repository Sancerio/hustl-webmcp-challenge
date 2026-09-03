import 'package:equatable/equatable.dart';

/// One proposed set inside a `workout_log` proposal. Strength sets carry
/// weight/reps; cardio sets carry distance/durationSeconds. All optional.
class ProposedWorkoutSet extends Equatable {
  const ProposedWorkoutSet({
    this.weight,
    this.reps,
    this.rpe,
    this.distance,
    this.durationSeconds,
    this.setType,
  });

  final double? weight;
  final int? reps;
  final double? rpe;
  final double? distance;
  final int? durationSeconds;
  final String? setType;

  static double? _optNum(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  static int? _optInt(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  factory ProposedWorkoutSet.fromJson(Map<String, dynamic> json) {
    return ProposedWorkoutSet(
      weight: _optNum(json['weight']),
      reps: _optInt(json['reps']),
      rpe: _optNum(json['rpe']),
      distance: _optNum(json['distance']),
      durationSeconds: _optInt(json['durationSeconds']),
      setType: json['setType']?.toString(),
    );
  }

  @override
  List<Object?> get props => [weight, reps, rpe, distance, durationSeconds, setType];
}

/// A proposed exercise (name + its sets) inside a `workout_log` proposal. The
/// `exerciseId` payload field is the exercise NAME (resolved to a real exercise
/// at apply time).
class ProposedWorkoutExercise extends Equatable {
  const ProposedWorkoutExercise({
    required this.name,
    required this.sets,
    this.slug,
  });

  final String name;
  final String? slug;
  final List<ProposedWorkoutSet> sets;

  factory ProposedWorkoutExercise.fromJson(Map<String, dynamic> json) {
    final sets = (json['sets'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((m) => ProposedWorkoutSet.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    return ProposedWorkoutExercise(
      name: json['exerciseId']?.toString() ?? 'Exercise',
      slug: json['slug']?.toString(),
      sets: sets,
    );
  }

  @override
  List<Object?> get props => [name, slug, sets];
}

/// The completed workout carried by a `workout_log` proposal. On approve (or
/// auto-approve) a completed session + its exercises + sets are written; the whole
/// proposal is undoable (the session is deleted).
class ProposedWorkoutLog extends Equatable {
  const ProposedWorkoutLog({
    required this.name,
    required this.exercises,
    this.startedAt,
    this.durationSeconds,
    this.notes,
  });

  final String name;
  final DateTime? startedAt;
  final int? durationSeconds;
  final String? notes;
  final List<ProposedWorkoutExercise> exercises;

  int get totalSets => exercises.fold(0, (s, e) => s + e.sets.length);

  static DateTime? _parseDate(Object? raw) {
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw)?.toLocal();
    return null;
  }

  static int? _optInt(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  /// Parse from the backend `proposedPayload` map. Returns null when absent.
  static ProposedWorkoutLog? fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    final exercises = (json['exercises'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((m) => ProposedWorkoutExercise.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    return ProposedWorkoutLog(
      name: json['name']?.toString() ?? 'Workout',
      startedAt: _parseDate(json['startedAt']),
      durationSeconds: _optInt(json['durationSeconds']),
      notes: json['notes']?.toString(),
      exercises: exercises,
    );
  }

  @override
  List<Object?> get props => [name, startedAt, durationSeconds, notes, exercises];
}
