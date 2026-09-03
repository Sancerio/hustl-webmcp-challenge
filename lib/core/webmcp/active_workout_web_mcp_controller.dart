import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../features/workout_logging/domain/models/workout_exercise.dart';
import '../../features/workout_logging/domain/models/workout_session.dart';
import '../../features/workout_logging/domain/models/workout_set.dart';
import 'web_mcp_access_gate.dart';

typedef ActiveWorkoutSessionReader = WorkoutSession? Function();
typedef ApplyWorkoutAdjustment =
    Future<bool> Function(StagedWorkoutAdjustment adjustment);

class WorkoutSetAdjustment {
  const WorkoutSetAdjustment({
    required this.exerciseId,
    required this.exerciseName,
    required this.setId,
    required this.setNumber,
    required this.before,
    required this.after,
  });

  final String exerciseId;
  final String exerciseName;
  final String setId;
  final int setNumber;
  final WorkoutSet before;
  final WorkoutSet after;
}

class StagedWorkoutAdjustment {
  const StagedWorkoutAdjustment({
    required this.ownerToken,
    required this.sessionId,
    required this.baseRevision,
    required this.changes,
  });

  final int ownerToken;
  final String sessionId;
  final String baseRevision;
  final List<WorkoutSetAdjustment> changes;
}

class ActiveWorkoutWebMcpController {
  ActiveWorkoutWebMcpController({WebMcpAccessGate? accessGate})
    : _accessGate = accessGate {
    accessGate?.ready.addListener(_handleAccessChange);
  }

  final ValueNotifier<StagedWorkoutAdjustment?> pending = ValueNotifier(null);

  final WebMcpAccessGate? _accessGate;
  _ActiveWorkoutBinding? _binding;
  int _nextOwnerToken = 0;

  int attach({
    required ActiveWorkoutSessionReader readSession,
    required ApplyWorkoutAdjustment apply,
  }) {
    final token = ++_nextOwnerToken;
    final accessGate = _accessGate;
    if (accessGate != null && !accessGate.ready.value) {
      _binding = null;
      _setPending(null);
      return token;
    }
    _binding = _ActiveWorkoutBinding(
      token: token,
      accessGeneration: accessGate?.generation,
      readSession: readSession,
      apply: apply,
    );
    _setPending(null);
    return token;
  }

  void detach(int token) {
    if (_binding?.token != token) return;
    _binding = null;
    _setPending(null);
  }

  Map<String, Object?> getActiveWorkout() {
    final session = _currentBinding()?.readSession();
    if (session == null || session.isCompleted || session.endTime != null) {
      return const {'status': 'unavailable', 'code': 'no_active_workout'};
    }
    return {
      'status': 'ready',
      'sessionId': session.id,
      'name': session.name,
      'baseRevision': revisionFor(session),
      'exercises': [
        for (final exercise in session.exercises.take(30))
          {
            'exerciseId': exercise.id,
            'name': exercise.exercise.name,
            'loggingMode': exercise.exercise.loggingMode.name,
            'sets': [
              for (
                var index = 0;
                index < exercise.sets.length && index < 20;
                index++
              )
                _setJson(exercise.sets[index], index),
            ],
          },
      ],
      'truncated':
          session.exercises.length > 30 ||
          session.exercises.any((exercise) => exercise.sets.length > 20),
    };
  }

  Map<String, Object?> stage(Map<String, Object?> arguments) {
    final binding = _currentBinding();
    final session = binding?.readSession();
    if (binding == null ||
        session == null ||
        session.isCompleted ||
        session.endTime != null) {
      return const {'status': 'unavailable', 'code': 'no_active_workout'};
    }
    if (arguments.length != 1 || !arguments.containsKey('changes')) {
      return _invalid('invalid_arguments');
    }
    final rawChanges = arguments['changes'];
    if (rawChanges is! List || rawChanges.isEmpty || rawChanges.length > 8) {
      return _invalid('invalid_change_count');
    }

    final changes = <WorkoutSetAdjustment>[];
    final targets = <String>{};
    for (final raw in rawChanges) {
      if (raw is! Map) return _invalid('invalid_change');
      final change = Map<String, Object?>.from(raw);
      const allowed = {'exerciseId', 'setId', 'weight', 'reps', 'rpe'};
      if (change.keys.any((key) => !allowed.contains(key)) ||
          change['exerciseId'] is! String ||
          change['setId'] is! String) {
        return _invalid('invalid_change');
      }
      final hasWeight = change.containsKey('weight');
      final hasReps = change.containsKey('reps');
      final hasRpe = change.containsKey('rpe');
      if (!hasWeight && !hasReps && !hasRpe) {
        return _invalid('empty_change');
      }

      final exerciseId = change['exerciseId']! as String;
      final setId = change['setId']! as String;
      final targetKey = '$exerciseId\u0000$setId';
      if (!targets.add(targetKey)) return _invalid('duplicate_target');

      final exercise = _findExercise(session, exerciseId, maxExercises: 30);
      if (exercise == null) return _invalid('exercise_not_found');
      final setIndex = exercise.sets.indexWhere((set) => set.id == setId);
      if (setIndex < 0 || setIndex >= 20) return _invalid('set_not_found');
      final before = exercise.sets[setIndex];
      if (before.isCompleted) return _invalid('completed_set_immutable');

      final weight = hasWeight
          ? _validDouble(change['weight'], 0, 2000)
          : before.weight;
      final reps = hasReps ? _validInt(change['reps'], 0, 1000) : before.reps;
      final rpe = hasRpe ? _validInt(change['rpe'], 1, 10) : before.rpe;
      if (weight == null || reps == null || (hasRpe && rpe == null)) {
        return _invalid('value_out_of_range');
      }
      final after = before.copyWith(weight: weight, reps: reps, rpe: rpe);
      if (after == before) return _invalid('no_change');
      changes.add(
        WorkoutSetAdjustment(
          exerciseId: exercise.id,
          exerciseName: exercise.exercise.name,
          setId: before.id,
          setNumber: setIndex + 1,
          before: before,
          after: after,
        ),
      );
    }

    final staged = StagedWorkoutAdjustment(
      ownerToken: binding.token,
      sessionId: session.id,
      baseRevision: revisionFor(session),
      changes: List.unmodifiable(changes),
    );
    _setPending(staged);
    return {
      'status': 'staged',
      'changeCount': changes.length,
      'baseRevision': staged.baseRevision,
      'requiresHumanReview': true,
    };
  }

