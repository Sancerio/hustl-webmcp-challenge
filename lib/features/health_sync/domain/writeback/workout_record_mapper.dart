import 'package:collection/collection.dart';

import '../../../workout_logging/domain/models/workout_session.dart';
import '../../../workout_logging/domain/models/workout_exercise.dart';
import '../../../workout_logging/domain/models/workout_set.dart';
import '../../../exercise_library/domain/models/exercise.dart';

import 'workout_record.dart';

/// Utility for transforming Hustl workout sessions into writeback-ready records.
class WorkoutRecordMapper {
  const WorkoutRecordMapper();

  WorkoutRecord fromSession(WorkoutSession session) {
    final endTime = session.endTime ?? DateTime.now();
    final startedAtUtc = session.startTime.toUtc();
    final endedAtUtc = endTime.toUtc();
    final durationSec = endedAtUtc
        .difference(startedAtUtc)
        .inSeconds
        .clamp(1, 86400);

    final activityType = _inferActivityType(session);
    final syncIdentifier = session.id;
    final syncVersionSource = session.lastUpdatedAt ?? endTime;
    final externalUuid = 'hustl:$syncIdentifier';
    final metadata = <String, String>{
      'name': session.name,
      'platform': 'hustl',
      'HKMetadataKeyWorkoutBrandName': session.name,
      'HKMetadataKeySyncIdentifier': syncIdentifier,
      'HKMetadataKeySyncVersion': syncVersionSource.millisecondsSinceEpoch
          .toString(),
      'HKMetadataKeyExternalUUID': externalUuid,
    };
    if (session.notes?.isNotEmpty == true) {
      metadata['notes'] = session.notes!;
    }

    return WorkoutRecord(
      sessionId: session.id,
      activityType: activityType,
      startedAt: startedAtUtc,
      endedAt: endedAtUtc,
      duration: durationSec,
      energyKilocalories:
          session.activeEnergyKilocalories ?? _estimateEnergy(session),
      distanceMeters: null,
      averageHeartRateBpm: session.averageHeartRateBpm,
      maxHeartRateBpm: session.maxHeartRateBpm,
      steps: null,
      metadata: metadata,
    );
  }

  WorkoutActivityType _inferActivityType(WorkoutSession session) {
    final name = session.name;
    if (_matchesRun(name)) return WorkoutActivityType.running;
    if (_matchesCycling(name)) {
      return WorkoutActivityType.cycling;
    }
    if (_matchesYoga(name)) return WorkoutActivityType.yoga;
    if (_matchesHiit(name)) return WorkoutActivityType.hiit;

    WorkoutActivityType? inferredFromExercises;
    for (final exercise in session.exercises) {
      final type = _mapExercise(exercise);
      if (type == WorkoutActivityType.running ||
          type == WorkoutActivityType.cycling ||
          type == WorkoutActivityType.yoga) {
        return type;
      }
      inferredFromExercises ??= type;
    }
    return inferredFromExercises ?? WorkoutActivityType.strength;
  }

  WorkoutActivityType _mapExercise(WorkoutExercise exercise) {
    final ex = exercise.exercise;
    switch (ex.kind) {
      case ExerciseKind.cardio:
        return _inferCardioActivity(exercise);
      case ExerciseKind.assisted:
        return WorkoutActivityType.strength;
      case ExerciseKind.strength:
        break;
    }
    final name = ex.name;
    if (_matchesYoga(name)) return WorkoutActivityType.yoga;
    if (_matchesRun(name)) return WorkoutActivityType.running;
    if (_matchesCycling(name)) {
      return WorkoutActivityType.cycling;
    }
    if (_matchesRowing(name)) return WorkoutActivityType.cardio;
    return WorkoutActivityType.strength;
  }

  WorkoutActivityType _inferCardioActivity(WorkoutExercise exercise) {
    final name = exercise.exercise.name;
    if (_matchesRun(name)) {
      return WorkoutActivityType.running;
    }
    if (_matchesCycling(name)) {
      return WorkoutActivityType.cycling;
    }
    if (_matchesRowing(name)) return WorkoutActivityType.cardio;
    if (_matchesYoga(name)) return WorkoutActivityType.yoga;
    return WorkoutActivityType.cardio;
  }

  static const List<String> _runKeywords = [
    'run',
    'running',
    'jog',
    'jogging',
    'treadmill',
  ];

  static const List<String> _cyclingKeywords = [
    'cycle',
    'cycling',
    'ride',
    'riding',
    'bike',
    'biking',
    'bicycle',
    'spin',
    'spinning',
  ];

  static const List<String> _yogaKeywords = ['yoga'];

  static const List<String> _hiitKeywords = ['hiit'];

  static const List<String> _rowKeywords = ['row', 'rowing', 'rower', 'erg'];

  bool _matchesRun(String value) => _hasKeyword(value, _runKeywords);

  bool _matchesCycling(String value) => _hasKeyword(value, _cyclingKeywords);

  bool _matchesYoga(String value) => _hasKeyword(value, _yogaKeywords);

  bool _matchesHiit(String value) => _hasKeyword(value, _hiitKeywords);

  bool _matchesRowing(String value) => _hasKeyword(value, _rowKeywords);

  bool _hasKeyword(String value, List<String> keywords) {
    final normalized = _normalizeForKeywordMatching(value);
    if (normalized.isEmpty) {
      return false;
    }
    for (final keyword in keywords) {
      final escaped = RegExp.escape(keyword);
      final boundaryPattern = '\\b$escaped\\b';
      final regex = keyword.contains(' ')
          ? RegExp(escaped)
          : RegExp(boundaryPattern);
      if (regex.hasMatch(normalized)) {
        return true;
      }
    }
    return false;
  }

  String _normalizeForKeywordMatching(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final separatedCamelCase = trimmed.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match[1]} ${match[2]}',
    );

    final separatedDigits = separatedCamelCase
        .replaceAllMapped(
          RegExp(r'([A-Za-z])([0-9])'),
          (match) => '${match[1]} ${match[2]}',
        )
        .replaceAllMapped(
          RegExp(r'([0-9])([A-Za-z])'),
          (match) => '${match[1]} ${match[2]}',
        );

    final replacedDelimiters = separatedDigits.replaceAll(
      RegExp(r'[_\-/]+'),
      ' ',
    );

    final collapsedWhitespace = replacedDelimiters
        .replaceAll(RegExp('[^\\w\\s]+'), ' ')
        .replaceAll(RegExp('\\s+'), ' ')
        .trim();

    return collapsedWhitespace.toLowerCase();
  }

  double? _estimateEnergy(WorkoutSession session) {
    final total = session.exercises
        .expand((ex) => ex.sets)
        .where((set) => set.isCompleted)
        .map(_estimateSetEnergy)
        .nonNulls
        .sum;
    if (total <= 0) return null;
    return double.parse(total.toStringAsFixed(1));
  }

  double? _estimateSetEnergy(WorkoutSet set) {
    if (set.weight <= 0 || set.reps <= 0) return null;
    // Simple heuristic: heavier sets burn slightly more energy.
    final energy = (set.weight * set.reps) * 0.005;
    if (energy <= 0) return null;
    return energy;
  }
}
