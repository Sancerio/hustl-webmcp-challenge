import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_radius.dart';

/// Shows a bottom sheet to pick a rest timer duration.
/// Returns the selected duration in seconds, or null if dismissed.
Future<int?> showRestTimerPicker(
  BuildContext context, {
  int? initialSeconds,
}) async {
  final theme = Theme.of(context);
  int selectedValue = initialSeconds ?? 90;
  bool isCustomOpen = false;
  int customTotal = selectedValue;
  int customMinutes = (customTotal ~/ 60).clamp(0, 10);
  int customSeconds = (customTotal % 60).clamp(0, 55);
  // snap seconds to 5-sec steps
  customSeconds = (customSeconds ~/ 5) * 5;

  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          void applyCustom() {
            final value = (customMinutes * 60) + customSeconds;
            final clamped = value.clamp(5, 600);
            context.pop(clamped);
          }

          return _RestTimerPickerSheet(
            selectedValue: selectedValue,
            isCustomOpen: isCustomOpen,
            customMinutes: customMinutes,
            customSeconds: customSeconds,
            onSelectPreset: (value) {
              selectedValue = value;
              context.pop(value);
            },
            onToggleCustom: () {
              setState(() {
                isCustomOpen = !isCustomOpen;
              });
            },
            onMinutesChanged: (m) =>
                setState(() => customMinutes = m.clamp(0, 10)),
            onSecondsChanged: (s) =>
                setState(() => customSeconds = (s ~/ 5 * 5).clamp(0, 55)),
            onApplyCustom: applyCustom,
          );
        },
      );
    },
  );
}

/// Internal sheet UI used by the picker; extracted for testability.
class _RestTimerPickerSheet extends StatelessWidget {
  const _RestTimerPickerSheet({
    required this.selectedValue,
    required this.isCustomOpen,
    required this.customMinutes,
    required this.customSeconds,
    required this.onSelectPreset,
    required this.onToggleCustom,
    required this.onMinutesChanged,
    required this.onSecondsChanged,
    required this.onApplyCustom,
  });

  final int? selectedValue;
  final bool isCustomOpen;
  final int customMinutes;
  final int customSeconds;
  final ValueChanged<int> onSelectPreset;
  final VoidCallback onToggleCustom;
  final ValueChanged<int> onMinutesChanged;
  final ValueChanged<int> onSecondsChanged;
  final VoidCallback onApplyCustom;

  final List<int> _presetValues = const [
    15,
    30,
    45,
    60,
    90,
    120,
    180,
    300,
    600,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sv = selectedValue;
    final currentLabel = sv == null
        ? null
        : (sv % 60 == 0 ? '${sv ~/ 60}m' : '${sv}s');

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(width: 40),
                Expanded(
                  child: Text(
                    'Set Rest Timer',
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: Icon(Icons.close, color: theme.colorScheme.onSurface),
                  onPressed: () => context.pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Choose a preset or enter a custom time',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (currentLabel != null)
              Text(
                'Current: $currentLabel',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 8),
            // Presets section
            Text(
              'Presets',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                ..._presetValues.map(
                  (v) => ChoiceChip(
                    label: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6.0,
                        horizontal: 2.0,
                      ),
                      child: Text(
                        v % 60 == 0 ? '${v ~/ 60}m' : '${v}s',
                        style: TextStyle(
                          color: sv == v
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    shape: const StadiumBorder(),
                    selected: sv == v,
                    selectedColor: theme.colorScheme.primaryContainer,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    onSelected: (_) => onSelectPreset(v),
                  ),
                ),
                ChoiceChip(
                  label: const Text('Custom...'),
                  selected: isCustomOpen,
                  selectedColor: theme.colorScheme.primaryContainer,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  labelStyle: TextStyle(
                    color: isCustomOpen
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) => onToggleCustom(),
                ),
              ],
            ),

            const SizedBox(height: 12),
            // Keep a stable space; allow sheet to scroll if needed
            SizedBox(
              height: 200,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: !isCustomOpen
                    ? const SizedBox.shrink(key: ValueKey('custom-hidden'))
                    : Card(
                        key: const ValueKey('custom-visible'),
                        color: theme.colorScheme.surface,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.controlRadius,
                          side: BorderSide(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: _CupertinoPickerArea(
                            minutes: customMinutes,
                            seconds: customSeconds,
                            onMinutesChanged: onMinutesChanged,
                            onSecondsChanged: onSecondsChanged,
                            onApply: onApplyCustom,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CupertinoPickerArea extends StatefulWidget {
  const _CupertinoPickerArea({
    required this.minutes,
    required this.seconds,
    required this.onMinutesChanged,
    required this.onSecondsChanged,
    required this.onApply,
  });

  final int minutes;
  final int seconds;
  final ValueChanged<int> onMinutesChanged;
  final ValueChanged<int> onSecondsChanged;
  final VoidCallback onApply;

  @override
  State<_CupertinoPickerArea> createState() => _CupertinoPickerAreaState();
}

class _CupertinoPickerAreaState extends State<_CupertinoPickerArea> {
  late FixedExtentScrollController _minCtrl;
  late FixedExtentScrollController _secCtrl;

  @override
  void initState() {
    super.initState();
    _minCtrl = FixedExtentScrollController(
      initialItem: widget.minutes.clamp(0, 10),
    );
    final secIndex = (widget.seconds ~/ 5).clamp(0, 11);
    _secCtrl = FixedExtentScrollController(initialItem: secIndex);
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _secCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String two(int n) => n.toString().padLeft(2, '0');

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: 120,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Minutes wheel
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: CupertinoPicker(
                        key: const Key('custom_min_picker'),
                        backgroundColor: Colors.transparent,
                        scrollController: _minCtrl,
                        itemExtent: 32,
                        onSelectedItemChanged: (index) {
                          widget.onMinutesChanged(index);
                        },
                        children: List.generate(
                          11,
                          (i) => Center(
                            child: Text(
                              '$i',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      'min',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.8,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Separator
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  ':',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // Seconds wheel (5s increments)
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: CupertinoPicker(
                        key: const Key('custom_sec_picker'),
                        backgroundColor: Colors.transparent,
                        scrollController: _secCtrl,
                        itemExtent: 32,
                        onSelectedItemChanged: (index) {
                          widget.onSecondsChanged(index * 5);
                        },
                        children: List.generate(
                          12,
                          (i) => Center(
                            child: Text(
                              two(i * 5),
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      'sec',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.8,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('custom_apply'),
            onPressed: widget.onApply,
            child: const Text('Apply'),
          ),
        ),
      ],
    );
  }
}
