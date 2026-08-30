import 'package:get_it/get_it.dart';

import '../../workout_logging/domain/models/workout_session.dart';
import '../../workout_logging/domain/repositories/workout_repository.dart';

/// Result of writing a parsed training history into the repository.
class ImportOutcome {
  const ImportOutcome({required this.imported, required this.replaced});

  /// Total sessions written this run.
  final int imported;

  /// Sessions that collided with an existing one (same name + start time) and
  /// were replaced rather than duplicated.
  final int replaced;

  bool get isEmpty => imported == 0;
}

/// Writes parsed [WorkoutSession]s into the [WorkoutRepository], de-duplicating
/// on (name + start time) so re-importing the same export replaces rather than
/// duplicates. Extracted from the settings importer so both the utilitarian
/// import screen and the onboarding switcher flow share one write path.
class WorkoutImportRunner {
  WorkoutImportRunner({WorkoutRepository? repository})
    : _repo = repository ?? GetIt.instance<WorkoutRepository>();

  final WorkoutRepository _repo;

  /// Imports [sessions], reporting progress as each one is written. Returns the
  /// total imported and how many replaced an existing session.
  Future<ImportOutcome> run(
    List<WorkoutSession> sessions, {
    void Function(int done, int total)? onProgress,
  }) async {
    final total = sessions.length;
    if (total == 0) {
      return const ImportOutcome(imported: 0, replaced: 0);
    }

    final existing = await _repo.getWorkoutSessions();
    final Map<String, WorkoutSession> keyToExisting = {
      for (final s in existing) keyFor(s): s,
    };

    int imported = 0;
    int replaced = 0;
    int processed = 0;

    for (final s in sessions) {
      final key = keyFor(s);
      final prior = keyToExisting[key];
      if (prior != null) {
        await _repo.deleteWorkoutSession(prior.id);
        replaced++;
      }
      final created = await _repo.createWorkoutSession(s);
      keyToExisting[key] = created;
      imported++;
      processed++;
      onProgress?.call(processed, total);
    }

    return ImportOutcome(imported: imported, replaced: replaced);
  }

  /// Collision key: same workout name (case-insensitive) starting at the same
  /// instant is treated as the same session.
  static String keyFor(WorkoutSession s) =>
      '${s.name.trim().toLowerCase()}|${s.startTime.millisecondsSinceEpoch}';
}
