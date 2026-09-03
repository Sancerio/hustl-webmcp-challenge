import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/features/learn/domain/learn_articles.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart'
    show SetType;
import 'package:hustl_app/features/workout_logging/domain/utils/effort_scale.dart';
import 'package:hustl_app/features/workout_logging/presentation/utils/effort_intensity.dart';

/// Shared [TapRegion] group id linking the set-input keyboard panel and the set
/// fields. A tap anywhere OUTSIDE this group (the ✓ check, action chips, Add
/// set, the finish bar, another row…) dismisses the keyboard; a tap on a field
/// stays in the group and re-targets the keyboard instead of closing it.
const String setInputTapGroupId = 'hustl.setInputKeyboard';

/// Which set field the keyboard is editing — drives the keypad's corner key
/// (decimal for the decimal-bearing weight/distance fields, Clear for the
/// whole-number reps/duration fields) and the max digit length. The RIR effort
/// row shows only for the strength weight/reps fields (cardio has no RIR).
enum SetInputKind { weight, reps, distance, duration }

/// Everything the [SetInputKeyboard] needs to edit ONE field, plus the field's
/// [TextEditingController] as a stable identity so the host can tell which input
/// is active (active highlight) and so tapping a different field re-keys the
/// keyboard onto the new value.
class SetInputSession {
  const SetInputSession({
    required this.controller,
    required this.kind,
    required this.allowDecimal,
    required this.initialText,
    this.rpe,
    required this.onTextChanged,
    this.onRpeChanged,
    required this.onDone,
    this.onNext,
    this.onCommit,
    this.setType,
    this.onSetTypeChanged,
    this.onCollapse,
  });

  /// Identity of the active field (NOT used to read text directly).
  final TextEditingController controller;
  final SetInputKind kind;
  final bool allowDecimal;
  final String initialText;
  final int? rpe;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<int?>? onRpeChanged;
  final VoidCallback onDone;

  /// Advance to the next field of this set (e.g. weight → reps). When non-null
  /// the keyboard's primary key reads "Next" and calls this instead of "Done";
  /// null on the last field, where the primary key completes the set ([onDone]).
  final VoidCallback? onNext;

  /// Persist the in-progress draft WITHOUT completing the set — called when the
  /// keyboard re-targets to another field or closes. Read-only keyboard fields
  /// don't fire the old focus-loss blur-save, so this is the explicit blur-save.
  final VoidCallback? onCommit;

  /// The set's current type, so the keypad's W / F tags can show their active
  /// state. Null when the host doesn't wire set-type tagging.
  final SetType? setType;

  /// Toggle the set's type from the keypad's W (warm-up) / F (failure) tags.
  /// Null disables those keys.
  final ValueChanged<SetType>? onSetTypeChanged;

  /// Dismiss the keyboard without completing the set (the collapse key). Null
  /// disables that key.
  final VoidCallback? onCollapse;

  /// Whether to show the effort (RIR) badge row. True whenever the field carries
  /// an effort callback — i.e. for BOTH weight and reps on a weight×reps set — so
  /// the keyboard is one constant height and switching fields never reshapes it.
  bool get showRpe => onRpeChanged != null;
}

/// Holds the active [SetInputSession]. A screen owns one and exposes it via
/// [SetInputKeyboardScope]; tapping any set input opens/re-targets it, so the
/// keyboard stays up and follows focus like a native keyboard.
class SetInputKeyboardController extends ChangeNotifier {
  SetInputSession? _active;
  SetInputSession? get active => _active;
  bool get isOpen => _active != null;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void open(SetInputSession session) {
    final previous = _active;
    // Re-targeting to a DIFFERENT field: commit the outgoing field's draft
    // first (native focus-loss save) so switching never drops a typed value.
    if (previous != null &&
        !identical(previous.controller, session.controller)) {
      previous.onCommit?.call();
    }
    _active = session;
    notifyListeners();
  }

