import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart'
    show SetType;
import 'package:hustl_app/features/workout_logging/domain/utils/effort_scale.dart';
import 'package:hustl_app/features/workout_logging/presentation/utils/effort_intensity.dart';

import 'duration_field.dart';
import 'set_input_keyboard.dart';

class SetRowRepsField extends StatefulWidget {
  final int setIndex;
  final bool usesDurationField;
  final bool isCompleted;
  final bool isRepsPrefilled;
  final bool isRepsPlaceholder;
  final TextEditingController repsController;
  final FocusNode repsFocusNode;
  final int? cardioDraftSeconds;
  final ValueChanged<int?> onDurationChanged;
  final ValueChanged<int?> onDurationSubmitted;
  final ValueChanged<bool> onDurationFocusChanged;
  final VoidCallback onDurationTap;
  final VoidCallback onRepsTap;
  final ValueChanged<String> onRepsChanged;
  final VoidCallback onRepsEditingComplete;
  // Persist the reps/duration draft without completing (keyboard re-target /
  // dismiss).
  final VoidCallback? onRepsCommit;
  final int? rpe;
  final ValueChanged<int?>? onRpeSelected;
  // The set's current type + a setter, so the keyboard's W / F tags can show and
  // toggle warm-up / failure for this set.
  final SetType? setType;
  final ValueChanged<SetType>? onSetTypeChanged;
  // Lets the host (SetRow) re-target the keyboard to this field — e.g. the
  // weight/distance field's "Next" key. Called once with this field's open
  // callback.
  final void Function(VoidCallback open)? registerOpener;

  const SetRowRepsField({
    super.key,
    required this.setIndex,
    required this.usesDurationField,
    required this.isCompleted,
    required this.isRepsPrefilled,
    required this.isRepsPlaceholder,
    required this.repsController,
    required this.repsFocusNode,
    required this.cardioDraftSeconds,
    required this.onDurationChanged,
    required this.onDurationSubmitted,
    required this.onDurationFocusChanged,
    required this.onDurationTap,
    required this.onRepsTap,
    required this.onRepsChanged,
    required this.onRepsEditingComplete,
    this.onRepsCommit,
    this.rpe,
    this.onRpeSelected,
    this.setType,
    this.onSetTypeChanged,
    this.registerOpener,
  });

  @override
  State<SetRowRepsField> createState() => _SetRowRepsFieldState();
}

class _SetRowRepsFieldState extends State<SetRowRepsField> {
  // Only used by the modal fallback (no hosting screen): tracks the active
  // border/tint while the sheet is open. The scoped path reads it from the
  // shared keyboard controller instead.
  bool _isEditing = false;

  // Lets the keyboard panel apply (one frame) before scrolling the row above
  // it. Cancelled on dispose so it never outlives the widget.
  Timer? _scrollIntoViewTimer;

  // State-owned controller holding the cardio Time field's visible "mm:ss"
  // string. The keyboard edits raw digits; this is the formatted projection.
  // (Unused for the reps branch, but created/disposed unconditionally so the
  // duration<->reps mode can switch without lifecycle gaps.)
  late final TextEditingController _durationDisplayController;

  // Latest cardio seconds parsed from the keyboard's raw digits — the keyboard
  // doesn't expose its in-progress value, so we mirror it here for "Done".
  int _durationDraftSeconds = 0;

  @override
  void initState() {
    super.initState();
    // Expose our open() so the weight/distance field's "Next" can re-target
    // here (reps for weight×reps, Time for cardio distance+duration).
    widget.registerOpener?.call(_openFromExternal);
    _durationDraftSeconds = widget.cardioDraftSeconds ?? 0;
    _durationDisplayController = TextEditingController(
      text: _durationDisplayText(widget.cardioDraftSeconds),
    );
  }

  @override
  void didUpdateWidget(SetRowRepsField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-seed the duration display when the stored seconds change EXTERNALLY
    // (e.g. parent rebuild after a sync) — but never while this field owns the
    // open keyboard, which would stomp the value the user is typing.
    if (widget.usesDurationField &&
        widget.cardioDraftSeconds != oldWidget.cardioDraftSeconds &&
        !_durationActive) {
      _durationDraftSeconds = widget.cardioDraftSeconds ?? 0;
      _durationDisplayController.text = _durationDisplayText(
        widget.cardioDraftSeconds,
      );
    }
  }

  @override
  void dispose() {
    _scrollIntoViewTimer?.cancel();
    _durationDisplayController.dispose();
    super.dispose();
  }

  // The formatted "mm:ss" projection of a stored seconds value (empty when the
  // field has no value yet, so the placeholder shows).
  String _durationDisplayText(int? seconds) => seconds == null
      ? ''
      : formatDurationDigits(durationSecondsToDigits(seconds));