  StagedWorkoutAdjustment? pendingFor(WorkoutSession session) {
    final staged = pending.value;
    if (staged == null ||
        staged.sessionId != session.id ||
        staged.baseRevision != revisionFor(session)) {
      return null;
    }
    return staged;
  }

  void invalidateIfStale(WorkoutSession session) {
    if (pending.value != null && pendingFor(session) == null) _setPending(null);
  }

  Future<bool> applyPending() async {
    final binding = _currentBinding();
    final staged = pending.value;
    final session = binding?.readSession();
    if (binding == null || staged == null || session == null) return false;
    if (binding.token != staged.ownerToken ||
        session.id != staged.sessionId ||
        revisionFor(session) != staged.baseRevision) {
      _setPending(null);
      return false;
    }
    for (final change in staged.changes) {
      final exercise = _findExercise(session, change.exerciseId);
      final set = exercise?.sets
          .where((set) => set.id == change.setId)
          .firstOrNull;
      if (set == null || set.isCompleted || set != change.before) {
        _setPending(null);
        return false;
      }
    }
    final applied = await binding.apply(staged);
    if (applied && pending.value == staged) _setPending(null);
    return applied;
  }

  void discard() => _setPending(null);

  void dispose() {
    _accessGate?.ready.removeListener(_handleAccessChange);
    pending.dispose();
  }

  static String revisionFor(WorkoutSession session) {
    final revisionPayload = <String, Object?>{
      'sessionId': session.id,
      'isCompleted': session.isCompleted,
      'hasEndTime': session.endTime != null,
      'exercises': [
        for (final exercise in session.exercises)
          {
            'exerciseId': exercise.id,
            'sets': [
              for (final set in exercise.sets)
                {
                  'setId': set.id,
                  'weight': set.weight,
                  'reps': set.reps,
                  'rpe': set.rpe,
                  'isCompleted': set.isCompleted,
                },
            ],
          },
      ],
    };
    final bytes = utf8.encode(jsonEncode(revisionPayload));
    var hash = 17;
    for (final byte in bytes) {
      // Stay below JavaScript's exact-integer ceiling so the same revision
      // logic is reliable in Flutter web and the Dart VM.
      hash = (hash * 31 + byte) % 2147483647;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static Map<String, Object?> _setJson(WorkoutSet set, int index) => {
    'setId': set.id,
    'setNumber': index + 1,
    'weight': set.weight,
    'reps': set.reps,
    'rpe': set.rpe,
    'setType': set.setType.name,
    'isCompleted': set.isCompleted,
  };

  static WorkoutExercise? _findExercise(
    WorkoutSession session,
    String id, {
    int? maxExercises,
  }) {
    final exercises = maxExercises == null
        ? session.exercises
        : session.exercises.take(maxExercises);
    for (final exercise in exercises) {
      if (exercise.id == id) return exercise;
    }
    return null;
  }

  static double? _validDouble(Object? value, double min, double max) {
    if (value is! num) return null;
    final result = value.toDouble();
    return result.isFinite && result >= min && result <= max ? result : null;
  }

  static int? _validInt(Object? value, int min, int max) {
    if (value is! num || !value.isFinite || value.toInt() != value) return null;
    final result = value.toInt();
    return result >= min && result <= max ? result : null;
  }

  static Map<String, Object?> _invalid(String code) => {
    'status': 'invalid_request',
    'code': code,
  };

  void _setPending(StagedWorkoutAdjustment? value) {
    if (pending.value != value) pending.value = value;
  }

  _ActiveWorkoutBinding? _currentBinding() {
    final binding = _binding;
    final accessGate = _accessGate;
    if (binding == null || accessGate == null) return binding;
    final generation = binding.accessGeneration;
    if (generation != null && accessGate.isReadyFor(generation)) return binding;
    _binding = null;
    _setPending(null);
    return null;
  }

  void _handleAccessChange() {
    if (_accessGate?.ready.value ?? true) return;
    _binding = null;
    _setPending(null);
  }
}

class _ActiveWorkoutBinding {
  const _ActiveWorkoutBinding({
    required this.token,
    required this.accessGeneration,
    required this.readSession,
    required this.apply,
  });

  final int token;
  final int? accessGeneration;
  final ActiveWorkoutSessionReader readSession;
  final ApplyWorkoutAdjustment apply;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
