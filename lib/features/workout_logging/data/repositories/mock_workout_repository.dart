import 'package:uuid/uuid.dart';
import '../../domain/repositories/workout_repository.dart';
import '../../domain/models/workout_session.dart';
import '../../domain/models/workout_exercise.dart';
import '../../domain/models/workout_set.dart';
import '../../../exercise_library/domain/models/exercise.dart';

class _PrRecord {
  final double weight;
  final int reps;
  const _PrRecord(this.weight, this.reps);
}

class MockWorkoutRepository implements WorkoutRepository {
  final Map<String, WorkoutSession> _sessions = {};
  final Uuid _uuid = const Uuid();
  WorkoutSession? _activeSessionCache;

  // Mock previous records (simulated personal records)
  final Map<String, List<WorkoutSet>> _exerciseHistory = {};
  final Map<String, _PrRecord> _prCache = {};
  final Map<String, ExerciseKind> _exerciseKindByKey = {};
  final Map<String, ExerciseLoggingMode> _exerciseLoggingModeByKey = {};

  void _rebuildHistory() {
    _exerciseHistory.clear();
    _exerciseKindByKey.clear();
    _exerciseLoggingModeByKey.clear();
    for (final session in _sessions.values) {
      for (final ex in session.exercises) {
        final key = _keyForExercise(ex.exercise);
        _exerciseKindByKey[key] = ex.exercise.kind;
        _exerciseLoggingModeByKey[key] = ex.exercise.loggingMode;
        if (ex.exercise.loggingMode != ExerciseLoggingMode.weightReps) {
          continue;
        }
        final history = _exerciseHistory.putIfAbsent(key, () => []);
        final bool isAssisted = ex.exercise.kind == ExerciseKind.assisted;
        for (final set in ex.sets) {
          if (set.isCompleted) {
            if (isAssisted && set.weight >= 0) {
              continue;
            }
            history.add(set);
          }
        }
      }
    }
    _prCache.clear();
  }

  String _keyForExercise(Exercise exercise) {
    final canonical = exercise.canonicalKey;
    if (canonical != null && canonical.isNotEmpty) {
      return canonical;
    }
    final normalized = exercise.name.trim().toLowerCase();
    return normalized.isNotEmpty ? normalized : exercise.name;
  }

  String _keyForName(String name, [String? slug]) {
    final canonical = Exercise.canonicalKeyFrom(name: name, slug: slug);
    if (canonical != null && canonical.isNotEmpty) {
      return canonical;
    }
    final normalized = name.trim().toLowerCase();
    return normalized.isNotEmpty ? normalized : name;
  }

