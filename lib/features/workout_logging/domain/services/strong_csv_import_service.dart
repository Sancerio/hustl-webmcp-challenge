import 'package:csv/csv.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/workout_session.dart';
import '../models/workout_exercise.dart';
import '../models/workout_set.dart';
import '../../../exercise_library/domain/repositories/exercise_repository.dart';
import '../../../exercise_library/domain/models/exercise.dart';
import 'workout_history_importer.dart';

class StrongCsvImportResult {
  final List<WorkoutSession> sessions;
  final List<String> warnings;
  const StrongCsvImportResult({required this.sessions, required this.warnings});
}

/// Parses Strong app CSV exports into Hustl workout sessions
class StrongCsvImportService implements WorkoutHistoryImporter {
  @override
  String get sourceName => 'Strong';

  StrongCsvImportService({ExerciseRepository? exerciseRepository})
    : _uuid = const Uuid(),
      _exerciseRepository =
          exerciseRepository ?? GetIt.instance<ExerciseRepository>();

  final Uuid _uuid;
  final ExerciseRepository _exerciseRepository;
  static final _failurePattern = RegExp(
    r'^f(ail(ure)?)?$',
    caseSensitive: false,
  );
  static final _warmupPattern = RegExp(r'^w(arm-?up)?$', caseSensitive: false);
  static final _supersetPattern = RegExp(
    r'^(s|ss|super( ?set)?)$',
    caseSensitive: false,
  );

  /// Input can be raw CSV string bytes or decoded text
  @override
  Future<StrongCsvImportResult> parse(String csvText) async {
    // Strong Android exports can be semicolon-delimited. Detect delimiter.
    final delimiter = _detectDelimiter(csvText);
    final converter = CsvToListConverter(eol: '\n', fieldDelimiter: delimiter);
    final rows = converter.convert(csvText, shouldParseNumbers: false);
    if (rows.isEmpty) {
      return const StrongCsvImportResult(
        sessions: [],
        warnings: ['CSV is empty'],
      );
    }

    // Expect Strong header
    final header = rows.first.map((c) => (c ?? '').toString().trim()).toList();
    final dateIdx = header.indexOf('Date');
    final workoutNameIdx = header.indexOf('Workout Name');
    // Some exports use "Duration (sec)"
    final durationIdx = header.contains('Duration')
        ? header.indexOf('Duration')
        : header.indexOf('Duration (sec)');
    final exerciseNameIdx = header.indexOf('Exercise Name');
    final setOrderIdx = header.indexOf('Set Order');
    // Some exports use "Weight (kg)"
    final weightIdx = header.contains('Weight')
        ? header.indexOf('Weight')
        : header.indexOf('Weight (kg)');
    final repsIdx = header.indexOf('Reps');
    final notesIdx = header.indexOf('Notes');
    final workoutNotesIdx = header.indexOf('Workout Notes');
    final rpeIdx = header.indexOf('RPE');

    final requiredCols = {
      'Date': dateIdx,
      'Workout Name': workoutNameIdx,
      'Exercise Name': exerciseNameIdx,
      'Set Order': setOrderIdx,
      'Reps': repsIdx,
    };
    final missing = requiredCols.entries
        .where((e) => e.value == -1)
        .map((e) => e.key)
        .toList();
    if (missing.isNotEmpty) {
      return StrongCsvImportResult(
        sessions: const [],
        warnings: ['Missing required columns: ${missing.join(', ')}'],
      );
    }

    // Build exercise lookup for faster mapping
    final allExercises = await _exerciseRepository.getAllExercises();
    final Map<String, Exercise> byName = {
      for (final e in allExercises) e.name.toLowerCase(): e,
    };

    // Group by (date start, workout name)
    final Map<String, List<List<dynamic>>> groupMap = {};
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;
      final dateStr = _safeString(row, dateIdx);
      final workoutName = _safeString(row, workoutNameIdx, fallback: 'Workout');
      final key = '$dateStr::$workoutName';
      (groupMap[key] ??= []).add(row);
    }

    final List<WorkoutSession> sessions = [];
    final List<String> warnings = [];

