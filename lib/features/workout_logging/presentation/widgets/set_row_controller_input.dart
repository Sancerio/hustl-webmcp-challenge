part of 'set_row_controller.dart';

extension SetRowControllerInput on SetRowController {
  void handleWeightTap() {
    _isEditingWeight = true;
    if (isWeightPlaceholder) {
      weightController.value = const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
      return;
    }
    weightController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: weightController.text.length,
    );
  }

  void handleWeightChanged(String value) {
    if (!_weightConfirmed && value.trim().isNotEmpty) {
      _weightConfirmed = true;
      _notify();
    }
  }

  void handleDurationChanged(int? seconds) {
    // Opening the duration keypad marks reps as editing, but only an actual
    // value callback makes the previous-session fallback an intentional draft.
    // Keep those states separate so tapping W/F on an untouched Time field
    // cannot promote the ghost duration into the new set.
    _durationDraftEdited = true;
    if (_cardioDraftSeconds == seconds) return;
    _cardioDraftSeconds = seconds;
    final wasEditing = _isEditingReps;
    _isEditingReps = true;
    // Avoid rebuilding the whole row on every digit; the DurationField manages
    // its own text controller while focused.
    if (!wasEditing) {
      _notify();
    }
  }

  void handleDurationFocusChanged(bool focused) {
    if (!focused || _isEditingReps) return;
    _isEditingReps = true;
    _notify();
  }

  void handleDurationTap() {
    if (_isEditingReps) return;
    _isEditingReps = true;
    _notify();
  }

  void handleRepsTap() {
    _isEditingReps = true;
    if (isRepsPlaceholder) {
      repsController.value = const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
      return;
    }
    repsController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: repsController.text.length,
    );
  }

  void handleRepsChanged(String value) {
    if (!_repsConfirmed && value.trim().isNotEmpty) {
      _repsConfirmed = true;
      _notify();
    }

    if (value.isNotEmpty) return;

    final reinstate = _previousSet == null ? '' : _previousSet!.reps.toString();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isDisposed) return;
      // The user may have continued typing since this callback was scheduled.
      if (repsController.text.isNotEmpty) return;
      repsController
        ..text = reinstate
        ..selection = TextSelection.collapsed(offset: reinstate.length);
      _notify();
    });
  }
}
