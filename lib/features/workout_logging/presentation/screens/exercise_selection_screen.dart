import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';
import '../../../exercise_library/domain/models/exercise.dart';
import '../../domain/models/workout_exercise.dart';
import '../../domain/utils/set_utils.dart';
import '../../domain/repositories/workout_repository.dart';
import '../../../exercise_library/presentation/widgets/exercise_list_screen_base.dart';
import '../../../exercise_library/presentation/widgets/custom_exercise_form.dart';
import '../../../../core/services/preferences_service.dart';
import '../../../../core/widgets/hustl_icon.dart';

class ExerciseSelectionScreen extends StatelessWidget {
  const ExerciseSelectionScreen({super.key});

  /// Builds a [WorkoutExercise] for [exercise], pulling its previous sets and
  /// saved rest timer. Shared by single-add and multi-select grouping.
  static Future<WorkoutExercise> _buildWorkoutExercise(
    Exercise exercise,
    WorkoutRepository workoutRepository,
    PreferencesService prefs,
    Uuid uuid, {
    String? supersetGroupId,
    int? supersetOrder,
  }) async {
    final previousSets = await workoutRepository.getPreviousExerciseSets(
      exercise.name,
      exerciseSlug: exercise.slug,
    );
    final savedRest = await prefs.getExerciseRestTimer(exercise.name);
    // Seed only top-level working sets — exclude linked drops (dropset rows with
    // a parentSetId) so a fresh workout never inherits orphan drops that would be
    // counted/labelled/rested as standalone sets. Drops are recreated by the user.
    final workingSetCount =
        previousSets?.where((s) => s.parentSetId == null).length ?? 0;
    final setCount = workingSetCount > 0 ? workingSetCount : 1;
    return WorkoutExercise(
      id: uuid.v4(),
      exercise: exercise,
      sets: generateEmptySets(setCount, uuid, previousSets: previousSets),
      previousSessionSets: previousSets,
      restTimerSeconds: savedRest,
      supersetGroupId: supersetGroupId,
      supersetOrder: supersetOrder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final workoutRepository = GetIt.instance<WorkoutRepository>();
    final prefs = GetIt.instance<PreferencesService>();
    const uuid = Uuid();
    final router = GoRouter.of(context);
    return ExerciseListScreenBase(
      appBarTitle: 'Select Exercise',
      allowFilters: true,
      allowMultiSelect: true,
      onMultiSelectConfirm: (context, exercises) async {
        final r = GoRouter.of(context);
        // One shared group id; supersetOrder follows selection order.
        final groupId = uuid.v4();
        final built = <WorkoutExercise>[];
        for (var i = 0; i < exercises.length; i++) {
          built.add(
            await _buildWorkoutExercise(
              exercises[i],
              workoutRepository,
              prefs,
              uuid,
              supersetGroupId: groupId,
              supersetOrder: i,
            ),
          );
        }
        if (r.canPop()) {
          r.pop(built);
        }
      },
      // This screen is always pushed (over /exercise_select), so the adaptive
      // HustlMenuButton renders a back button — consistent with the rest of the
      // app instead of a bare hardcoded Material arrow.
      showMenuButton: true,
      appBarTrailing: IconButton(
        icon: HustlIcon(
          asset: 'assets/icons/ic_add.svg',
          size: 24,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        tooltip: 'Create Custom',
        onPressed: () async {
          final created = await showCustomExerciseForm(context);
          if (created == null) return;
          final workoutExercise = await _buildWorkoutExercise(
            created,
            workoutRepository,
            prefs,
            uuid,
          );
          if (router.canPop()) {
            router.pop(workoutExercise);
          }
        },
      ),
      onExerciseTap: (context, exercise) async {
        // Capture router before async gap
        final r = GoRouter.of(context);
        final workoutExercise = await _buildWorkoutExercise(
          exercise,
          workoutRepository,
          prefs,
          uuid,
        );
        if (r.canPop()) {
          r.pop(workoutExercise);
        }
      },
    );
  }
}