  bool _matchesExercise(Exercise exercise, String name, [String? slug]) {
    return exercise.matchesIdentity(name: name, slug: slug);
  }

  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession session) async {
    final String id = (session.id.isNotEmpty) ? session.id : _uuid.v4();
    final newSession = session.copyWith(id: id);
    _sessions[id] = newSession;
    _activeSessionCache = newSession;
    _rebuildHistory();
    return newSession;
  }

  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async {
    return _sessions[id];
  }

  @override
  // Custom convenience: return the latest active (non-completed) session
  Future<WorkoutSession?> getLatestActiveSession() async {
    if (_activeSessionCache != null && _activeSessionCache!.endTime == null) {
      return _activeSessionCache;
    }
    final ongoing = _sessions.values.where((s) => s.endTime == null).toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    _activeSessionCache = ongoing.isNotEmpty ? ongoing.first : null;
    return _activeSessionCache;
  }

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    var sessions = _sessions.values.toList();

    // Apply date filters if provided
    if (startDate != null) {
      sessions = sessions.where((s) => s.startTime.isAfter(startDate)).toList();
    }

    if (endDate != null) {
      sessions = sessions.where((s) => s.startTime.isBefore(endDate)).toList();
    }

    // Sort by date (newest first)
    sessions.sort((a, b) => b.startTime.compareTo(a.startTime));

    // Apply limit if provided
    if (limit != null && limit > 0 && limit < sessions.length) {
      sessions = sessions.sublist(0, limit);
    }

    return sessions;
  }

  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession session, {
    bool markDirty = true,
  }) async {
    if (!_sessions.containsKey(session.id)) {
      throw Exception('Session not found');
    }

    final shouldMarkDirty = markDirty ? true : session.dirty;
    final updated = session.copyWith(dirty: shouldMarkDirty);

    _sessions[session.id] = updated;
    if (updated.endTime == null) {
      _activeSessionCache = updated;
    }
    _rebuildHistory();
    return updated;
  }

  @override
  Future<void> deleteWorkoutSession(String id) async {
    final removed = _sessions.remove(id);
    if (_activeSessionCache?.id == removed?.id) {
      _activeSessionCache = null;
    }
    _rebuildHistory();
  }

  @override
  Future<WorkoutSession> addExerciseToSession(
    String sessionId,
    WorkoutExercise exercise,
  ) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found');
    }

    final updatedSession = session.addExercise(exercise);
    _sessions[sessionId] = updatedSession;
    _activeSessionCache = updatedSession;
    _rebuildHistory();
    return updatedSession;
  }

  @override
  Future<WorkoutSession> updateExerciseInSession(
    String sessionId,
    String exerciseId,
    WorkoutExercise exercise,
  ) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found');
    }

    final index = session.exercises.indexWhere((e) => e.id == exerciseId);
    if (index == -1) {
      throw Exception('Exercise not found in session');
    }

    final updatedSession = session.updateExercise(index, exercise);
    _sessions[sessionId] = updatedSession;
    _activeSessionCache = updatedSession;
    _rebuildHistory();
    return updatedSession;
  }

  @override
  Future<WorkoutSession> removeExerciseFromSession(
    String sessionId,
    String exerciseId,
  ) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found');
    }

    final index = session.exercises.indexWhere((e) => e.id == exerciseId);
    if (index == -1) {
      throw Exception('Exercise not found in session');
    }

    final updatedSession = session.removeExercise(index);
    _sessions[sessionId] = updatedSession;
    _activeSessionCache = updatedSession;
    _rebuildHistory();
    return updatedSession;
  }

  @override
  Future<WorkoutExercise> addSetToExercise(
    String sessionId,
    String exerciseId,
    WorkoutSet set,
  ) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found');
    }

    final index = session.exercises.indexWhere((e) => e.id == exerciseId);
    if (index == -1) {
      throw Exception('Exercise not found in session');
    }

    final exercise = session.exercises[index];
    final updatedExercise = exercise.addSet(set);

    final updatedSession = session.updateExercise(index, updatedExercise);
    _sessions[sessionId] = updatedSession;
    _activeSessionCache = updatedSession;
    _rebuildHistory();

    return updatedExercise;
  }

  @override
  Future<WorkoutExercise> updateSetInExercise(
    String sessionId,
    String exerciseId,
    int setIndex,
    WorkoutSet set,
  ) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found');
    }

    final exerciseIndex = session.exercises.indexWhere(
      (e) => e.id == exerciseId,
    );
    if (exerciseIndex == -1) {
      throw Exception('Exercise not found in session');
    }

    final exercise = session.exercises[exerciseIndex];
    if (setIndex < 0 || setIndex >= exercise.sets.length) {
      throw Exception('Set index out of bounds');
    }

    final updatedExercise = exercise.updateSet(setIndex, set);

    final updatedSession = session.updateExercise(
      exerciseIndex,
      updatedExercise,
    );
    _sessions[sessionId] = updatedSession;
    _activeSessionCache = updatedSession;
    _rebuildHistory();

    return updatedExercise;
  }

  @override
  Future<WorkoutSession> completeWorkoutSession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found');
    }

    final completedSession = session.complete();
    _sessions[sessionId] = completedSession;
    if (_activeSessionCache?.id == sessionId) {
      _activeSessionCache = null;
    }
    _rebuildHistory();
    return completedSession;
  }

  @override
  Future<List<WorkoutSet>?> getPreviousExerciseSets(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    DateTime? latest;
    List<WorkoutSet>? latestSets;
    for (final session in _sessions.values) {
      final DateTime t = session.startTime;
      if (latest != null && t.isBefore(latest)) continue;
      for (final ex in session.exercises) {
        if (_matchesExercise(ex.exercise, exerciseName, exerciseSlug)) {
          final completed = ex.sets.where((s) => s.isCompleted).toList();
          if (completed.isNotEmpty) {
            latest = t;
            latestSets = completed;
            break;
          }
        }
      }
    }
    return latestSets;
  }

  @override
  Future<DateTime?> getLastPerformedDate(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    final sessions = _sessions.values.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    for (final session in sessions) {
      if (session.exercises.any(
        (e) => _matchesExercise(e.exercise, exerciseName, exerciseSlug),
      )) {
        return session.startTime;
      }
    }
    return null;
  }

  @override
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  }) async {
    final key = _keyForName(exerciseName, exerciseSlug);
    if (_exerciseLoggingModeByKey[key] != null &&
        _exerciseLoggingModeByKey[key] != ExerciseLoggingMode.weightReps) {
      return false;
    }
    // Warm-ups and dropset drops are never PRs — only the heavy top set wins.
    if (set.setType == SetType.warmup || set.setType == SetType.dropset) {
      return false;
    }
    final kind = _exerciseKindByKey[key];
    if (kind == ExerciseKind.assisted && set.weight >= 0) {
      return false;
    }
    final current = _prCache[key] ??= _computeBestPr(key);
    final bool isPr =
        set.weight > current.weight ||
        (set.weight == current.weight && set.reps > current.reps);
    if (isPr) {
      _prCache[key] = _PrRecord(set.weight, set.reps);
    }
    return isPr;
  }

  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    final key = _keyForName(exerciseName, exerciseSlug);
    if (_exerciseLoggingModeByKey[key] != null &&
        _exerciseLoggingModeByKey[key] != ExerciseLoggingMode.weightReps) {
      return null;
    }
    final current = _prCache[key] ??= _computeBestPr(key);
    if (current.weight == double.negativeInfinity || current.reps < 0) {
      return null;
    }
    return ExercisePr(weight: current.weight, reps: current.reps);
  }

  _PrRecord _computeBestPr(String exerciseKey) {
    final history = _exerciseHistory[exerciseKey];
    final kind = _exerciseKindByKey[exerciseKey];
    double bestWeight = double.negativeInfinity;
    int bestReps = -1;
    if (history != null) {
      for (final s in history) {
        // Defensive: ensure only completed sets are considered
        if (!s.isCompleted) continue;
        // Warm-ups and dropset drops never set a PR.
        if (s.setType == SetType.warmup || s.setType == SetType.dropset) {
          continue;
        }
        if (kind == ExerciseKind.assisted && s.weight >= 0) continue;
        if (s.weight > bestWeight ||
            (s.weight == bestWeight && s.reps > bestReps)) {
          bestWeight = s.weight;
          bestReps = s.reps;
        }
      }
    }
    return _PrRecord(bestWeight, bestReps);
  }

  @override
  Future<void> recomputeAllPrFlags() async {
    // For mock, simply recompute on in-memory data with a simple pass
    final sessions = _sessions.values.toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final Map<String, double> bestWeight = {};
    final Map<String, int> bestRepsAtWeight = {};
    for (int i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      final updatedExercises = <WorkoutExercise>[];
      for (final ex in s.exercises) {
        final key = _keyForExercise(ex.exercise);
        if (ex.exercise.loggingMode != ExerciseLoggingMode.weightReps) {
          updatedExercises.add(
            ex.copyWith(
              sets: ex.sets.map((set) => set.copyWith(isPr: false)).toList(),
            ),
          );
          continue;
        }
        double bw = bestWeight[key] ?? double.negativeInfinity;
        int br = bestRepsAtWeight[key] ?? -1;
        final updatedSets = <WorkoutSet>[];
        final bool isAssisted = ex.exercise.kind == ExerciseKind.assisted;
        for (final set in ex.sets) {
          bool isPr = false;
          // Warm-ups and dropset drops never set a PR.
          if (set.isCompleted &&
              set.setType != SetType.warmup &&
              set.setType != SetType.dropset) {
            if (isAssisted && set.weight >= 0) {
              isPr = false;
            } else if (set.weight > bw || (set.weight == bw && set.reps > br)) {
              isPr = true;
              bw = set.weight;
              br = set.reps;
            }
          }
          updatedSets.add(set.copyWith(isPr: isPr));
        }
        bestWeight[key] = bw;
        bestRepsAtWeight[key] = br;
        updatedExercises.add(ex.copyWith(sets: updatedSets));
      }
      sessions[i] = s.copyWith(exercises: updatedExercises);
    }
    _sessions
      ..clear()
      ..addEntries(sessions.map((s) => MapEntry(s.id, s)));
    _rebuildHistory();
  }
}