  /// Clears the active session if it belongs to [controller] — called when the
  /// owning row is disposed (swiped away, removed, or virtualized off-screen) so
  /// the keyboard can't keep writing through a now-disposed controller. Clears
  /// synchronously, then unmounts the host panel via a post-frame notify: detach
  /// can run during the parent list's build (notify-during-build would assert)
  /// or via ListView virtualization (no parent rebuild follows, so a synchronous
  /// clear alone would leave the panel mounted). The post-frame is guarded so a
  /// teardown-time detach never notifies a disposed controller.
  void detachIfActive(TextEditingController controller) {
    if (!identical(_active?.controller, controller)) return;
    _active = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
  }

  /// Closes the keyboard. By default commits the active draft first (tap-outside
  /// / leave); pass `commit: false` when the caller already persisted (Done).
  void close({bool commit = true}) {
    final active = _active;
    if (active == null) return;
    if (commit) active.onCommit?.call();
    _active = null;
    notifyListeners();
  }
}

/// Makes the screen's [SetInputKeyboardController] available to descendant set
/// fields. Absent in isolated widget tests / on screens that opt out — fields
/// then fall back to their standalone behaviour.
class SetInputKeyboardScope
    extends InheritedNotifier<SetInputKeyboardController> {
  const SetInputKeyboardScope({
    super.key,
    required SetInputKeyboardController controller,
    required super.child,
  }) : super(notifier: controller);

  static SetInputKeyboardController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SetInputKeyboardScope>()
        ?.notifier;
  }

  /// Like [maybeOf] but does NOT register a dependency — safe to call from
  /// lifecycle methods (e.g. `dispose`) and one-shot callbacks.
  static SetInputKeyboardController? read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<SetInputKeyboardScope>();
    return (element?.widget as SetInputKeyboardScope?)?.notifier;
  }
}

/// Strong/MacroFactor-style custom keyboard for a set's numeric inputs.
///
/// A constant-height panel: a number pad plus an always-present row of
/// colour-coded RIR (reps-in-reserve) effort badges. Weight gets a decimal key;
/// reps gets a Clear key. The first digit after opening on an existing value
/// REPLACES it (select-all semantics); tapping the active badge clears the RIR.
class SetInputKeyboard extends StatefulWidget {
  const SetInputKeyboard({super.key, required this.session});

  final SetInputSession session;

  /// Approximate full sheet/panel height (content + bottom safe area), so a host
  /// can reserve space and reflow the list while this is open. Reps is taller
  /// (it carries the RPE range).
  static double estimatedHeight(BuildContext context, {required bool showRpe}) {
    // Optional RIR section, then the number grid + right action column (same
    // 4-row height). No top toolbar.
    final base = showRpe ? 392.0 : 280.0;
    return base + MediaQuery.of(context).viewPadding.bottom;
  }

  @override
  State<SetInputKeyboard> createState() => _SetInputKeyboardState();
}

