part of 'set_row_controller.dart';

extension SetRowControllerSync on SetRowController {
  void updateFromWidget({
    required WorkoutSet set,
    required WorkoutSet? previousSet,
    required ExerciseKind exerciseKind,
    required ExerciseLoggingMode loggingMode,
  }) {
    final oldSet = _set;
    _set = set;
    _previousSet = previousSet;
    _exerciseKind = exerciseKind;
    _loggingMode = loggingMode;

    if (oldSet == set) return;

    final nextWeightConfirmed = SetRowStateLogic.isWeightExplicit(
      isDurationOnly: isDurationOnly,
      isCompleted: set.isCompleted,
      weight: set.weight,
      wasConfirmed: _weightConfirmed,
    );
    final nextRepsConfirmed = SetRowStateLogic.isRepsExplicit(
      isCompleted: set.isCompleted,
      reps: set.reps,
      wasConfirmed: _repsConfirmed,
    );

    SetRowStateLogic.syncNumericController<double>(
      controller: weightController,
      focusNode: weightFocusNode,
      newValue: set.weight,
      fallbackValue: isDurationOnly ? null : previousSet?.weight,
      isDurationOnly: isDurationOnly,
      isConfirmed: nextWeightConfirmed,
    );

    if (usesDurationField) {
      _updateRepsForCardio(
        isConfirmed: nextRepsConfirmed,
        newValue: set.reps,
        fallbackValue: previousSet?.reps,
      );
      repsController.clear();
    } else {
      SetRowStateLogic.syncNumericController<int>(
        controller: repsController,
        focusNode: repsFocusNode,
        newValue: set.reps,
        fallbackValue: previousSet?.reps,
        isDurationOnly: isDurationOnly,
        isConfirmed: nextRepsConfirmed,
      );
    }

    _weightConfirmed = nextWeightConfirmed;
    _repsConfirmed = nextRepsConfirmed;
    _durationDraftEdited = false;
    _applyWeightPlaceholderIfNeeded();
    _notify();
  }

  void _initializeControllers() {
    final prevWeight = _previousSet?.weight;
    final prevReps = _previousSet?.reps;

    final hasExplicitWeight = SetRowStateLogic.isWeightExplicit(
      isDurationOnly: isDurationOnly,
      isCompleted: _set.isCompleted,
      weight: _set.weight,
      wasConfirmed: false,
    );
    final hasExplicitReps = SetRowStateLogic.isRepsExplicit(
      isCompleted: _set.isCompleted,
      reps: _set.reps,
      wasConfirmed: false,
    );

    final initialWeight = isDurationOnly
        ? 0.0
        : hasExplicitWeight
        ? _set.weight
        : (prevWeight ?? 0.0);
    final initialReps = hasExplicitReps ? _set.reps : (prevReps ?? 0);

    final shouldClearWeight =
        !hasExplicitWeight &&
        !isDurationOnly &&
        _set.weight.abs() == 0 &&
        (_previousSet == null || _previousSet!.weight == 0);
    if (shouldClearWeight) {
      weightController.clear();
    } else {
      // Trim the noise: `92.0` -> `92`, `62.5` -> `62.5` (matches the Previous
      // column + avoids the trailing `.0` clipping against the `kg` suffix).
      weightController.text = NumberFormatUtil.formatWeight(initialWeight);
    }

    if (usesDurationField) {
      _cardioDraftSeconds = hasExplicitReps ? _set.reps : _previousSet?.reps;
      repsController.clear();
    } else if (!hasExplicitReps &&
        _set.reps == 0 &&
        (_previousSet == null || _previousSet!.reps == 0)) {
      repsController.clear();
    } else {
      repsController.text = initialReps.toString();
    }

    _weightConfirmed = hasExplicitWeight;
    _repsConfirmed = hasExplicitReps;
    _durationDraftEdited = false;
    _applyWeightPlaceholderIfNeeded();
  }

  void _applyWeightPlaceholderIfNeeded() {
    if (isDurationOnly || isCompleted) return;
    if (_weightConfirmed) return;
    final prevWeight = _previousSet?.weight ?? 0.0;
    if (prevWeight.abs() > 0) return;
    weightController.clear();
  }

  void _syncConfirmationFromSet(WorkoutSet set) {
    _weightConfirmed = SetRowStateLogic.isWeightExplicit(
      isDurationOnly: isDurationOnly,
      isCompleted: set.isCompleted,
      weight: set.weight,
      wasConfirmed: _weightConfirmed,
    );
    _repsConfirmed = SetRowStateLogic.isRepsExplicit(
      isCompleted: set.isCompleted,
      reps: set.reps,
      wasConfirmed: _repsConfirmed,
    );
  }

  void _updateRepsForCardio({
    required bool isConfirmed,
    required int newValue,
    required int? fallbackValue,
  }) {
    if (repsFocusNode.hasFocus) return;
    final currentSecs = _cardioDraftSeconds ?? 0;
    final nextValue = SetRowStateLogic.resolveCardioDraftSeconds(
      currentSecs: currentSecs,
      newValue: newValue,
      fallbackValue: fallbackValue,
      isConfirmed: isConfirmed,
    );
    _cardioDraftSeconds = nextValue;
  }
}
