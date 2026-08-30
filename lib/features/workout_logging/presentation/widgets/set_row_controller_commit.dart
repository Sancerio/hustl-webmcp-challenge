part of 'set_row_controller.dart';

extension SetRowControllerCommit on SetRowController {
  SetRowPersistEvent handleWeightEditingComplete() {
    _suppressWeightBlurOnce = true;

    if (isCompleted) {
      final completed = completeSet();
      return SetRowPersistEvent.completed(completed);
    }

    _weightConfirmed = true;
    _notify();
    return SetRowPersistEvent.updated(buildUpdatedSet());
  }

  ({WorkoutSet updated, WorkoutSet completed}) handleDurationEditingComplete(
    int? seconds,
  ) {
    _suppressRepsBlurOnce = true;
    final effectiveSeconds = seconds ?? 0;

    _cardioDraftSeconds = effectiveSeconds;
    _notify();

    final updated = buildUpdatedSet().copyWith(reps: effectiveSeconds);
    final completed = completeSet(setOverride: updated);
    return (updated: updated, completed: completed);
  }

  ({WorkoutSet updated, WorkoutSet completed}) handleRepsEditingComplete() {
    _suppressRepsBlurOnce = true;
    final updated = buildUpdatedSet();
    final completed = completeSet(setOverride: updated);
    return (updated: updated, completed: completed);
  }

  /// Persist the in-progress draft WITHOUT completing the set. The custom
  /// keyboard's read-only fields never lose focus, so [handleFocusChange]'s
  /// blur-save never fires; the host calls this when the keyboard re-targets to
  /// another field, the user taps outside, or leaves. Mirrors the persist branch
  /// of [handleFocusChange]: only persists a field that was actually edited and
  /// whose value differs from the stored set.
  /// The would-be blur-save (placeholder-respecting), computed WITHOUT mutating
  /// state or notifying. For the dispose/teardown path: the owning row is being
  /// removed (swiped, deleted, or scrolled far enough to virtualize) while the
  /// keyboard is open, and a `_notify()` / `onSetUpdated` during the parent's
  /// build would assert — so the caller computes this synchronously (controllers
  /// still alive) and persists it after the frame. Returns null when nothing was
  /// edited or the draft equals the stored set.
  WorkoutSet? pendingCommitSet() {
    if (!_isEditingWeight && !_isEditingReps) return null;
    final updated = draftRespectingPlaceholders();
    if (updated.weight == _set.weight && updated.reps == _set.reps) return null;
    return updated;
  }

  SetRowPersistEvent? commitDraft() {
    if (!_isEditingWeight && !_isEditingReps) return null;

    // Use the placeholder-respecting build (same guard as setRpe): opening the
    // keyboard only to pick an RPE marks _isEditingReps but must NOT promote the
    // prefilled previous-session weight/reps into a logged value.
    final updated = draftRespectingPlaceholders();
    _isEditingWeight = false;
    _isEditingReps = false;

    if (updated.weight == _set.weight && updated.reps == _set.reps) {
      return null;
    }

    if (isCompleted) {
      final completed = completeSet(setOverride: updated);
      return SetRowPersistEvent.completed(completed);
    }

    _set = updated;
    _notify();
    return SetRowPersistEvent.updated(updated);
  }

  SetRowPersistEvent? handleFocusChange() {
    final lostWeight = !weightFocusNode.hasFocus;
    final lostReps = !repsFocusNode.hasFocus;
    if (!(lostWeight || lostReps)) return null;

    if (lostWeight && _suppressWeightBlurOnce) {
      _suppressWeightBlurOnce = false;
      return null;
    }
    if (lostReps && _suppressRepsBlurOnce) {
      _suppressRepsBlurOnce = false;
      return null;
    }

    if (lostWeight && repsFocusNode.hasFocus) return null;
    if (lostReps && weightFocusNode.hasFocus) return null;

    final updated = buildUpdatedSet();
    final shouldPersist =
        (lostWeight && _isEditingWeight) ||
        (lostReps && _isEditingReps) ||
        updated.weight != _set.weight ||
        updated.reps != _set.reps;
    if (!shouldPersist) return null;

    if (updated.weight == _set.weight && updated.reps == _set.reps) {
      return null;
    }

    if (lostWeight) _isEditingWeight = false;
    if (lostReps) _isEditingReps = false;

    if (isCompleted) {
      final completed = completeSet(setOverride: updated);
      return SetRowPersistEvent.completed(completed);
    }

    // Persist in-progress edits without changing completion state.
    _set = updated;
    return SetRowPersistEvent.updated(updated);
  }
}
