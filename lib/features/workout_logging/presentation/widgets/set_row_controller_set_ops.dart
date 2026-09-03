part of 'set_row_controller.dart';

extension SetRowControllerSetOps on SetRowController {
  WorkoutSet completeSet({WorkoutSet? setOverride}) {
    final base = setOverride ?? buildUpdatedSet();
    final completed = base.copyWith(isCompleted: true);
    _set = completed;
    _syncConfirmationFromSet(completed);
    _notify();
    return completed;
  }

  WorkoutSet uncompleteSet() {
    final updated = buildUpdatedSet(isCompleted: false, isPr: false);
    _set = updated;
    _notify();
    return updated;
  }

  WorkoutSet changeSetType(SetType type) {
    // Preserve any weight/reps the user has typed into the custom keypad but
    // has not completed yet. Previous-session placeholders remain excluded by
    // draftRespectingPlaceholders, so changing type alone never logs history as
    // a new value.
    var updated = draftRespectingPlaceholders().copyWith(setType: type);
    // Failure == RIR 0 (no reps left): typing a set to failure logs RIR 0 in the
    // SAME mutation so type and effort persist together (the keyboard F shortcut
    // relies on this being atomic — a separate RPE write would race the type).
    if (type == SetType.failure) {
      updated = updated.copyWith(rpe: EffortScale.rpeFromRir(0));
    }
    _set = updated;
    _notify();
    return updated;
  }

  /// Set or clear the optional RPE (pass null to clear). RPE should not promote
  /// untouched previous-set placeholders into real draft values.
  WorkoutSet setRpe(int? value) {
    final updated = draftRespectingPlaceholders().copyWith(rpe: value);
    _set = updated;
    _notify();
    return updated;
  }

  /// Build the set from the field drafts, but only promote a field the user
  /// actually entered — never a faint prefill or placeholder (previous-session
  /// value). Shared by [setRpe] and the keyboard blur-save (`commitDraft`) so
  /// neither path can log a previous-session value when the user only opened the
  /// keyboard to pick an RPE.
  WorkoutSet draftRespectingPlaceholders() {
    final useWeightDraft =
        (_weightConfirmed || _isEditingWeight) &&
        !isWeightPrefilled &&
        !isWeightPlaceholder;
    final hasIntentionalRepsDraft = usesDurationField
        ? (_repsConfirmed || _durationDraftEdited)
        : (_repsConfirmed || _isEditingReps);
    final useRepsDraft =
        hasIntentionalRepsDraft &&
        !isRepsPrefilled &&
        !isRepsPlaceholder;
    return _set
        .copyWith(weight: useWeightDraft ? _parseWeight() : _set.weight)
        .copyWith(reps: useRepsDraft ? _parseReps() : _set.reps);
  }

  /// Compact last-session value for the "Previous" column. Kept tight so it
  /// reads in a narrow column on small phones:
  /// - weight×reps   -> "60 kg × 10"
  /// - distance+time -> "5 · 01:30"  (mid-dot separator; the unit lives in the
  ///   "km" header, so it is dropped here to avoid a cramped column)
  /// - duration only -> "01:30"
  /// - no previous   -> "-"
  ///
  /// The visible [Text] is read by screen readers, so this doubles as the row's
  /// accessible previous-value summary — no separate Semantics node is needed.
  String previousSetLabel() {
    final prev = _previousSet;
    if (prev == null) return '-';
    if (isDurationOnly) return TimeFormatUtil.formatMmSs(prev.reps);
    if (isDistanceDuration) {
      return '${NumberFormatUtil.formatWeight(prev.weight)} · '
          '${TimeFormatUtil.formatMmSs(prev.reps)}';
    }
    // Keep the sign: assisted exercises store assistance as a negative weight,
    // and the field ghost shows it signed ("-20.0"), so the Previous label must
    // match (e.g. "-20 kg × 10") rather than misstate it as a positive load.
    return '${NumberFormatUtil.formatWeight(prev.weight)} kg × ${prev.reps}';
  }

  /// True once the row carries any user-driven entry: a confirmed/edited draft
  /// in either field, or an already-logged value. Drives whether the
  /// progressive-overload hint may show — it only appears on a still-empty row,
  /// and hides the moment the user (or an accepted suggestion) fills a field.
  bool get hasUserEntry =>
      _weightConfirmed ||
      _repsConfirmed ||
      _isEditingWeight ||
      _isEditingReps ||
      _set.hasLoggedValue;

  /// Fill the weight/reps fields from an accepted next-set suggestion, exactly
  /// as if the user had typed them: the values become confirmed drafts awaiting
  /// the completion tap. It NEVER completes the set and never writes through to
  /// the persisted set on its own — the normal completion/blur path commits the
  /// draft, so an accepted suggestion behaves identically to typed input.
  void applySuggestion({required double weightKg, required int reps}) {
    final weightText = NumberFormatUtil.formatWeight(weightKg);
    weightController
      ..text = weightText
      ..selection = TextSelection.collapsed(offset: weightText.length);
    _weightConfirmed = true;
    _isEditingWeight = false;

    final repsText = reps.toString();
    repsController
      ..text = repsText
      ..selection = TextSelection.collapsed(offset: repsText.length);
    _repsConfirmed = true;
    _isEditingReps = false;

    _notify();
  }

  WorkoutSet buildUpdatedSet({bool? isCompleted, bool? isPr}) {
    return _set.copyWith(
      weight: _parseWeight(),
      reps: _parseReps(),
      isCompleted: isCompleted ?? _set.isCompleted,
      isPr: isPr ?? _set.isPr,
    );
  }

  double _parseWeight() {
    double weight = double.tryParse(weightController.text) ?? _set.weight;
    if (_exerciseKind == ExerciseKind.assisted && weight > 0) {
      weight = -weight;
    }
    return weight;
  }

  int _parseReps() {
    if (!usesDurationField) {
      return int.tryParse(repsController.text) ?? _set.reps;
    }

    if (_cardioDraftSeconds != null) {
      return _cardioDraftSeconds!;
    }

    // Treat a cleared duration field as an explicit 0 when reps was actively
    // edited, so blur persistence does not retain stale previous reps.
    if (_isEditingReps) {
      return 0;
    }

    return _set.reps;
  }
}