class _SetInputKeyboardState extends State<SetInputKeyboard>
    with SingleTickerProviderStateMixin {
  // Effort is shown as RIR (reps in reserve, 0–6+) but still STORED as RPE; the
  // frontend mapping lives in [EffortScale]. The `6` badge renders as "6+".
  static const List<int> _rirValues = [0, 1, 2, 3, 4, 5, 6];

  late String _text;
  late int? _rir;
  late SetType _setType;

  // Native-style reveal: the panel slides its content up from below on mount
  // (paint only — the host reserves the height, so the list reflow / scroll
  // math are unaffected). ~iOS timing/curve. Field switches reuse this State
  // (didUpdateWidget), so the slide never replays mid-edit.
  late final AnimationController _revealController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  late final Animation<Offset> _revealOffset =
      Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
        CurvedAnimation(parent: _revealController, curve: Curves.easeOutCubic),
      );

  // First digit after opening on an existing value REPLACES it (select-all);
  // backspace/clear cancel that and edit in place. Without it, editing `12` to
  // `8` would produce `128`.
  bool _replaceOnNextDigit = false;

  // weight & distance accept up to 6 chars (`122.5`); reps up to 3 (`100`);
  // duration up to 4 raw digits (`mm:ss`, up to `99:59`). For duration the
  // `_text` is the raw digit string — all mm:ss formatting happens in the
  // session's onTextChanged, not here.
  int get _maxLen {
    switch (widget.session.kind) {
      case SetInputKind.weight:
      case SetInputKind.distance:
        return 6;
      case SetInputKind.reps:
        return 3;
      case SetInputKind.duration:
        return 4;
    }
  }

  @override
  void initState() {
    super.initState();
    _text = widget.session.initialText;
    _rir = EffortScale.rirFromRpe(widget.session.rpe);
    _setType = widget.session.setType ?? SetType.regular;
    _replaceOnNextDigit = _text.isNotEmpty;
    _revealController.forward();
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SetInputKeyboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The host reuses this widget across field switches (stable key) instead of
    // rebuilding it, so re-seed the local editing state when re-targeted to a
    // DIFFERENT field. Same controller (e.g. a plain parent rebuild) keeps the
    // in-progress text — matching the previous ValueKey(controller) behaviour.
    if (!identical(oldWidget.session.controller, widget.session.controller)) {
      _text = widget.session.initialText;
      _rir = EffortScale.rirFromRpe(widget.session.rpe);
      _setType = widget.session.setType ?? SetType.regular;
      _replaceOnNextDigit = _text.isNotEmpty;
    }
  }

  void _setText(String value) {
    setState(() => _text = value);
    widget.session.onTextChanged(value);
    Haptics.selection();
  }

  void _appendDigit(String digit) {
    if (_replaceOnNextDigit) {
      _replaceOnNextDigit = false;
      _setText(digit);
      return;
    }
    if (_text.replaceAll('.', '').length >= _maxLen) return;
    final next = _text == '0' ? digit : '$_text$digit';
    _setText(next);
  }

  void _appendDecimal() {
    if (_replaceOnNextDigit) {
      _replaceOnNextDigit = false;
      _setText('0.');
      return;
    }
    if (_text.contains('.')) return;
    _setText(_text.isEmpty ? '0.' : '$_text.');
  }

  void _backspace() {
    _replaceOnNextDigit = false;
    if (_text.isEmpty) return;
    _setText(_text.substring(0, _text.length - 1));
  }

  void _clear() {
    _replaceOnNextDigit = false;
    if (_text.isEmpty) return;
    _setText('');
  }

  void _selectRir(int value) {
    // Tapping the active badge again clears it (effort is optional).
    final next = _rir == value ? null : value;
    setState(() => _rir = next);
    widget.session.onRpeChanged?.call(EffortScale.rpeFromRir(next));
    Haptics.selection();
  }

  void _clearRir() {
    if (_rir == null) return;
    setState(() => _rir = null);
    widget.session.onRpeChanged?.call(null);
    Haptics.selection();
  }

  // W / F tags toggle the set's type. Tapping the active tag again returns the
  // set to a regular working set. Kept as local state (like _rir) so the active
  // highlight flips instantly, then reported up via onSetTypeChanged.
  void _toggleType(SetType type) {
    final next = _setType == type ? SetType.regular : type;
    // Failure == RIR 0 (no reps left). We do NOT write RPE here: the set-type
    // change handler applies type + RIR 0 atomically as ONE persisted write.
    // That matters in the production ExerciseCard path, where the type change is
    // intercepted and mutates the sets list — a separate RPE write off this
    // row's (now stale) controller would clobber the failure type. Locally we
    // just pre-highlight the RIR 0 ring for instant feedback; the rebuild then
    // seeds it from the persisted rpe. One-way: un-toggling F leaves RIR as-is.
    setState(() {
      _setType = next;
      if (next == SetType.failure && widget.session.showRpe) _rir = 0;
    });
    widget.session.onSetTypeChanged?.call(next);
    Haptics.selection();
  }

  void _collapse() {
    widget.session.onCollapse?.call();
    Haptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final showRpe = widget.session.showRpe;

    return SlideTransition(
      position: _revealOffset,
      child: SafeArea(
        top: false,
        child: Container(
          key: const Key('repsRpeKeyboard'),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.sheet),
            ),
            border: Border(
              top: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x2,
            AppSpacing.x1,
            AppSpacing.x2,
            AppSpacing.x2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Effort (RIR) badges are ALWAYS present for weight×reps sets (both
              // the weight and reps fields carry the effort callback), so the
              // keyboard is one constant height — switching fields never reshapes
              // it and the set row above never jumps.
              if (showRpe) ...[
                _RirBadgeField(
                  values: _rirValues,
                  selected: _rir,
                  onSelected: _selectRir,
                  onClear: _clearRir,
                  onHelp: () => showRirInfoSheet(context),
                ),
                const SizedBox(height: AppSpacing.x2),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: AppSpacing.x2),
              ],
              // MacroFactor-style: a 3-wide number grid on the left, and a
              // right-hand column of action keys (collapse · W · F · ✓). Each
              // does a real job, so the action never reads as one oversized
              // button and 0 keeps its natural spot clear of the primary key.
              _Keypad(
                allowDecimal: widget.session.allowDecimal,
                onDigit: _appendDigit,
                onDecimal: _appendDecimal,
                onBackspace: _backspace,
                onClear: _clear,
                isNext: widget.session.onNext != null,
                onPrimary: widget.session.onNext ?? widget.session.onDone,
                onCollapse: widget.session.onCollapse != null
                    ? _collapse
                    : null,
                canTag: widget.session.onSetTypeChanged != null,
                isWarmup: _setType == SetType.warmup,
                isFailure: _setType == SetType.failure,
                onToggleWarmup: () => _toggleType(SetType.warmup),
                onToggleFailure: () => _toggleType(SetType.failure),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reps-in-reserve gloss for each RIR value. Kept short so it never wraps in the
/// header line.
String _rirMeaning(int? rir) {
  switch (rir) {
    case 0:
      return 'Max effort · nothing left';
    case 1:
      return '1 rep left in reserve';
    case 2:
      return '2 reps left in reserve';
    case 3:
      return '3 reps left in reserve';
    case 4:
      return '4 reps left in reserve';
    case 5:
      return '5 reps left in reserve';
    case 6:
      return '6+ reps left · took it easy';
    default:
      return 'Optional · how many reps left?';
  }
}

/// The effort input: a labelled header + a MacroFactor-style scale of discrete,
/// colour-coded RIR dots, trailed by a "?" that explains RIR.
class _RirBadgeField extends StatelessWidget {
  const _RirBadgeField({
    required this.values,
    required this.selected,
    required this.onSelected,
    required this.onClear,
    required this.onHelp,
  });

  final List<int> values;
  final int? selected;
  final ValueChanged<int> onSelected;
  final VoidCallback onClear;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasValue = selected != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'RIR',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: AppSpacing.x1),
            Expanded(
              child: Text(
                _rirMeaning(selected),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: hasValue
                      ? colors.onSurface.withValues(alpha: 0.75)
                      : colors.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            AnimatedOpacity(
              opacity: hasValue ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: IgnorePointer(
                ignoring: !hasValue,
                child: TextButton(
                  key: const Key('rirClear'),
                  onPressed: onClear,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.x1,
                    ),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: colors.onSurfaceVariant,
                    textStyle: theme.textTheme.labelLarge,
                  ),
                  child: const Text('Clear'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x1),
        Row(
          children: [
            Expanded(
              child: _RirScale(
                values: values,
                selected: selected,
                onSelected: onSelected,
              ),
            ),
            const SizedBox(width: AppSpacing.x1),
            _RirHelpButton(onTap: onHelp),
          ],
        ),
      ],
    );
  }
}

/// The effort scale: a row of discrete, colour-coded [_RirDot]s (no connecting
/// rail — that read too much like the old slider, especially in dark mode).
class _RirScale extends StatelessWidget {
  const _RirScale({
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  final List<int> values;
  final int? selected;
  final ValueChanged<int> onSelected;

  static const double _height = 48;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: Row(
        children: [
          for (final value in values)
            Expanded(
              child: _RirDot(
                value: value,
                color: rirColor(value),
                selected: value == selected,
                onTap: () => onSelected(value),
              ),
            ),
        ],
      ),
    );
  }
}

/// A single RIR dot — a colour-coded circle. Outlined in its intensity colour
/// when unselected; filled (and enlarged, with a soft glow) when selected.
/// Labelled `6+` at the top of the scale.
class _RirDot extends StatelessWidget {
  const _RirDot({
    required this.value,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final label = value >= 6 ? '6+' : '$value';

    return InkResponse(
      key: Key('rirKey$value'),
      onTap: onTap,
      radius: 26,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          width: selected ? 40 : 30,
          height: selected ? 40 : 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? color : colors.surface,
            border: Border.all(color: color, width: selected ? 0 : 1.5),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: selected ? AppColors.brandCloudWhite : color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

/// The trailing "?" that opens the RIR explainer.
class _RirHelpButton extends StatelessWidget {
  const _RirHelpButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkResponse(
      key: const Key('rirHelp'),
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surfaceContainerHighest,
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Icon(
          Icons.question_mark_rounded,
          size: 15,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Quick in-place explainer for RIR (reps in reserve), opened from the keyboard's
/// "?" so the lifter never has to leave the set they're logging.
Future<void> showRirInfoSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final colors = theme.colorScheme;
      Widget legend(int rir, String label) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.x1),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: rirColor(rir),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          ],
        ),
      );

      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x3,
            0,
            AppSpacing.x3,
            AppSpacing.x3,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RIR — reps in reserve',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.x2),
              Text(
                'RIR is how many more reps you could have done at the end of a '
                'set. It’s the simplest way to gauge — and log — how hard a set '
                'felt, so you can train at the right intensity over time.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.x3),
              legend(0, 'RIR 0–1 — at or near failure, nothing left'),
              legend(2, 'RIR 2–3 — hard, a couple of reps left'),
              legend(4, 'RIR 4–5 — moderate, comfortably short of failure'),
              legend(6, 'RIR 6+ — easy, plenty left in the tank'),
              const SizedBox(height: AppSpacing.x2),
              Text(
                'Lower RIR means a harder set. Logging it is optional — add it '
                'when it helps you autoregulate.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.x3),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  key: const Key('rirReadMore'),
                  onPressed: () {
                    // Capture the router before dismissing the sheet (the sheet's
                    // context is gone after pop); then open the full Learn guide.
                    final router = GoRouter.of(context);
                    router.pop();
                    router.push('/learn/$understandingRirSlug');
                  },
                  child: const Text('Read the full guide'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.allowDecimal,
    required this.onDigit,
    required this.onDecimal,
    required this.onBackspace,
    required this.onClear,
    required this.isNext,
    required this.onPrimary,
    required this.onCollapse,
    required this.canTag,
    required this.isWarmup,
    required this.isFailure,
    required this.onToggleWarmup,
    required this.onToggleFailure,
  });

  final bool allowDecimal;
  final ValueChanged<String> onDigit;
  final VoidCallback onDecimal;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  /// Primary action — "Next" advances to the next field; otherwise it completes
  /// the set ("Done"). Lives at the bottom of the right column.
  final bool isNext;
  final VoidCallback onPrimary;

  /// Dismiss the keyboard (the collapse key). Null disables it.
  final VoidCallback? onCollapse;

  /// Whether the W / F set-type tags are wired (else they render disabled).
  final bool canTag;
  final bool isWarmup;
  final bool isFailure;
  final VoidCallback onToggleWarmup;
  final VoidCallback onToggleFailure;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // 3-wide number grid: 0 in its natural bottom-middle spot, backspace
    // bottom-right.
    final numberGrid = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.x1),
            child: Row(
              children: [
                for (final digit in row)
                  Expanded(
                    child: _KeyboardKey(
                      keyboardKey: Key('repsKeyboardDigit$digit'),
                      label: digit,
                      onTap: () => onDigit(digit),
                    ),
                  ),
              ],
            ),
          ),
        Row(
          children: [
            // Weight/distance gets a decimal point; reps gets a Clear key.
            Expanded(
              child: allowDecimal
                  ? _KeyboardKey(
                      keyboardKey: const Key('repsKeyboardDecimal'),
                      label: '.',
                      onTap: onDecimal,
                    )
                  : _KeyboardKey(
                      keyboardKey: const Key('repsKeyboardClear'),
                      label: 'Clear',
                      muted: true,
                      onTap: onClear,
                    ),
            ),
            Expanded(
              child: _KeyboardKey(
                keyboardKey: const Key('repsKeyboardDigit0'),
                label: '0',
                onTap: () => onDigit('0'),
              ),
            ),
            Expanded(
              child: _KeyboardKey(
                keyboardKey: const Key('repsKeyboardBackspace'),
                icon: Icons.backspace_outlined,
                muted: true,
                onTap: onBackspace,
              ),
            ),
          ],
        ),
      ],
    );

    // Right column of action keys, one per grid row: collapse · W · F · ✓.
    final rightColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.x1),
          child: _ActionKey(
            keyboardKey: const Key('repsKeyboardCollapse'),
            icon: Icons.keyboard_arrow_down_rounded,
            fill: colors.surfaceContainerHighest,
            content: colors.onSurfaceVariant,
            onTap: onCollapse,
          ),
        ),
        // Set-type colour system: blue is commit-only (the ✓ Done key below,
        // active control chips elsewhere) and never marks a set type. W
        // (warm-up) is amber everywhere; F (to-failure) is terracotta
        // everywhere — it IS the RIR 0 shortcut, so it shares the effort
        // "near-failure" colour. Idle keys show a tint + darkened ink glyph;
        // the engaged state is a solid fill with a white glyph.
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.x1),
          child: _ActionKey(
            keyboardKey: const Key('repsKeyboardWarmup'),
            label: 'W',
            fill: isWarmup
                ? AppColors.warmupSolid
                : AppColors.accentWarningAmber.withValues(
                    alpha: AppColors.setTypeKeyIdleAlpha(context),
                  ),
            content: isWarmup
                ? AppColors.brandCloudWhite
                : AppColors.warmupInk(context),
            onTap: canTag ? onToggleWarmup : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.x1),
          child: _ActionKey(
            keyboardKey: const Key('repsKeyboardFailure'),
            label: 'F',
            fill: isFailure
                ? AppColors.effortNearFailure
                : AppColors.effortNearFailure.withValues(
                    alpha: AppColors.setTypeKeyIdleAlpha(context),
                  ),
            content: isFailure
                ? AppColors.brandCloudWhite
                : AppColors.failureInk(context),
            onTap: canTag ? onToggleFailure : null,
          ),
        ),
        _ActionKey(
          keyboardKey: Key(isNext ? 'repsKeyboardNext' : 'repsKeyboardDone'),
          icon: isNext ? Icons.arrow_forward_rounded : Icons.check_rounded,
          fill: colors.primary,
          content: colors.onPrimary,
          onTap: onPrimary,
        ),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: numberGrid),
        Expanded(flex: 1, child: rightColumn),
      ],
    );
  }
}

