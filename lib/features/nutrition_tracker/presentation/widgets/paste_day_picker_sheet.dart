import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';

/// Multi-select "paste to which days?" picker for the meal clipboard. Lists the
/// surrounding days — the past two weeks (for back-filling) through the next two
/// weeks (for planning) — as checkable rows so the user can tick several at
/// once, then returns the chosen target dates via [show]. The source day itself
/// is omitted. Returns `null` if dismissed without pasting.
class PasteDayPickerSheet extends StatefulWidget {
  const PasteDayPickerSheet._({required this.foodCount, required this.options});

  final int foodCount;
  final List<DateTime> options;

  static Future<List<DateTime>?> show(
    BuildContext context, {
    required DateTime fromDate,
    required int foodCount,
    int horizonDays = 14,
    int lookbackDays = 14,
  }) {
    final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
    // Earliest past day first, the source day omitted, then forward. This lets
    // the user back-fill earlier days as well as plan ahead.
    final options = [
      for (var i = lookbackDays; i >= 1; i--) start.subtract(Duration(days: i)),
      for (var i = 1; i <= horizonDays; i++) start.add(Duration(days: i)),
    ];
    return showModalBottomSheet<List<DateTime>>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (_) =>
          PasteDayPickerSheet._(foodCount: foodCount, options: options),
    );
  }

  @override
  State<PasteDayPickerSheet> createState() => _PasteDayPickerSheetState();
}

class _PasteDayPickerSheetState extends State<PasteDayPickerSheet> {
  final Set<DateTime> _checked = <DateTime>{};

  void _toggle(DateTime date) {
    setState(() {
      _checked.contains(date) ? _checked.remove(date) : _checked.add(date);
    });
  }

  String _label(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = date.difference(today).inDays;
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    if (diff == 0) return 'Today';
    final pattern = date.year == now.year ? 'EEE, MMM d' : 'EEE, MMM d, y';
    return DateFormat(pattern).format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = _checked.length;
    final foods = widget.foodCount;
    final maxHeight = MediaQuery.of(context).size.height * 0.75;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x3,
                AppSpacing.x1,
                AppSpacing.x3,
                0,
              ),
              child: Text(
                'Paste to which days?',
                style: theme.textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x3,
                0,
                AppSpacing.x3,
                AppSpacing.x2,
              ),
              child: Text(
                '$foods ${foods == 1 ? 'food' : 'foods'} on the clipboard',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
                itemCount: widget.options.length,
                itemBuilder: (context, i) {
                  final date = widget.options[i];
                  final checked = _checked.contains(date);
                  return CheckboxListTile(
                    value: checked,
                    onChanged: (_) => _toggle(date),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(_label(date)),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x3,
                AppSpacing.x1,
                AppSpacing.x3,
                AppSpacing.x2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$n ${n == 1 ? 'day' : 'days'} selected',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: n == 0
                        ? null
                        : () {
                            Haptics.confirm();
                            context.pop(_checked.toList(growable: false));
                          },
                    child: Text('Paste to $n ${n == 1 ? 'day' : 'days'}'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
