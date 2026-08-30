import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/utils/number_format_util.dart';

import '../../../exercise_library/domain/models/exercise.dart';
import '../../domain/models/workout_set.dart';
import '../../domain/services/progression_suggestion_service.dart';
import 'set_input_keyboard.dart';
import 'set_row_content.dart';
import 'set_row_controller.dart';
import 'set_row_fields.dart';
import 'set_row_layout.dart';

typedef SetTypeChangeCallback =
    void Function(WorkoutSet draft, SetType requestedType);

class SetRow extends StatefulWidget {
  final int setIndex;

  /// 1-based working-set ordinal, re-derived over non-warm-up sets only
  /// (`W W 1 2 3`). Warm-up rows ignore this and render a `W` badge.
  final int displayOrdinal;

  /// Optional override for the "Set" column (superset round labels like `A1`).
  /// Null = render the numeric [displayOrdinal]. Warm-up rows keep their `W`.
  final String? displayLabel;
  final WorkoutSet set;
  final Function(WorkoutSet) onSetUpdated;
  final Function(WorkoutSet) onSetCompleted;
  final VoidCallback? onSetDeleted;
  final Function(WorkoutSet)? onSetUncompleted;

  /// True when this row is a dropset drop (a linked sub-set). Drives the
  /// indented `tertiary` bracket + "D" badge in [SetRowContent].
  final bool isDrop;

  /// Optional interceptor for the set-type popup. When provided, the card owns
  /// the structural change (e.g. picking "Drop set" appends a child drop rather
  /// than re-typing this row; picking "Regular" on a dropset parent strips its
  /// drops). Null = legacy in-place behavior via the controller.
  final SetTypeChangeCallback? onSetTypeChanged;
  final WorkoutSet? previousSet;
  final double dismissThreshold;
  final ExerciseKind exerciseKind;
  final ExerciseLoggingMode loggingMode;
  final bool isPreviousCompleted;
  final bool isNextCompleted;

  const SetRow({
    super.key,
    required this.setIndex,
    this.displayOrdinal = 1,
    this.displayLabel,
    required this.set,
    required this.onSetUpdated,
    required this.onSetCompleted,
    this.onSetDeleted,
    this.onSetUncompleted,
    this.isDrop = false,
    this.onSetTypeChanged,
    this.previousSet,
    this.dismissThreshold = 0.35,
    this.exerciseKind = ExerciseKind.strength,
    this.loggingMode = ExerciseLoggingMode.weightReps,
    this.isPreviousCompleted = false,
    this.isNextCompleted = false,
  });