class _KeyboardKey extends StatelessWidget {
  const _KeyboardKey({
    required this.keyboardKey,
    this.label,
    this.icon,
    this.muted = false,
    required this.onTap,
  }) : assert(label != null || icon != null);

  final Key keyboardKey;
  final String? label;
  final IconData? icon;
  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = muted ? colors.onSurfaceVariant : colors.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1 / 2),
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: InkWell(
          key: keyboardKey,
          borderRadius: BorderRadius.circular(AppRadius.control),
          onTap: onTap,
          child: SizedBox(
            height: 50,
            child: Center(
              child: icon != null
                  ? Icon(icon, color: foreground, size: 22)
                  // Scale the label down rather than overflow the fixed-height
                  // key at large accessibility text scales ("Clear" is widest).
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          label!,
                          maxLines: 1,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: foreground,
                            fontWeight: muted
                                ? FontWeight.w600
                                : FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A right-column action key (collapse · W · F · ✓). Unlike [_KeyboardKey] it
/// carries its own fill/content colours and an optional outline (for an active
/// W/F tag), and renders disabled (dimmed, no tap) when [onTap] is null.
class _ActionKey extends StatelessWidget {
  const _ActionKey({
    required this.keyboardKey,
    this.label,
    this.icon,
    required this.fill,
    required this.content,
    required this.onTap,
  }) : assert(label != null || icon != null);

  final Key keyboardKey;
  final String? label;
  final IconData? icon;
  final Color fill;
  final Color content;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(AppRadius.control);
    final enabled = onTap != null;

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1 / 2),
        child: Material(
          color: fill,
          borderRadius: radius,
          child: InkWell(
            key: keyboardKey,
            borderRadius: radius,
            onTap: onTap,
            child: SizedBox(
              height: 50,
              child: Center(
                child: icon != null
                    ? Icon(icon, color: content, size: 22)
                    // Scale the W / F / label down rather than overflow at large
                    // accessibility text scales.
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Text(
                            label!,
                            maxLines: 1,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: content,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