  // True when THIS field owns the open keyboard (docked session OR modal sheet).
  // The session's identity is [repsController] (reused for both reps and
  // duration) so SetRow's existing dispose/detach/commit machinery keeps working
  // unchanged for cardio rows.
  bool get _durationActive {
    if (_isEditing) return true; // modal fallback
    final keyboard = SetInputKeyboardScope.read(context);
    return identical(keyboard?.active?.controller, widget.repsController);
  }

  // Re-target the shared keyboard to this field (reads the scope lazily so it's
  // valid when invoked, e.g. from the distance field's "Next").
  void _openFromExternal() {
    final keyboard = SetInputKeyboardScope.read(context);
    if (keyboard != null) _openScoped(keyboard);
  }

  SetInputSession _session(VoidCallback onDone, {VoidCallback? onCollapse}) {
    return SetInputSession(
      controller: widget.repsController,
      kind: SetInputKind.reps,
      allowDecimal: false,
      initialText: widget.repsController.text,
      rpe: widget.rpe,
      setType: widget.setType,
      onSetTypeChanged: widget.onSetTypeChanged,
      onTextChanged: (value) {
        widget.repsController.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
        widget.onRepsChanged(value);
      },
      onRpeChanged: widget.onRpeSelected,
      onDone: onDone,
      onCommit: widget.onRepsCommit,
      onCollapse: onCollapse,
    );
  }