    for (final entry in groupMap.entries) {
      final firstRow = entry.value.first;
      final dateStr = _safeString(firstRow, dateIdx);
      final workoutName = _safeString(
        firstRow,
        workoutNameIdx,
        fallback: 'Workout',
      );
      final workoutNotes = workoutNotesIdx != -1
          ? _safeString(firstRow, workoutNotesIdx)
          : null;
      final startTime = _parseStrongDate(dateStr);

      // Group inside by exercise name
      final Map<String, List<List<dynamic>>> byExercise = {};
      for (final row in entry.value) {
        final exName = _safeString(row, exerciseNameIdx);
        if (exName.isEmpty) continue;
        final setOrderRaw = _safeString(row, setOrderIdx).toLowerCase();
        // Skip Strong's inline timer rows
        if (setOrderRaw == 'rest timer' ||
            exName.toLowerCase() == 'rest timer') {
          continue;
        }
        (byExercise[exName] ??= []).add(row);
      }

      final List<WorkoutExercise> workoutExercises = [];

      for (final exEntry in byExercise.entries) {
        final exNameRaw = exEntry.key;
        final exLookupKey = exNameRaw.toLowerCase();
        final resolved =
            byName[exLookupKey] ??
            Exercise(name: exEntry.key, muscles: const []);
        if (byName[exLookupKey] == null) {
          warnings.add('Unmatched exercise: "$exNameRaw"');
        }
        // Keep CSV order; some rows have non-numeric order like 'F' or 'Rest Timer'

        final sets = <WorkoutSet>[];
        for (final row in exEntry.value) {
          final weight = weightIdx != -1
              ? (double.tryParse(_safeString(row, weightIdx)) ?? 0.0)
              : 0.0;
          final reps = _parseInt(_safeString(row, repsIdx)) ?? 0;
          final rpe = rpeIdx != -1 ? _parseInt(_safeString(row, rpeIdx)) : null;
          final notes = notesIdx != -1 ? _safeString(row, notesIdx) : null;
          // Seconds column is currently unused
          // Mark imported sets as completed at session day if reps > 0
          final isCompleted = reps > 0;

          // Map Strong special set markers to set type
          final orderText = _safeString(row, setOrderIdx).trim();
          final SetType setType;
          if (_failurePattern.hasMatch(orderText)) {
            setType = SetType.failure;
          } else if (_warmupPattern.hasMatch(orderText)) {
            setType = SetType.warmup;
          } else if (_supersetPattern.hasMatch(orderText)) {
            setType = SetType.superset;
          } else {
            setType = SetType.regular;
          }

          sets.add(
            WorkoutSet(
              id: _uuid.v4(),
              weight: weight,
              reps: reps,
              rpe: rpe,
              setType: setType,
              notes: notes?.isEmpty == true ? null : notes,
              isCompleted: isCompleted,
              completedAt: isCompleted ? startTime : null,
              // PR flag will be computed post-import by repository recompute step
              isPr: false,
            ),
          );
        }

        workoutExercises.add(
          WorkoutExercise(id: _uuid.v4(), exercise: resolved, sets: sets),
        );
      }

      // Parse duration if present to estimate endTime
      DateTime? endTime;
      if (durationIdx != -1) {
        endTime = _applyDuration(startTime, _safeString(firstRow, durationIdx));
      }

      sessions.add(
        WorkoutSession(
          id: _uuid.v4(),
          name: workoutName,
          startTime: startTime,
          endTime: endTime ?? startTime,
          exercises: workoutExercises,
          notes: (workoutNotes?.isEmpty ?? true) ? null : workoutNotes,
          isCompleted: true,
        ),
      );
    }

