import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DurationField extends StatefulWidget {
  const DurationField({
    super.key,
    required this.valueSeconds,
    required this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.onFocusChanged,
    this.decoration,
    this.textStyle,
    this.textAlign = TextAlign.center,
    this.scrollPadding = EdgeInsets.zero,
    this.enabled = true,
    this.placeholder = 'mm:ss',
    this.maxDigits = 6,
    this.textInputAction = TextInputAction.done,
    this.keyboardType = const TextInputType.numberWithOptions(
      signed: false,
      decimal: false,
    ),
    this.onTap,
    this.selectAllOnFocus = true,
  }) : assert(maxDigits >= 2);

  final int? valueSeconds;
  final ValueChanged<int?> onSubmitted;
  final ValueChanged<int?>? onChanged;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChanged;
  final InputDecoration? decoration;
  final TextStyle? textStyle;
  final TextAlign textAlign;
  final EdgeInsets scrollPadding;
  final bool enabled;
  final String placeholder;
  final int maxDigits;
  final TextInputAction textInputAction;
  final TextInputType keyboardType;
  final VoidCallback? onTap;
  final bool selectAllOnFocus;

  @override
  State<DurationField> createState() => _DurationFieldState();
}

class _DurationFieldState extends State<DurationField> {
  late final TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _ignoreControllerChange = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _formatFromSeconds(widget.valueSeconds, widget.maxDigits),
    );
    _controller.addListener(_handleControllerChanged);
    _attachFocusNode(widget.focusNode);
  }

  @override
  void didUpdateWidget(DurationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _detachFocusNode();
      _attachFocusNode(widget.focusNode);
    }

    if (!_focusNode.hasFocus && widget.valueSeconds != oldWidget.valueSeconds) {
      final updated = _formatFromSeconds(widget.valueSeconds, widget.maxDigits);
      if (_controller.text != updated) {
        _setControllerText(updated);
      }
    } else if (!_focusNode.hasFocus &&
        widget.maxDigits != oldWidget.maxDigits) {
      final updated = _formatFromSeconds(widget.valueSeconds, widget.maxDigits);
      if (_controller.text != updated) {
        _setControllerText(updated);
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    _detachFocusNode();
    super.dispose();
  }

  void _attachFocusNode(FocusNode? node) {
    _ownsFocusNode = node == null;
    _focusNode = node ?? FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  void _detachFocusNode() {
    _focusNode.removeListener(_handleFocusChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
  }

  void _handleControllerChanged() {
    if (_ignoreControllerChange) {
      _ignoreControllerChange = false;
      return;
    }
    final digits = _extractDigits(_controller.text);
    final seconds = digits.isEmpty
        ? null
        : _digitsToSeconds(digits, widget.maxDigits);
    widget.onChanged?.call(seconds);
  }

  void _handleFocusChanged() {
    final hasFocus = _focusNode.hasFocus;
    widget.onFocusChanged?.call(hasFocus);
    if (hasFocus) {
      if (widget.selectAllOnFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _controller.text.length,
          );
        });
      }
      return;
    }
  }

  void _notifySubmitted() {
    final digits = _extractDigits(_controller.text);
    final seconds = digits.isEmpty
        ? null
        : _digitsToSeconds(digits, widget.maxDigits);
    widget.onSubmitted(seconds);

    final formatted = _formatFromSeconds(seconds, widget.maxDigits);
    if (_controller.text != formatted) {
      _setControllerText(formatted);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final followUp = _formatFromSeconds(
        widget.valueSeconds ?? seconds,
        widget.maxDigits,
      );
      if (_controller.text != followUp) {
        _setControllerText(followUp);
      }
    });
  }

  void _setControllerText(String text) {
    _ignoreControllerChange = true;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final decoration = (widget.decoration ?? const InputDecoration()).copyWith(
      hintText: widget.placeholder,
    );

    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: [
        DurationTextInputFormatter(maxDigits: widget.maxDigits),
      ],
      textAlign: widget.textAlign,
      style: widget.textStyle,
      scrollPadding: widget.scrollPadding,
      enabled: widget.enabled,
      decoration: decoration,
      onEditingComplete: _notifySubmitted,
      onTap: widget.onTap,
      maxLines: 1,
      enableInteractiveSelection: true,
      autocorrect: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
    );
  }
}