  // Cardio Time session: the keyboard edits raw digits, this projects them to
  // "mm:ss" (display) + seconds (persisted). Identity is [repsController]; no
  // RIR (cardio), no "Next" (Time is the last field → "Done").
  SetInputSession _durationSession(
    VoidCallback onDone, {
    VoidCallback? onCollapse,
  }) {
    return SetInputSession(
      controller: widget.repsController,
      kind: SetInputKind.duration,
      allowDecimal: false,
      initialText: durationSecondsToDigits(widget.cardioDraftSeconds ?? 0),
      setType: widget.setType,
      onSetTypeChanged: widget.onSetTypeChanged,
      onTextChanged: (raw) {
        final seconds = durationDigitsToSeconds(raw);
        _durationDraftSeconds = seconds;
        _durationDisplayController.text = formatDurationDigits(raw);
        widget.onDurationChanged(seconds);
      },
      onDone: onDone,
      onCommit: widget.onRepsCommit,
      onCollapse: onCollapse,
    );
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

  // Screen-hosted path: open (or re-target) the shared keyboard. "Done" commits
  // the value (which also completes the set) before closing.
  void _openScoped(SetInputKeyboardController keyboard) {
    if (widget.usesDurationField) {
      widget.onDurationTap();
      keyboard.open(
        _durationSession(() {
          // Persist + complete via the existing cardio submit path, normalize
          // the visible "mm:ss" to the stored seconds (e.g. 00:90 → 01:30), then
          // close without re-committing. The re-seed is explicit because closing
          // rebuilds via the keyboard dependency, which does NOT run
          // didUpdateWidget's external re-seed.
          widget.onDurationSubmitted(_durationDraftSeconds);
          _durationDisplayController.text = _durationDisplayText(
            _durationDraftSeconds,
          );
          keyboard.close(commit: false);
        }, onCollapse: keyboard.close),
      );
    } else {
      widget.onRepsTap();
      keyboard.open(
        _session(() {
          // Done already commits + completes; close without re-committing.
          widget.onRepsEditingComplete();
          keyboard.close(commit: false);
        }, onCollapse: keyboard.close),
      );
    }
    _scheduleScrollIntoView();
  }

  // Standalone fallback (no hosting screen): a modal bottom sheet.
  Future<void> _openModal(BuildContext context) async {
    if (widget.usesDurationField) {
      widget.onDurationTap();
    } else {
      widget.onRepsTap();
    }
    setState(() => _isEditing = true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (sheetContext) {
        final onDone = widget.usesDurationField
            ? () {
                widget.onDurationSubmitted(_durationDraftSeconds);
                _durationDisplayController.text = _durationDisplayText(
                  _durationDraftSeconds,
                );
                Navigator.of(sheetContext).pop();
              }
            : () {
                widget.onRepsEditingComplete();
                Navigator.of(sheetContext).pop();
              };
        void onCollapse() => Navigator.of(sheetContext).pop();
        return SetInputKeyboard(
          session: widget.usesDurationField
              ? _durationSession(onDone, onCollapse: onCollapse)
              : _session(onDone, onCollapse: onCollapse),
        );
      },
    );
    // Barrier tap / drag / system back dismiss the sheet without "Done" —
    // persist the draft so the typed value isn't lost.
    widget.onRepsCommit?.call();
    if (mounted) setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    // Join the shared-keyboard tap group: a tap on this field re-targets the
    // keyboard, while a tap on any control OUTSIDE the group dismisses it (via
    // the panel's onTapOutside).
    return TapRegion(groupId: setInputTapGroupId, child: _buildField(context));
  }

  Widget _buildField(BuildContext context) {
    final theme = Theme.of(context);
    final keyboard = SetInputKeyboardScope.maybeOf(context);
    final scoped = keyboard != null;
    final active = scoped
        ? identical(keyboard.active?.controller, widget.repsController)
        : _isEditing;

    final Color restColor = widget.isCompleted
        ? theme.colorScheme.tertiary.withValues(alpha: 0.7)
        : theme.colorScheme.primary.withValues(alpha: 0.5);
    final Color borderColor = active ? theme.colorScheme.primary : restColor;
    final double borderWidth = active ? 2 : 1;
    final Color fillColor = active
        ? theme.colorScheme.primary.withValues(alpha: 0.08)
        : theme.colorScheme.surface;

    if (widget.usesDurationField) {
      return Semantics(
        label: 'Set ${widget.setIndex + 1} Time (mm:ss)',
        textField: true,
        enabled: true,
        child: ExcludeSemantics(
          child: TextField(
            key: const ValueKey('durationField'),
            scrollPadding: EdgeInsets.zero,
            maxLines: 1,
            controller: _durationDisplayController,
            keyboardType: TextInputType.none,
            readOnly: true,
            canRequestFocus: false,
            showCursor: false,
            textAlign: TextAlign.center,
            enabled: true,
            onTap: scoped
                ? () => _openScoped(keyboard)
                : () => _openModal(context),
            // Row-value voice (§12.1): 15/w600 tabular.
            style: TextStyle(
              color: (widget.isRepsPrefilled || widget.isRepsPlaceholder)
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.35)
                  : theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 15,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            decoration: _fieldDecoration(
              theme: theme,
              borderColor: borderColor,
              borderWidth: borderWidth,
              fillColor: fillColor,
              hintText: _durationDisplayController.text.isEmpty
                  ? 'mm:ss'
                  : null,
            ),
          ),
        ),
      );
    }

    // weight×reps mode: a read-only field driven by the custom keyboard. With a
    // hosting screen the shared keyboard is re-targeted on tap (so tapping
    // another field keeps it open); otherwise a modal sheet is used.
    // A small colour-coded RIR tag clings to the field's bottom-right corner
    // (MacroFactor-style) so the logged effort reads at a glance without taking
    // a column of its own. Same intensity palette as the keyboard's RIR scale.
    final rir = EffortScale.rirFromRpe(widget.rpe);

    return Semantics(
      label: 'Set ${widget.setIndex + 1} Reps',
      textField: true,
      enabled: true,
      child: ExcludeSemantics(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            TextField(
              key: Key('repsField-${widget.setIndex}'),
              scrollPadding: EdgeInsets.zero,
              maxLines: 1,
              controller: widget.repsController,
              focusNode: widget.repsFocusNode,
              keyboardType: TextInputType.none,
              readOnly: true,
              canRequestFocus: false,
              showCursor: false,
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.done,
              enabled: true,
              onTap: scoped
                  ? () => _openScoped(keyboard)
                  : () => _openModal(context),
              onChanged: widget.onRepsChanged,
              onEditingComplete: widget.onRepsEditingComplete,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              // Row-value voice (§12.1): 15/w600 tabular.
              style: TextStyle(
                color: (widget.isRepsPrefilled || widget.isRepsPlaceholder)
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.35)
                    : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: _fieldDecoration(
                theme: theme,
                borderColor: borderColor,
                borderWidth: borderWidth,
                fillColor: fillColor,
                hintText:
                    widget.isRepsPlaceholder &&
                        widget.repsController.text.isEmpty
                    ? '0'
                    : null,
              ),
            ),
            if (rir != null)
              Positioned(
                right: -3,
                bottom: -3,
                child: IgnorePointer(child: _RepsRirTag(rir: rir)),
              ),
          ],
        ),
      ),
    );
  }

  // Shared decoration for the read-only reps / Time fields so the two stay
  // visually identical (only the hint differs: `0` vs `mm:ss`).
  InputDecoration _fieldDecoration({
    required ThemeData theme,
    required Color borderColor,
    required double borderWidth,
    required Color fillColor,
    required String? hintText,
  }) {
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: theme.colorScheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: borderColor, width: borderWidth),
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
      hintText: hintText,
      hintStyle: TextStyle(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
        fontWeight: FontWeight.w600,
        fontSize: 15,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// The small colour-coded RIR badge that tags a reps field with its logged
/// effort. A pill showing the RIR value (`2`, or `6+` at the top of the scale),
/// filled in the value's intensity colour and ringed in the surface colour so it
/// reads as a distinct tag clinging to the field corner.
class _RepsRirTag extends StatelessWidget {
  const _RepsRirTag({required this.rir});

  final int rir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: rirColor(rir),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.surface, width: 1.5),
      ),
      child: Text(
        EffortScale.rirLabel(rir),
        style: theme.textTheme.labelSmall?.copyWith(
          color: AppColors.brandCarbonBlack,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          height: 1.0,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