    // Sort sessions by start time ascending
    sessions.sort((a, b) => a.startTime.compareTo(b.startTime));
    return StrongCsvImportResult(sessions: sessions, warnings: warnings);
  }

  String _safeString(List row, int idx, {String fallback = ''}) {
    if (idx < 0 || idx >= row.length) return fallback;
    final v = row[idx];
    return (v == null ? fallback : v.toString().trim());
  }

  DateTime _parseStrongDate(String dateStr) {
    // Strong example: 2023-09-01 10:34:00
    try {
      final parts = dateStr.split(' ');
      final date = parts[0].split('-').map(int.parse).toList();
      final time = parts.length > 1
          ? parts[1].split(':').map(int.parse).toList()
          : [0, 0, 0];
      return DateTime(
        date[0],
        date[1],
        date[2],
        time[0],
        time[1],
        time.length > 2 ? time[2] : 0,
      );
    } catch (_) {
      return DateTime.now();
    }
  }

  DateTime _applyDuration(DateTime start, String durationText) {
    // Formats like "1h 14m", "45m", "37m"
    int hours = 0;
    int minutes = 0;
    int seconds = 0;
    final tokens = durationText.split(' ');
    for (final t in tokens) {
      final v = int.tryParse(t.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (t.contains('h')) hours = v;
      if (t.contains('m')) minutes = v;
      if (t.contains('s')) seconds = v;
    }
    return start.add(
      Duration(hours: hours, minutes: minutes, seconds: seconds),
    );
  }

  int? _parseInt(String raw) {
    if (raw.isEmpty) return null;
    // Handle numbers that may come as floats like "9.0"
    final asInt = int.tryParse(raw);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(raw);
    if (asDouble != null) return asDouble.round();
    return null;
  }

  String _detectDelimiter(String text) {
    // Inspect first non-empty line for common delimiters
    final firstLine = text
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return ',';
    final comma = _count(firstLine, ',');
    final semicolon = _count(firstLine, ';');
    final tab = _count(firstLine, '\t');
    if (semicolon >= comma && semicolon >= tab) return ';';
    if (tab >= comma && tab >= semicolon) return '\t';
    return ',';
  }

  int _count(String s, String ch) => '\n$s\n'.split(ch).length - 1;
}

/// Builds Strong-compatible CSV exports from Hustl workout sessions.
class StrongCsvExportService {
  static const List<String> header = [
    'Date',
    'Workout Name',
    'Duration',
    'Exercise Name',
    'Set Order',
    'Weight (kg)',
    'Reps',
    'Distance',
    'Distance Unit',
    'RPE',
    'Notes',
    'Workout Notes',
  ];

  static final DateFormat _strongDateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
  static final DateFormat _fileDateFormat = DateFormat('yyyyMMdd');

  String fileName({DateTime? now}) {
    final date = (now ?? DateTime.now()).toLocal();
    return 'hustl-workouts-${_fileDateFormat.format(date)}.csv';
  }

  String buildCsv(List<WorkoutSession> sessions) {
    final stableSessions = [...sessions]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final rows = <List<String>>[header];

    for (final session in stableSessions) {
      final date = _strongDateFormat.format(session.startTime.toLocal());
      final duration = _formatDuration(session);
      final workoutNotes = session.notes ?? '';

      for (final workoutExercise in session.exercises) {
        final exerciseName = workoutExercise.exercise.name;
        final mode = workoutExercise.exercise.loggingMode;
        for (int i = 0; i < workoutExercise.sets.length; i++) {
          final set = workoutExercise.sets[i];

          String weightKg = '';
          String reps = '';
          String distance = '';
          String distanceUnit = '';

          switch (mode) {
            case ExerciseLoggingMode.weightReps:
              weightKg = _formatNumber(set.weight);
              reps = set.reps.toString();
              break;
            case ExerciseLoggingMode.distanceDuration:
              distance = _formatNumber(set.weight);
              distanceUnit = 'km';
              reps = set.reps.toString();
              break;
            case ExerciseLoggingMode.durationOnly:
              reps = set.reps.toString();
              break;
          }

          rows.add([
            date,
            session.name,
            duration,
            exerciseName,
            (i + 1).toString(),
            weightKg,
            reps,
            distance,
            distanceUnit,
            set.rpe?.toString() ?? '',
            set.notes ?? '',
            workoutNotes,
          ]);
        }
      }
    }

    return const ListToCsvConverter(eol: '\n').convert(rows);
  }

  String _formatDuration(WorkoutSession session) {
    final endTime = session.endTime;
    if (endTime == null) return '';
    final delta = endTime.difference(session.startTime);
    if (delta.isNegative) return '';

    final hours = delta.inHours;
    final minutes = delta.inMinutes.remainder(60);
    if (hours <= 0) return '${delta.inMinutes}m';
    return '${hours}h ${minutes}m';
  }

  String _formatNumber(double value) {
    final fixed = value.toStringAsFixed(3);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