class DurationTextInputFormatter extends TextInputFormatter {
  DurationTextInputFormatter({this.maxDigits = 6}) : assert(maxDigits >= 2);

  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldDigits = _extractDigits(oldValue.text);
    final rawDigits = _extractDigits(newValue.text);
    var nextDigits = rawDigits;

    final insertedNonDigit =
        newValue.text.length > oldValue.text.length &&
        rawDigits.length == oldDigits.length;
    if (insertedNonDigit) {
      nextDigits = oldDigits;
    }

    if (nextDigits.length > maxDigits) {
      nextDigits = nextDigits.substring(nextDigits.length - maxDigits);
    }

    final formatted = formatDurationDigits(nextDigits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
      composing: TextRange.empty,
    );
  }
}

String _extractDigits(String text) {
  return text.replaceAll(RegExp(r'[^0-9]'), '');
}

/// Max raw digits the cardio duration field (and its custom keyboard) accepts —
/// `mm:ss`, up to `99:59`. Kept in one place so the keyboard's `_maxLen` and the
/// `seconds → digits` clamp below agree.
const int _cardioDurationMaxDigits = 4;

/// Format a raw digit string (e.g. `"130"`) as `mm:ss` (e.g. `"01:30"`). The
/// custom keyboard keeps `_text` as raw digits and routes ALL display
/// formatting through this, so the keyboard itself stays digit-agnostic.
String formatDurationDigits(String digits) {
  if (digits.isEmpty) {
    return '';
  }

  // Always interpret as `minutes:seconds` (no hours segment).
  //
  // This avoids UI "jumping" from `mm:ss` → `h:mm:ss` while typing and keeps a
  // consistent mental model for users.
  if (digits.length <= 2) {
    return '00:${digits.padLeft(2, '0')}';
  }

  final minutesRaw = digits.substring(0, digits.length - 2);
  final seconds = digits.substring(digits.length - 2).padLeft(2, '0');
  final minutes = minutesRaw.length < 2
      ? minutesRaw.padLeft(2, '0')
      : minutesRaw;
  return '$minutes:$seconds';
}

/// Total seconds for a raw digit string. The last two digits are seconds, the
/// rest minutes (so `"130"` → `1*60 + 30` = 90; `"90"` → 90, NOT 30).
int durationDigitsToSeconds(String digits) {
  if (digits.isEmpty) {
    return 0;
  }
  if (digits.length <= 2) {
    return int.parse(digits);
  }

  final minutes = int.parse(digits.substring(0, digits.length - 2));
  final seconds = int.parse(digits.substring(digits.length - 2));
  return minutes * 60 + seconds;
}

/// Raw digit string for a seconds value, clamped to the cardio `mm:ss` range
/// (`99:59`). Inverse of [durationDigitsToSeconds]; used to seed the keyboard's
/// `_text` and the display from a stored value (e.g. 90 → `"130"`).
String durationSecondsToDigits(int seconds) {
  return _secondsToDigits(seconds, _cardioDurationMaxDigits);
}

/// Shared `seconds → raw digits` clamp, reused by both the public cardio helper
/// and [DurationField]'s own (configurable max) seed path.
String _secondsToDigits(int seconds, int maxDigits) {
  final clamped = seconds.clamp(0, _maxSecondsForDigits(maxDigits));
  final minutes = clamped ~/ 60;
  final secs = clamped % 60;
  final digits = '${minutes.toString()}${secs.toString().padLeft(2, '0')}';
  return digits.length > maxDigits
      ? digits.substring(digits.length - maxDigits)
      : digits;
}

int _digitsToSeconds(String digits, int maxDigits) {
  return durationDigitsToSeconds(digits);
}

String _formatFromSeconds(int? seconds, int maxDigits) {
  if (seconds == null) {
    return '';
  }
  return formatDurationDigits(_secondsToDigits(seconds, maxDigits));
}

int _maxSecondsForDigits(int maxDigits) {
  if (maxDigits <= 2) {
    return 59;
  }
  final minutesDigits = maxDigits - 2;
  final maxMinutes = int.parse(List.filled(minutesDigits, '9').join());
  return maxMinutes * 60 + 59;
}
