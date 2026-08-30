import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart'
    show SetType;

import 'set_input_keyboard.dart';

class SetRowWeightField extends StatefulWidget {
  final int setIndex;
  final bool isDistanceDuration;
  final bool isCompleted;
  final bool isWeightPrefilled;
  final bool isWeightPlaceholder;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ExerciseKind exerciseKind;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;
  final VoidCallback onEditingComplete;
  // Persist the weight draft without completing (keyboard re-target / dismiss).
  final VoidCallback? onCommit;
  // The set's effort, shown in the always-present keyboard badge row so it can
  // be set while editing weight too (null for non weight×reps exercises).
  final int? rpe;
  final ValueChanged<int?>? onRpeSelected;
  // Advance the keyboard to the reps field (weight→reps). Null = no Next key.
  final VoidCallback? onNext;
  // The set's current type + a setter, so the keyboard's W / F tags can show and
  // toggle warm-up / failure while editing weight too.
  final SetType? setType;
  final ValueChanged<SetType>? onSetTypeChanged;

  const SetRowWeightField({
    super.key,
    required this.setIndex,
    required this.isDistanceDuration,
    required this.isCompleted,
    required this.isWeightPrefilled,
    required this.isWeightPlaceholder,
    required this.controller,
    required this.focusNode,
    required this.exerciseKind,
    required this.onTap,
    required this.onChanged,
    required this.onEditingComplete,
    this.onCommit,
    this.rpe,
    this.onRpeSelected,
    this.onNext,
    this.setType,
    this.onSetTypeChanged,
  });

  @override
  State<SetRowWeightField> createState() => _SetRowWeightFieldState();
}

class _SetRowWeightFieldState extends State<SetRowWeightField> {
  Timer? _scrollIntoViewTimer;

  @override
  void dispose() {
    _scrollIntoViewTimer?.cancel();
    super.dispose();
  }

  void _scheduleScrollIntoView() {
    _scrollIntoViewTimer?.cancel();
    _scrollIntoViewTimer = Timer(const Duration(milliseconds: 16), () {
      if (!context.mounted) return;
      if (Scrollable.maybeOf(context) == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 1.0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  // Screen-hosted path: open (or re-target) the shared keyboard. Strength
  // weight and cardio distance are IDENTICAL plain-decimal entry — only the
  // session `kind` (corner key/length) and the absent RIR row differ.
  void _openScoped(SetInputKeyboardController keyboard) {
    widget.onTap();
    keyboard.open(
      SetInputSession(
        controller: widget.controller,
        kind: widget.isDistanceDuration
            ? SetInputKind.distance
            : SetInputKind.weight,
        allowDecimal: true,
        initialText: widget.controller.text,
        rpe: widget.rpe,
        setType: widget.setType,
        onSetTypeChanged: widget.onSetTypeChanged,
        onTextChanged: (value) {
          widget.controller.value = TextEditingValue(
            text: value,
            selection: TextSelection.collapsed(offset: value.length),
          );
          widget.onChanged(value);
        },
        onRpeChanged: widget.onRpeSelected,
        onCommit: widget.onCommit,
        // "Next" re-targets the keyboard to reps; re-target commits this draft.
        onNext: widget.onNext,
        onDone: () {
          // Done already persists the weight; close without re-committing.
          widget.onEditingComplete();
          keyboard.close(commit: false);
        },
        onCollapse: keyboard.close,
      ),
    );
    _scheduleScrollIntoView();
  }

  @override
  Widget build(BuildContext context) {
    // Join the shared-keyboard tap group (see SetRowRepsField): tapping the
    // field re-targets the keyboard; a tap outside the group dismisses it.
    return TapRegion(
      groupId: setInputTapGroupId,
      child: _buildField(context),
    );
  }

  Widget _buildField(BuildContext context) {
    final theme = Theme.of(context);
    final keyboard = SetInputKeyboardScope.maybeOf(context);
    // The Strong-style custom keyboard drives BOTH strength weight and cardio
    // distance whenever a hosting screen provides a keyboard scope; without one
    // (e.g. the history edit screen / isolated widget tests) the field falls
    // back to the native numeric keyboard.
    final useCustomKeyboard = keyboard != null;
    final active = useCustomKeyboard &&
        keyboard.active?.controller == widget.controller;

    final Color restColor = widget.isCompleted
        ? theme.colorScheme.tertiary.withValues(alpha: 0.7)
        : theme.colorScheme.primary.withValues(alpha: 0.5);
    final Color enabledBorderColor = active
        ? theme.colorScheme.primary
        : restColor;
    final double enabledBorderWidth = active ? 2 : 1;
    final Color fillColor = active
        ? theme.colorScheme.primary.withValues(alpha: 0.08)
        : theme.colorScheme.surface;

    return Semantics(
      label: widget.isDistanceDuration
          ? 'Set ${widget.setIndex + 1} Distance (km)'
          : 'Set ${widget.setIndex + 1} Weight (kg)',
      textField: true,
      enabled: true,
      child: ExcludeSemantics(
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          // Weight and distance are entered via the read-only custom keyboard
          // when a scope is present; the standalone fallback uses the OS keyboard.
          keyboardType: useCustomKeyboard
              ? TextInputType.none
              : const TextInputType.numberWithOptions(decimal: true),
          readOnly: useCustomKeyboard,
          canRequestFocus: !useCustomKeyboard,
          showCursor: !useCustomKeyboard,
          scrollPadding: EdgeInsets.zero,
          maxLines: 1,
          textAlign: TextAlign.center,
          textInputAction: TextInputAction.next,
          enabled: true,
          onTap: useCustomKeyboard
              ? () => _openScoped(keyboard)
              // Native fallback only (no hosting scope → `keyboard` is null), so
              // there is no custom keyboard to dismiss here.
              : widget.onTap,
          onChanged: widget.onChanged,
          onEditingComplete: widget.onEditingComplete,
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              widget.exerciseKind == ExerciseKind.assisted
                  ? RegExp(r'^-?\d*\.?\d*')
                  : RegExp(r'^\d*\.?\d*'),
            ),
          ],
          // Row-value voice (§12.1): 15/w600 tabular.
          style: TextStyle(
            color: (widget.isWeightPrefilled || widget.isWeightPlaceholder)
                ? theme.colorScheme.onSurface.withValues(alpha: 0.35)
                : theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 15,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            isDense: true,
            // Vertical inset tuned so the tap target clears the 44pt minimum.
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: theme.colorScheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: enabledBorderColor,
                width: enabledBorderWidth,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: widget.isCompleted
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.primary,
                width: 1.0,
              ),
            ),
            fillColor: fillColor,
            filled: true,
            hintText:
                (widget.isWeightPlaceholder && widget.controller.text.isEmpty)
                ? '0.0'
                : null,
            hintStyle: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
              fontWeight: FontWeight.w600,
              fontSize: 15,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            suffixText: widget.isDistanceDuration ? 'km' : 'kg',
            suffixStyle: TextStyle(
              color: theme.colorScheme.onSurface.withValues(
                alpha: widget.isWeightPlaceholder ? 0.35 : 0.8,
              ),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