  @override
  State<SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<SetRow> {
  late final SetRowController _controller;

  // Cached (non-dependency) reference to the host's keyboard controller so
  // dispose() can detach this row's session without an inherited-widget lookup
  // on a defunct element. Null when there's no hosting screen.
  SetInputKeyboardController? _keyboard;

  // Set when this row is being intentionally deleted (swiped away). dispose()
  // then SKIPS its draft-commit — committing a deleted row's draft could
  // resurrect the set via a parent closure that still sees pre-delete state.
  bool _deleting = false;

  // Open callback for THIS row's reps field, registered by SetRowRepsField, so
  // the weight field's "Next" key can re-target the keyboard to reps.
  VoidCallback? _openRepsField;

  @override
  void initState() {
    super.initState();
    _controller = SetRowController(
      set: widget.set,
      previousSet: widget.previousSet,
      exerciseKind: widget.exerciseKind,
      loggingMode: widget.loggingMode,
    );
    _controller.weightFocusNode.addListener(_handleFocusChange);
    _controller.repsFocusNode.addListener(_handleFocusChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // read() doesn't register a dependency, so the row isn't rebuilt on every
    // keyboard open/close (the fields already handle their own highlight).
    _keyboard = SetInputKeyboardScope.read(context);
  }

  @override
  void didUpdateWidget(SetRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.updateFromWidget(
      set: widget.set,
      previousSet: widget.previousSet,
      exerciseKind: widget.exerciseKind,
      loggingMode: widget.loggingMode,
    );
  }

  @override
  void dispose() {
    // If this row owned the active set-input keyboard session, it's being torn
    // down (swiped away, removed, or scrolled far enough to virtualize) while
    // the keyboard is open. Persist any typed draft so it isn't silently lost,
    // then clear the session so the keyboard can't write through the disposed
    // controllers. The draft is computed synchronously (controllers still alive)
    // and applied after the frame — dispose can run during the parent list's
    // build, where onSetUpdated -> setState would assert; onSetUpdated no-ops if
    // the set was deleted, so a swipe-delete stays a no-op either way.
    final keyboard = _keyboard;
    if (keyboard != null) {
      final active = keyboard.active?.controller;
      final ownsActive =
          identical(active, _controller.weightController) ||
          identical(active, _controller.repsController);
      if (ownsActive) {
        // Skip the draft-commit for an intentional delete (the swipe already
        // discarded it); only a virtualized/removed-but-still-present row keeps
        // its typed draft.
        final pending = _deleting ? null : _controller.pendingCommitSet();
        keyboard
          ..detachIfActive(_controller.weightController)
          ..detachIfActive(_controller.repsController);
        if (pending != null) {
          final onUpdated = widget.onSetUpdated;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => onUpdated(pending),
          );
        }
      }
    }
    _controller.weightFocusNode.removeListener(_handleFocusChange);
    _controller.repsFocusNode.removeListener(_handleFocusChange);
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final event = _controller.handleFocusChange();
    if (event == null) return;

    switch (event.kind) {
      case SetRowPersistKind.updated:
        widget.onSetUpdated(event.set);
        return;
      case SetRowPersistKind.completed:
        widget.onSetCompleted(event.set);
        return;
    }
  }

  void _handleSetTypeSelected(SetType type) {
    // When the card owns set-type changes (dropset structural rules), hand it
    // both the selection and the latest field draft. The custom keypad keeps
    // edits in the row controller until completion, so forwarding only [type]
    // would let the card rebuild from an older zero-valued set and erase reps
    // typed immediately before W/F was tapped.
    final intercept = widget.onSetTypeChanged;
    if (intercept != null) {
      intercept(_controller.draftRespectingPlaceholders(), type);
      return;
    }
    widget.onSetUpdated(_controller.changeSetType(type));
  }

  void _handleCompletePressed() {
    final completed = _controller.completeSet();
    // The single set-completion haptic (and PR celebrate) is fired centrally in
    // ExerciseCard._onSetCompleted, which covers every completion path.
    widget.onSetCompleted(completed);
  }

  void _handleRpeSelected(int? value) {
    // RPE is orthogonal to completion: persist as a plain update so it never
    // re-fires completion haptics / rest timer / PR check.
    widget.onSetUpdated(_controller.setRpe(value));
  }

  void _handleUncompletePressed() {
    final handler = widget.onSetUncompleted;
    if (handler == null) return;
    handler(_controller.uncompleteSet());
  }

  // Accept a next-set target: fill the fields exactly as if typed (a confirmed
  // draft awaiting the completion tap — never auto-completed), then persist the
  // draft as a plain update so it survives virtualization. Both steps route
  // through the controller's existing fill/commit helpers.
  void _handleAcceptSuggestion(ProgressionSuggestion suggestion) {
    _controller.applySuggestion(
      weightKg: suggestion.weightKg,
      reps: suggestion.reps,
    );
    widget.onSetUpdated(_controller.buildUpdatedSet());
  }

  /// Whether next-set suggestions are enabled. Reads the toggle from the shared
  /// [PreferencesService]; when it is not registered (unconfigured test envs)
  /// the feature stays off so it never surfaces unexpectedly.
  bool get _suggestionsEnabled {
    if (!GetIt.instance.isRegistered<PreferencesService>()) return false;
    return GetIt.instance<PreferencesService>().suggestNextSetTargets;
  }

  /// The progressive-overload suggestion for this row, or null when it must not
  /// show: toggle off, a completed row, a warm-up / drop row, a row the user has
  /// already started, no previous set, or a set the heuristic declines.
  ProgressionSuggestion? _currentSuggestion() {
    if (!_suggestionsEnabled) return null;
    if (_controller.isCompleted) return null;
    if (widget.isDrop || widget.set.setType == SetType.warmup) return null;
    if (_controller.hasUserEntry) return null;
    final prev = widget.previousSet;
    if (prev == null) return null;
    return const ProgressionSuggestionService().suggestFromPreviousSet(
      previous: prev,
      loggingMode: widget.loggingMode,
    );
  }

  void _handleWeightEditingComplete(BuildContext context) {
    final event = _controller.handleWeightEditingComplete();

    switch (event.kind) {
      case SetRowPersistKind.updated:
        widget.onSetUpdated(event.set);
        FocusScope.of(context).nextFocus();
        return;
      case SetRowPersistKind.completed:
        widget.onSetCompleted(event.set);
        FocusScope.of(context).unfocus();
        return;
    }
  }

  void _handleRepsEditingComplete(BuildContext context) {
    final seq = _controller.handleRepsEditingComplete();

    widget.onSetUpdated(seq.updated);
    widget.onSetCompleted(seq.completed);
    FocusScope.of(context).unfocus();
  }

  // Blur-save for the custom keyboard: persist the in-progress draft (without
  // completing) when the keyboard re-targets to another field or closes.
  void _handleCommitDraft() {
    final event = _controller.commitDraft();
    if (event == null) return;
    switch (event.kind) {
      case SetRowPersistKind.updated:
        widget.onSetUpdated(event.set);
      case SetRowPersistKind.completed:
        widget.onSetCompleted(event.set);
    }
  }

  void _handleDurationEditingComplete(BuildContext context, int? seconds) {
    final seq = _controller.handleDurationEditingComplete(seconds);

    widget.onSetUpdated(seq.updated);
    widget.onSetCompleted(seq.completed);
    FocusScope.of(context).unfocus();
  }

  BorderRadius _borderRadius() {
    return BorderRadius.only(
      topLeft: (_controller.isCompleted && widget.isPreviousCompleted)
          ? Radius.zero
          : const Radius.circular(8),
      topRight: (_controller.isCompleted && widget.isPreviousCompleted)
          ? Radius.zero
          : const Radius.circular(8),
      bottomLeft: (_controller.isCompleted && widget.isNextCompleted)
          ? Radius.zero
          : const Radius.circular(8),
      bottomRight: (_controller.isCompleted && widget.isNextCompleted)
          ? Radius.zero
          : const Radius.circular(8),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Recomputed on every controller notification so the hint disappears the
        // instant the row is completed or the user (or an accepted suggestion)
        // fills a field.
        final suggestion = _currentSuggestion();
        return Dismissible(
          key: ValueKey(widget.set.id),
          direction: widget.onSetDeleted != null
              ? DismissDirection.endToStart
              : DismissDirection.none,
          movementDuration: const Duration(milliseconds: 120),
          confirmDismiss: (dir) async {
            if (dir != DismissDirection.endToStart) return false;
            if (_controller.weightFocusNode.hasFocus ||
                _controller.repsFocusNode.hasFocus) {
              FocusScope.of(context).unfocus();
            }
            return true;
          },
          dismissThresholds: {
            DismissDirection.endToStart: widget.dismissThreshold,
          },
          onDismissed: (_) {
            _deleting = true;
            FocusScope.of(context).unfocus();
            // The active row is being deleted: close the keyboard and DISCARD
            // its draft (the set is gone). _deleting also makes dispose skip its
            // draft-commit, so the just-deleted set can't be resurrected.
            final keyboard = _keyboard;
            final active = keyboard?.active?.controller;
            if (keyboard != null &&
                (identical(active, _controller.weightController) ||
                    identical(active, _controller.repsController))) {
              keyboard.close(commit: false);
            }
            widget.onSetDeleted?.call();
          },
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16.0),
            color: theme.colorScheme.error.withValues(alpha: 0.2),
            child: Icon(Icons.delete, color: theme.colorScheme.error, size: 24),
          ),
          child: RepaintBoundary(
            child: AnimatedContainer(
              duration: Duration.zero,
              curve: Curves.easeOut,
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: _controller.isCompleted
                    ? theme.colorScheme.tertiaryContainer.withValues(
                        alpha: 0.32,
                      )
                    : Colors.transparent,
                borderRadius: _borderRadius(),
              ),
              child: Stack(
                children: [
                  if (_controller.isCompleted)
                    const Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: _CompletedLeftAccent(),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      SetRowLayout.rowPadding,
                      8,
                      SetRowLayout.rowPadding,
                      8,
                    ),
                    // The "Previous" column shows last session's value (and
                    // is natively announced by screen readers as a plain Text),
                    // so no extra previous-value Semantics node is needed here.
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SetRowContent(
                          setIndex: widget.setIndex,
                          displayOrdinal: widget.displayOrdinal,
                          displayLabel: widget.displayLabel,
                          isCompleted: _controller.isCompleted,
                          setType: _controller.setType,
                          onSetTypeSelected: _handleSetTypeSelected,
                          isDrop: widget.isDrop,
                          previousSetLabel: _controller.previousSetLabel(),
                          hasPreviousSet: widget.previousSet != null,
                          weightField: _controller.isDurationOnly
                              ? null
                              : SetRowWeightField(
                                  setIndex: widget.setIndex,
                                  isDistanceDuration:
                                      _controller.isDistanceDuration,
                                  isCompleted: _controller.isCompleted,
                                  isWeightPrefilled:
                                      _controller.isWeightPrefilled,
                                  isWeightPlaceholder:
                                      _controller.isWeightPlaceholder,
                                  controller: _controller.weightController,
                                  focusNode: _controller.weightFocusNode,
                                  exerciseKind: _controller.exerciseKind,
                                  onTap: _controller.handleWeightTap,
                                  onChanged: _controller.handleWeightChanged,
                                  onEditingComplete: () =>
                                      _handleWeightEditingComplete(context),
                                  onCommit: _handleCommitDraft,
                                  // Effort badges live in the shared keyboard for
                                  // BOTH fields (constant height), so the weight
                                  // field carries the set's RPE too.
                                  rpe:
                                      _controller.loggingMode ==
                                          ExerciseLoggingMode.weightReps
                                      ? _controller.rpe
                                      : null,
                                  onRpeSelected:
                                      _controller.loggingMode ==
                                          ExerciseLoggingMode.weightReps
                                      ? _handleRpeSelected
                                      : null,
                                  // "Next" → re-target the keyboard to the second
                                  // field: reps for weight×reps, Time for cardio
                                  // distance+duration. (durationOnly has no distance
                                  // field, so it needs no Next.)
                                  onNext:
                                      (_controller.loggingMode ==
                                              ExerciseLoggingMode.weightReps ||
                                          _controller.isDistanceDuration)
                                      ? () => _openRepsField?.call()
                                      : null,
                                  // W / F tags in the keyboard toggle this set's type.
                                  setType: _controller.setType,
                                  onSetTypeChanged: _handleSetTypeSelected,
                                ),
                          repsFieldWidth: _controller.usesDurationField
                              ? SetRowLayout.durationFieldWidth
                              : SetRowLayout.repsFieldWidth,
                          repsField: SetRowRepsField(
                            setIndex: widget.setIndex,
                            usesDurationField: _controller.usesDurationField,
                            isCompleted: _controller.isCompleted,
                            isRepsPrefilled: _controller.isRepsPrefilled,
                            isRepsPlaceholder: _controller.isRepsPlaceholder,
                            repsController: _controller.repsController,
                            repsFocusNode: _controller.repsFocusNode,
                            cardioDraftSeconds: _controller.cardioDraftSeconds,
                            onDurationChanged:
                                _controller.handleDurationChanged,
                            onDurationSubmitted: (seconds) =>
                                _handleDurationEditingComplete(
                                  context,
                                  seconds,
                                ),
                            onDurationFocusChanged:
                                _controller.handleDurationFocusChanged,
                            onDurationTap: _controller.handleDurationTap,
                            onRepsTap: _controller.handleRepsTap,
                            onRepsChanged: _controller.handleRepsChanged,
                            onRepsEditingComplete: () =>
                                _handleRepsEditingComplete(context),
                            onRepsCommit: _handleCommitDraft,
                            rpe:
                                _controller.loggingMode ==
                                    ExerciseLoggingMode.weightReps
                                ? _controller.rpe
                                : null,
                            onRpeSelected:
                                _controller.loggingMode ==
                                    ExerciseLoggingMode.weightReps
                                ? _handleRpeSelected
                                : null,
                            // W / F tags in the keyboard toggle this set's type.
                            setType: _controller.setType,
                            onSetTypeChanged: _handleSetTypeSelected,
                            // Register the reps open() so weight's "Next" can call it.
                            registerOpener: (open) => _openRepsField = open,
                          ),
                          completionButton: SetRowCompletionButton(
                            setIndex: widget.setIndex,
                            isCompleted: _controller.isCompleted,
                            isPr: _controller.isPr,
                            onComplete: _handleCompletePressed,
                            onUncomplete: _handleUncompletePressed,
                          ),
                        ),
                        if (suggestion != null)
                          _NextSetSuggestionHint(
                            label:
                                '${NumberFormatUtil.formatWeight(suggestion.weightKg)} kg '
                                '× ${suggestion.reps}',
                            onAccept: () => _handleAcceptSuggestion(suggestion),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CompletedLeftAccent extends StatelessWidget {
  const _CompletedLeftAccent();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('completedLeftAccent'),
      width: 3,
      color: Theme.of(context).colorScheme.tertiary,
    );
  }
}

/// A small, obviously-tappable next-set target shown beneath a still-empty
/// working row (e.g. `→ 62.5 kg × 8`). Secondary, theme-driven styling so it
/// reads as a hint, not a logged value; tapping it fills the row's fields.
/// Aligned under the "Previous" column so it sits with the reference value.
class _NextSetSuggestionHint extends StatelessWidget {
  const _NextSetSuggestionHint({required this.label, required this.onAccept});

  final String label;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: SetRowLayout.setColumnWidth + SetRowLayout.previousLeadingGap,
        bottom: 6,
      ),
      child: InkWell(
        key: const Key('nextSetSuggestion'),
        onTap: onAccept,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_forward,
                size: 13,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
