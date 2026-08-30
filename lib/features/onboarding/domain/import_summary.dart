import '../../workout_logging/domain/models/workout_session.dart';

/// Build-ready summary of an imported training history (e.g. the sessions
/// produced by `StrongCsvImportService.parse(...)`). Used to turn the utilitarian
/// "147 sessions found" dialog into an onboarding magic moment: "your training
/// came with you — 142 workouts, 37 exercises, since Jan 2023."
class ImportSummary {
  const ImportSummary({
    required this.workouts,
    required this.exercises,
    required this.totalSets,
    required this.totalVolumeKg,
    this.firstDate,
    this.lastDate,
  });

  final int workouts;
  final int exercises;
  final int totalSets;
  final double totalVolumeKg;
  final DateTime? firstDate;
  final DateTime? lastDate;

  bool get isEmpty => workouts == 0;

  /// Tonnes lifted, the headline-friendly volume unit for a whole history.
  double get totalVolumeTonnes => totalVolumeKg / 1000.0;

  /// Computes the summary from parsed sessions. Pure — safe to run on the
  /// import result before writing anything to the repository.
  factory ImportSummary.fromSessions(List<WorkoutSession> sessions) {
    final exerciseNames = <String>{};
    var sets = 0;
    var volume = 0.0;
    DateTime? first;
    DateTime? last;

    for (final session in sessions) {
      if (first == null || session.startTime.isBefore(first)) {
        first = session.startTime;
      }
      if (last == null || session.startTime.isAfter(last)) {
        last = session.startTime;
      }
      volume += session.totalVolume;
      for (final exercise in session.exercises) {
        exerciseNames.add(exercise.exercise.name.trim().toLowerCase());
        sets += exercise.sets.length;
      }
    }

    return ImportSummary(
      workouts: sessions.length,
      exercises: exerciseNames.length,
      totalSets: sets,
      totalVolumeKg: volume,
      firstDate: first,
      lastDate: last,
    );
  }
}
