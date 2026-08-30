import '../../../features/exercise_library/domain/models/exercise.dart';
import '../../../features/workout_logging/domain/next_incomplete_exercise.dart';
import '../../../features/workout_logging/domain/models/workout_exercise.dart';
import '../../../features/workout_logging/domain/models/workout_session.dart';
import '../../../features/workout_logging/domain/models/workout_set.dart';
import '../../utils/time_format_util.dart';
import '../../utils/number_format_util.dart';

class WatchBridgeResolvedSelection {
  const WatchBridgeResolvedSelection({
    required this.selectedExerciseId,
    required this.exercise,
    required this.nextIncompleteSetIndex,
  });

  final String selectedExerciseId;
  final WorkoutExercise exercise;
  final int? nextIncompleteSetIndex;
}

class WatchBridgeNextSuggestion {
  const WatchBridgeNextSuggestion({
    required this.name,
    required this.isNextSet,
  });

  final String? name;
  final bool isNextSet;
}

typedef WatchBridgeSetPrefill = ({double weight, int reps});

WatchBridgeResolvedSelection? resolveSelection(
  WorkoutSession session, {
  String? restExerciseId,
  String? selectedExerciseId,
}) {
  if (session.exercises.isEmpty) return null;

  final resolvedId =
      restExerciseId ??
      selectedExerciseId ??
      firstIncompleteExerciseId(session);
  final idx = session.exercises.indexWhere((e) => e.id == resolvedId);
  final exercise = idx == -1 ? session.exercises.first : session.exercises[idx];
  final nextSetIndex = exercise.sets.indexWhere((set) => !set.isCompleted);

  return WatchBridgeResolvedSelection(
    selectedExerciseId: exercise.id,
    exercise: exercise,
    nextIncompleteSetIndex: nextSetIndex == -1 ? null : nextSetIndex,
  );
}

String? firstIncompleteExerciseId(WorkoutSession session) {
  for (final exercise in session.exercises) {
    if (exercise.sets.any((s) => !s.isCompleted)) {
      return exercise.id;
    }
  }
  return session.exercises.isNotEmpty ? session.exercises.first.id : null;
}

String? nextSetSummary(WatchBridgeResolvedSelection selection) {
  final prefill = nextSetPrefill(selection);
  if (prefill == null) return null;
  return switch (selection.exercise.exercise.loggingMode) {
    ExerciseLoggingMode.distanceDuration =>
      '${_formatWeight(prefill.weight)} km × ${TimeFormatUtil.formatMmSs(prefill.reps)}',
    ExerciseLoggingMode.durationOnly => TimeFormatUtil.formatMmSs(prefill.reps),
    ExerciseLoggingMode.weightReps =>
      '${_formatWeight(prefill.weight)}×${prefill.reps}',
  };
}

WatchBridgeSetPrefill? nextSetPrefill(WatchBridgeResolvedSelection selection) {
  final index = selection.nextIncompleteSetIndex;
  if (index == null) return null;
  final WorkoutSet set = selection.exercise.sets[index];

  final previousSets = selection.exercise.previousSessionSets;
  final previousSet = (previousSets != null && previousSets.isNotEmpty)
      ? previousSets[index < previousSets.length
            ? index
            : previousSets.length - 1]
      : null;

  final hasExplicitWeight = set.isCompleted || set.weight.abs() > 0;
  final hasExplicitReps = set.isCompleted || set.reps > 0;

  final weight = hasExplicitWeight
      ? set.weight
      : (previousSet?.weight ?? set.weight);
  final reps = hasExplicitReps ? set.reps : (previousSet?.reps ?? set.reps);

  return (weight: weight, reps: reps);
}

WatchBridgeNextSuggestion nextRemainingWorkSuggestion(
  List<WorkoutExercise> exercises,
  WorkoutExercise current,
) {
  if (exercises.isEmpty) {
    return const WatchBridgeNextSuggestion(name: null, isNextSet: false);
  }

  final index = exercises.indexWhere((e) => e.id == current.id);
  if (index == -1) {
    return const WatchBridgeNextSuggestion(name: null, isNextSet: false);
  }

  final incompleteSetCount = current.sets.where((s) => !s.isCompleted).length;
  if (incompleteSetCount > 1) {
    return WatchBridgeNextSuggestion(
      name: current.exercise.name,
      isNextSet: true,
    );
  }

  for (var i = index + 1; i < exercises.length; i++) {
    if (exercises[i].sets.any((s) => !s.isCompleted)) {
      return WatchBridgeNextSuggestion(
        name: exercises[i].exercise.name,
        isNextSet: false,
      );
    }
  }

  for (var i = 0; i < index; i++) {
    if (exercises[i].sets.any((s) => !s.isCompleted)) {
      return WatchBridgeNextSuggestion(
        name: exercises[i].exercise.name,
        isNextSet: false,
      );
    }
  }

  return const WatchBridgeNextSuggestion(name: null, isNextSet: false);
}

WatchBridgeNextSuggestion nextExerciseSuggestion(
  List<WorkoutExercise> exercises,
  WorkoutExercise current,
) {
  final index = exercises.indexWhere((e) => e.id == current.id);
  if (index == -1) {
    return const WatchBridgeNextSuggestion(name: null, isNextSet: false);
  }

  final hasRemainingSets = current.sets.any((s) => !s.isCompleted);
  if (hasRemainingSets) {
    return WatchBridgeNextSuggestion(
      name: current.exercise.name,
      isNextSet: true,
    );
  }
  // Current exercise is done: surface the next exercise that still has work
  // left, skipping any following exercises that are already fully completed so
  // the notification never names an already-finished exercise.
  final nextIndex = nextIncompleteExerciseIndex(exercises, index);
  if (nextIndex != null) {
    return WatchBridgeNextSuggestion(
      name: exercises[nextIndex].exercise.name,
      isNextSet: false,
    );
  }
  return const WatchBridgeNextSuggestion(name: null, isNextSet: false);
}

String navigateExerciseId({
  required List<WorkoutExercise> exercises,
  required String currentExerciseId,
  required int delta,
}) {
  if (exercises.isEmpty) return currentExerciseId;
  final currentIndex = exercises.indexWhere((e) => e.id == currentExerciseId);
  if (currentIndex == -1) return exercises.first.id;

  final nextIndex = (currentIndex + delta) % exercises.length;
  return exercises[nextIndex < 0 ? exercises.length - 1 : nextIndex].id;
}

String _formatWeight(double value) {
  if (!value.isFinite) return '0';
  return NumberFormatUtil.formatWeight(value);
}

/// Returns a URL that the watch extension can fetch (http/https), or `null` when
/// the provided URL is empty or points to a Flutter asset (`assets/...`).
///
/// If [rawUrl] is relative (e.g. `/images/x.png`), it is resolved against
/// [baseUrl] (typically `ApiConfig.baseUrl`).
String? resolveWatchImageUrl(String? rawUrl, {required String baseUrl}) {
  final trimmed = rawUrl?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (trimmed.startsWith('assets/')) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (uri.hasScheme) return trimmed;

  final base = Uri.tryParse(baseUrl);
  if (base == null || !base.hasScheme) return trimmed;
  return base.resolve(trimmed).toString();
}
